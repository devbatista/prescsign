module Retention
  # Executa a política descrita em docs/RETENTION_POLICY.md.
  #
  # Idempotente por construção: todo recorte é por janela de tempo, então uma
  # segunda passada logo em seguida não encontra mais nada para remover. Isso
  # vale também para a simulação, que só conta o que a passada real removeria.
  #
  # **Nada aqui roda sozinho.** A própria política condiciona a ativação em
  # produção a validação jurídica e a uma estratégia de backup — e essa
  # estratégia ainda é pendência aberta (seção 4 de docs/PENDENCIAS.md). Por
  # isso não há agendador: apagar é ato deliberado, via
  # `rake retention:cleanup APPLY=1` ou `RetentionCleanupJob` com `dry_run:
  # false`. O padrão dos dois pontos de entrada é simular.
  class CleanupService
    BATCH_SIZE = 1_000

    # Arquivos do topo de tmp/ que têm dono e não são resíduo nosso: apagar o
    # local_secret.txt troca o secret_key_base de desenvolvimento, e os outros
    # dois são marcadores do Rails. A varredura também não desce em
    # subdiretório — cache/, pids/, sockets/ e storage/ são gerenciados pelo
    # framework, não por esta política.
    RAILS_MANAGED_TMP_FILES = %w[.keep local_secret.txt restart.txt].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    # `tmp_root` existe para o spec varrer um diretório descartável: apontado
    # para o tmp/ real, um teste apagaria arquivos de verdade do repositório.
    def initialize(dry_run: true, now: Time.current, tmp_root: Rails.root.join("tmp"))
      @dry_run = dry_run
      @now = now
      @tmp_root = Pathname.new(tmp_root)
    end

    def call
      report = {
        audit_logs: purge_audit_logs,
        delivery_logs: purge_delivery_logs,
        unattached_blobs: purge_unattached_blobs,
        tmp_files: purge_tmp_files,
        document_versions: 0
      }

      log!(report)
      report
    end

    private

    attr_reader :dry_run, :now, :tmp_root

    def retention
      Rails.application.config.x.retention
    end

    def purge_audit_logs
      delete_in_batches(AuditLog, scope_older_than(AuditLog, :occurred_at, retention.audit_logs_days))
    end

    def purge_delivery_logs
      delete_in_batches(DeliveryLog, scope_older_than(DeliveryLog, :attempted_at, retention.delivery_logs_days))
    end

    # Blob sem attachment é resíduo de upload interrompido — o PDF que vingou
    # está preso à versão do documento e não aparece aqui. `purge` remove o
    # registro e o arquivo no storage; `delete_all` deixaria o arquivo órfão.
    def purge_unattached_blobs
      scope = scope_older_than(ActiveStorage::Blob.unattached, :created_at, retention.unattached_blobs_days)
      return 0 if scope.nil?
      return scope.count if dry_run

      count = 0
      scope.find_each(batch_size: BATCH_SIZE) do |blob|
        blob.purge
        count += 1
      end
      count
    end

    def purge_tmp_files
      days = retention.tmp_files_days
      return 0 if days.blank?

      return 0 unless tmp_root.directory?

      cutoff = cutoff_for(days)
      count = 0

      Dir.children(tmp_root).each do |entry|
        next if RAILS_MANAGED_TMP_FILES.include?(entry)

        path = tmp_root.join(entry)
        next unless File.file?(path)
        next unless File.mtime(path) < cutoff

        File.delete(path) unless dry_run
        count += 1
      end

      count
    end

    # Recorta `relation` no que for anterior à janela. Devolve nil quando a
    # janela não está configurada, para o chamador distinguir "nada a remover"
    # de "categoria desligada".
    def scope_older_than(relation, column, days)
      return nil if days.blank?

      relation.where(column => ...cutoff_for(days))
    end

    def cutoff_for(days)
      now - days.to_i.days
    end

    def delete_in_batches(model, scope)
      return 0 if scope.nil?
      return scope.count if dry_run

      count = 0
      scope.in_batches(of: BATCH_SIZE) do |batch|
        count += model.where(id: batch.pluck(:id)).delete_all
      end
      count
    end

    def log!(report)
      Rails.logger.info(
        {
          event: "retention_cleanup",
          mode: dry_run ? "dry_run" : "apply",
          cutoff_reference: now.utc.iso8601,
          # Versões de documento e os PDFs presos a elas nunca entram na
          # varredura: DocumentVersion tem `before_destroy :prevent_destroy` e
          # a política as trata como permanentes. Fica explícito no log para
          # que o zero não seja lido como "não havia nada".
          document_versions_policy: "permanent",
          removed: report
        }
      )
    end
  end
end

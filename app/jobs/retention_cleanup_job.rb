# Executa a política de retenção (docs/RETENTION_POLICY.md) fora do ciclo de
# requisição. Não há agendador no projeto e este job não se reenfileira: quem
# dispara é o `rake retention:cleanup` ou um agendador externo, quando as
# pré-condições da política estiverem cumpridas.
#
# O padrão é simular. Remover exige `dry_run: false` explícito.
class RetentionCleanupJob < ApplicationJob
  queue_as :default

  def perform(dry_run: true)
    Retention::CleanupService.call(dry_run: dry_run)
  rescue StandardError => e
    Observability::CriticalAlertService.notify!(
      category: "retention_cleanup_failure",
      exception: e,
      context: { job: self.class.name, dry_run: dry_run }
    )
    raise
  end
end

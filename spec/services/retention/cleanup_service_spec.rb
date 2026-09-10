require "rails_helper"
require "tmpdir"

RSpec.describe Retention::CleanupService do
  include WebSpecHelpers

  let(:now) { Time.utc(2026, 9, 9, 12, 0, 0) }
  let(:tmp_root) { Pathname.new(Dir.mktmpdir("retention-spec")) }

  after { FileUtils.remove_entry(tmp_root) if tmp_root.exist? }

  def configure_retention!(audit_logs_days: 2190, delivery_logs_days: 1825,
                           tmp_files_days: 7, unattached_blobs_days: 2,
                           document_versions_days: nil)
    options = ActiveSupport::OrderedOptions.new
    options.audit_logs_days = audit_logs_days
    options.delivery_logs_days = delivery_logs_days
    options.tmp_files_days = tmp_files_days
    options.unattached_blobs_days = unattached_blobs_days
    options.document_versions_days = document_versions_days
    options.documents_permanent = document_versions_days.nil?
    allow(Rails.application.config.x).to receive(:retention).and_return(options)
  end

  def service(dry_run: true)
    described_class.new(dry_run: dry_run, now: now, tmp_root: tmp_root)
  end

  def create_audit_log(occurred_at:)
    AuditLog.create!(resource: organization, action: "created", occurred_at: occurred_at)
  end

  def create_delivery_log(attempted_at:)
    DeliveryLog.create!(
      channel: "email", status: "queued", recipient: "paciente@example.com", attempted_at: attempted_at
    )
  end

  def write_tmp_file(name, mtime:)
    path = tmp_root.join(name)
    File.write(path, "resíduo")
    File.utime(mtime, mtime, path)
    path
  end

  let(:organization) { create_organization }

  before { configure_retention! }

  describe "janela de tempo" do
    it "remove só o que está fora da janela e preserva o que está dentro" do
      fora = create_audit_log(occurred_at: now - 2191.days)
      dentro = create_audit_log(occurred_at: now - 2189.days)

      expect(service(dry_run: false).call[:audit_logs]).to eq(1)
      expect(AuditLog.exists?(fora.id)).to be(false)
      expect(AuditLog.exists?(dentro.id)).to be(true)
    end

    it "aplica a janela própria de cada categoria" do
      create_audit_log(occurred_at: now - 2191.days)
      create_delivery_log(attempted_at: now - 1826.days)
      create_delivery_log(attempted_at: now - 1824.days)

      report = service(dry_run: false).call

      expect(report[:audit_logs]).to eq(1)
      expect(report[:delivery_logs]).to eq(1)
    end

    it "é idempotente: a segunda passada não encontra mais nada" do
      create_audit_log(occurred_at: now - 2191.days)
      create_delivery_log(attempted_at: now - 1826.days)

      service(dry_run: false).call
      segunda = service(dry_run: false).call

      expect(segunda.values.sum).to eq(0)
    end

    it "não remove nada quando a janela da categoria não está configurada" do
      configure_retention!(audit_logs_days: nil)
      antigo = create_audit_log(occurred_at: now - 5000.days)

      expect(service(dry_run: false).call[:audit_logs]).to eq(0)
      expect(AuditLog.exists?(antigo.id)).to be(true)
    end
  end

  describe "simulação" do
    it "conta o que removeria sem remover" do
      antigo = create_audit_log(occurred_at: now - 2191.days)
      write_tmp_file("residuo.csv", mtime: now - 8.days)

      report = service(dry_run: true).call

      expect(report[:audit_logs]).to eq(1)
      expect(report[:tmp_files]).to eq(1)
      expect(AuditLog.exists?(antigo.id)).to be(true)
      expect(tmp_root.join("residuo.csv")).to exist
    end
  end

  # A garantia mais importante do serviço. DocumentVersion tem
  # `before_destroy :prevent_destroy`, e um `delete_all` passaria por cima dessa
  # guarda sem erro — é exatamente o que este teste existe para impedir.
  describe "versões de documento" do
    let(:doctor) { create_doctor(organization: organization) }
    let(:patient) { create_patient(user: doctor, organization: organization) }

    before do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.document.document_versions.update_all(generated_at: now - 5000.days)
    end

    it "nunca remove versões, por mais antigas que sejam" do
      expect { service(dry_run: false).call }.not_to change(DocumentVersion, :count)
    end

    it "nunca remove versões nem quando uma janela é configurada para elas" do
      configure_retention!(document_versions_days: 1)

      expect { service(dry_run: false).call }.not_to change(DocumentVersion, :count)
      expect(service(dry_run: false).call[:document_versions]).to eq(0)
    end
  end

  describe "arquivos de tmp/" do
    it "remove arquivo do topo fora da janela" do
      write_tmp_file("antigo.csv", mtime: now - 8.days)

      expect(service(dry_run: false).call[:tmp_files]).to eq(1)
      expect(tmp_root.join("antigo.csv")).not_to exist
    end

    it "preserva arquivo dentro da janela" do
      write_tmp_file("recente.csv", mtime: now - 6.days)

      expect(service(dry_run: false).call[:tmp_files]).to eq(0)
      expect(tmp_root.join("recente.csv")).to exist
    end

    it "preserva os arquivos gerenciados pelo Rails" do
      described_class::RAILS_MANAGED_TMP_FILES.each do |name|
        write_tmp_file(name, mtime: now - 999.days)
      end

      expect(service(dry_run: false).call[:tmp_files]).to eq(0)
      described_class::RAILS_MANAGED_TMP_FILES.each do |name|
        expect(tmp_root.join(name)).to exist
      end
    end

    it "não desce em subdiretório" do
      FileUtils.mkdir_p(tmp_root.join("cache"))
      antigo_aninhado = tmp_root.join("cache", "antigo.txt")
      File.write(antigo_aninhado, "cache")
      File.utime(now - 999.days, now - 999.days, antigo_aninhado)
      File.utime(now - 999.days, now - 999.days, tmp_root.join("cache"))

      expect(service(dry_run: false).call[:tmp_files]).to eq(0)
      expect(antigo_aninhado).to exist
      expect(tmp_root.join("cache")).to be_directory
    end
  end

  describe "blobs órfãos do Active Storage" do
    def create_blob(created_at:)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF resíduo"), filename: "orfao.pdf", content_type: "application/pdf"
      )
      blob.update_columns(created_at: created_at)
      blob
    end

    it "remove blob sem attachment fora da janela" do
      orfao = create_blob(created_at: now - 3.days)

      expect(service(dry_run: false).call[:unattached_blobs]).to eq(1)
      expect(ActiveStorage::Blob.exists?(orfao.id)).to be(false)
    end

    it "preserva blob sem attachment dentro da janela" do
      recente = create_blob(created_at: now - 1.day)

      expect(service(dry_run: false).call[:unattached_blobs]).to eq(0)
      expect(ActiveStorage::Blob.exists?(recente.id)).to be(true)
    end

    it "preserva blob preso a uma versão de documento, por mais antigo que seja" do
      doctor = create_doctor(organization: organization)
      patient = create_patient(user: doctor, organization: organization)
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      version = prescription.document.document_versions.first
      version.attach_pdf!("%PDF assinado")
      blob = version.pdf_file.blob
      blob.update_columns(created_at: now - 5000.days)

      expect(service(dry_run: false).call[:unattached_blobs]).to eq(0)
      expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    end
  end
end

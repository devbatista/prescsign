require "rails_helper"

RSpec.describe RetentionCleanupJob do
  it "simula por padrão" do
    expect(Retention::CleanupService).to receive(:call).with(dry_run: true)

    described_class.perform_now
  end

  it "remove quando recebe dry_run: false explícito" do
    expect(Retention::CleanupService).to receive(:call).with(dry_run: false)

    described_class.perform_now(dry_run: false)
  end

  it "alerta e propaga quando a limpeza falha" do
    erro = StandardError.new("boom")
    allow(Retention::CleanupService).to receive(:call).and_raise(erro)

    expect(Observability::CriticalAlertService).to receive(:notify!).with(
      hash_including(category: "retention_cleanup_failure", exception: erro)
    )

    expect { described_class.perform_now }.to raise_error(erro)
  end
end

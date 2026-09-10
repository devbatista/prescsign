namespace :retention do
  desc "Aplica a política de retenção (docs/RETENTION_POLICY.md). Simula por padrão; APPLY=1 remove de verdade."
  task cleanup: :environment do
    apply = ENV["APPLY"].to_s.strip == "1"
    report = Retention::CleanupService.call(dry_run: !apply)

    puts(apply ? "Retenção aplicada:" : "Simulação (nada foi removido). Use APPLY=1 para aplicar:")
    report.each { |category, count| puts format("  %-20s %d", category, count) }
    puts "  document_versions e os PDFs presos a elas são permanentes e nunca entram na varredura."
  end
end

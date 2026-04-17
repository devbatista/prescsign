require "rails_helper"

RSpec.describe "Production security configuration" do
  it "forces SSL in production environment config" do
    production_config_path = Rails.root.join("config/environments/production.rb")
    content = File.read(production_config_path)

    expect(content).to match(/^\s*config\.force_ssl\s*=\s*true\s*$/)
  end
end

module SncrTokenStoreHelpers
  # Stub do Sncr::TokenStore com backing em memória (por user_id), para as
  # request specs não dependerem de Redis. Retorna o hash de backing, útil para
  # asserções (ex.: `expect(backing[user.id]).to eq("jwt")`).
  def stub_sncr_token_store
    backing = {}
    allow(Sncr::TokenStore).to receive(:new) do |user_id:, **|
      instance_double(Sncr::TokenStore).tap do |store|
        allow(store).to receive(:write) { |token| backing[user_id] = token }
        allow(store).to receive(:read) { backing[user_id] }
        allow(store).to receive(:clear) { backing.delete(user_id) }
      end
    end
    backing
  end

  # Liga o modo simulado do SNCR (Sncr::FakeClient) durante o bloco.
  def with_sncr_fake
    original = Rails.application.config.x.sncr.fake
    Rails.application.config.x.sncr.fake = true
    yield
  ensure
    Rails.application.config.x.sncr.fake = original
  end

  # CNPJ da plataforma para os specs que exercitam o endpoint de
  # Especial/Retenção, que o exige. Sem isto o spec passa em quem tem o valor no
  # .env e falha no CI, que não tem — o mesmo tropeço que já custou uma correção
  # em spec/requests/app/about_spec.rb.
  def with_sncr_platform_cnpj(cnpj = "12345678000195")
    original = Rails.application.config.x.sncr.platform_cnpj
    Rails.application.config.x.sncr.platform_cnpj = cnpj
    yield
  ensure
    Rails.application.config.x.sncr.platform_cnpj = original
  end
end

RSpec.configure do |config|
  config.include SncrTokenStoreHelpers
end

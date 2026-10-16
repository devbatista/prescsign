# O Rails 8 desenha as rotas sob demanda em test, e o Devise só registra os
# serializadores do Warden quando o `devise_for` roda. O `sign_in` do primeiro
# exemplo do processo acontecia antes disso: a sessão guardava o objeto User em
# vez de `[[id], salt]`, e a requisição seguinte quebrava com ArgumentError em
# `serialize_from_session`. Na suíte completa não aparecia, porque algum
# exemplo anterior já tinha carregado as rotas — só rodando o spec sozinho.
RSpec.configure do |config|
  config.before(:suite) do
    Rails.application.reload_routes_unless_loaded
  end
end

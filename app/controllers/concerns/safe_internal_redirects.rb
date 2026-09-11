# Só aceita caminhos internos como destino de retorno, para que um parâmetro
# vindo da URL não vire open redirect.
#
# Extraído de App::Sncr::AuthController quando o retorno passou a atravessar
# também o painel de numerações: a mesma regra em dois controllers.
module SafeInternalRedirects
  extend ActiveSupport::Concern

  private

  # Caminho interno começa com "/" e não com "//" — esta última forma é
  # protocol-relative e levaria para outro host.
  def safe_internal_path(value)
    value if value.is_a?(String) && value.start_with?("/") && !value.start_with?("//")
  end
end

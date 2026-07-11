require "devise/failure_app"

# Sends unauthenticated web requests (on app./admin.) to the login subdomain,
# instead of Devise's default same-host /entrar (which wouldn't route there).
class SubdomainFailureApp < Devise::FailureApp
  def redirect_url
    "#{request.scheme}://#{login_host}/sign-in"
  end

  private

  def login_host
    host = request.host
    base = host.include?(".") ? host.split(".").last(2).join(".") : host
    login = "login.#{base}"

    port = request.port
    default_port = request.scheme == "https" ? 443 : 80
    port && port != default_port ? "#{login}:#{port}" : login
  end
end

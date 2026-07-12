require "devise/failure_app"

# Sends unauthenticated web requests (on app./admin.) to the login subdomain,
# instead of Devise's default same-host /entrar (which wouldn't route there).
class SubdomainFailureApp < Devise::FailureApp
  def redirect_url
    "#{request.scheme}://#{login_host}/sign-in"
  end

  # The JWT API (/api/v1) must answer 401 for unauthenticated requests, never a
  # redirect — even when the request format is HTML. Only the web layer redirects
  # to the login subdomain. (The API is removed in Fase 5; this keeps it correct
  # while both layers coexist.)
  def http_auth?
    api_request? || super
  end

  private

  # Warden rewrites PATH_INFO to "/unauthenticated" before invoking the failure
  # app, so request.path is useless here — use the original attempted path.
  def api_request?
    attempted = warden_options[:attempted_path].presence || request.original_fullpath
    attempted.to_s.match?(%r{\A/(v1|api)(/|\z)})
  end

  def login_host
    host = request.host
    base = host.include?(".") ? host.split(".").last(2).join(".") : host
    login = "login.#{base}"

    port = request.port
    default_port = request.scheme == "https" ? 443 : 80
    port && port != default_port ? "#{login}:#{port}" : login
  end
end

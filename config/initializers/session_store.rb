# Share the session cookie across all subdomains (login./register./app./admin.)
# so a login on login.prescsign.local authenticates app./admin. too.
#
# domain: :all derives the cookie domain from the request host using tld_length
# (e.g. app.prescsign.local -> .prescsign.local). Override with SESSION_COOKIE_DOMAIN.
Rails.application.config.session_store :cookie_store,
  key: "_prescsign_session",
  domain: (ENV["SESSION_COOKIE_DOMAIN"].presence || :all),
  same_site: :lax

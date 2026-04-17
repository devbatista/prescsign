allowed_origins = Rails.application.config.x.cors.allowed_origins

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)

    resource "*",
             headers: %w[Accept Authorization Content-Type Origin X-Organization-Id],
             expose: %w[X-Request-Id],
             methods: %i[get post put patch delete options head],
             max_age: 600
  end
end

import Config

# Production port (HTTPS)
config :ignite,
  port: 4443

# SSL/TLS — uncomment and set paths to your certificate files.
# For self-signed certs (testing): mix ignite.gen.cert
# For production: use Let's Encrypt or your CA.
#
# config :ignite,
#   ssl: [
#     certfile: "priv/ssl/cert.pem",
#     keyfile: "priv/ssl/key.pem"
#   ]

# Optional: HTTP-to-HTTPS redirect listener.
# When set, Ignite starts a plain HTTP listener on this port that
# 301-redirects all requests to the HTTPS port above.
#
# config :ignite,
#   http_redirect_port: 4080

# HSTS — tells browsers to only use HTTPS for this domain.
config :ignite,
  hsts: true,
  hsts_max_age: 31_536_000

# Production database — defaults here, overridden by runtime.exs env vars.
# In a release, set DATABASE_PATH to configure the SQLite path.
config :ignite, MyApp.Repo,
  database: "ignite_prod.db",
  pool_size: 10

# Production logging — less verbose
config :logger, level: :info

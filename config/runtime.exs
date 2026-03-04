import Config

# runtime.exs is evaluated at boot time — both in `iex -S mix` and in
# a release. Use System.get_env/1 here to read environment variables.
# These override values set in config.exs / prod.exs / test.exs.

if config_env() == :prod do
  # Port — default to 4443 for HTTPS, override with $PORT
  port =
    case System.get_env("PORT") do
      nil -> 4443
      val -> String.to_integer(val)
    end

  config :ignite, port: port

  # Database path (SQLite).
  # For production, set DATABASE_PATH to an absolute path on the server.
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: export DATABASE_PATH=/var/data/ignite_prod.db
      """

  config :ignite, MyApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Secret key for session cookie signing.
  # Must be at least 64 bytes for security.
  # Generate one with: openssl rand -base64 64
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: openssl rand -base64 64
      """

  config :ignite, secret_key_base: secret_key_base

  # SSL certificate paths (optional).
  # Omit these to run plain HTTP behind a reverse proxy (nginx, Caddy, etc.).
  ssl_certfile = System.get_env("SSL_CERTFILE")
  ssl_keyfile = System.get_env("SSL_KEYFILE")

  if ssl_certfile && ssl_keyfile do
    config :ignite,
      ssl: [
        certfile: ssl_certfile,
        keyfile: ssl_keyfile
      ]
  end

  # HTTP→HTTPS redirect port (optional)
  case System.get_env("HTTP_REDIRECT_PORT") do
    nil -> :ok
    val -> config(:ignite, http_redirect_port: String.to_integer(val))
  end

  # Rate limiting override (optional)
  case System.get_env("RATE_LIMIT_MAX") do
    nil ->
      :ok

    val ->
      window = String.to_integer(System.get_env("RATE_LIMIT_WINDOW_MS") || "60000")
      config :ignite, rate_limit: [max_requests: String.to_integer(val), window_ms: window]
  end
end

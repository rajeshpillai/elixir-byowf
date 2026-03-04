import Config

# Store the current environment so runtime code can check it without
# calling Mix.env() (which isn't available in releases).
config :ignite, env: config_env()

# Logger configuration — include request_id in every log line.
# Logger.metadata(request_id: ...) is called per-request in the Cowboy adapter;
# this config tells the default formatter to print it.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Database configuration (SQLite — zero infrastructure needed).
# To switch to PostgreSQL: change adapter in Repo, add {:postgrex, "~> 0.19"},
# and update this config with hostname, username, password, database.
config :ignite, MyApp.Repo,
  database: "ignite_dev.db",
  pool_size: 5

config :ignite,
  ecto_repos: [MyApp.Repo],
  port: 4000

# Rate limiting — per-IP sliding window.
# Override per-environment or at runtime via RATE_LIMIT_MAX / RATE_LIMIT_WINDOW_MS.
config :ignite,
  rate_limit: [
    max_requests: 100,
    window_ms: 60_000
  ]

# Import environment-specific config (config/dev.exs, config/test.exs, etc.)
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end

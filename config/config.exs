import Config

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
  ecto_repos: [MyApp.Repo]

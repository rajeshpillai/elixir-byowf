import Config

# Database configuration (SQLite — zero infrastructure needed).
# To switch to PostgreSQL: change adapter in Repo, add {:postgrex, "~> 0.19"},
# and update this config with hostname, username, password, database.
config :ignite, MyApp.Repo,
  database: "ignite_dev.db",
  pool_size: 5

config :ignite,
  ecto_repos: [MyApp.Repo]

import Config

# Use a different port so tests don't conflict with a running dev server.
config :ignite, port: 4002

# Use a separate test database to avoid polluting dev data.
config :ignite, MyApp.Repo,
  database: "ignite_test.db",
  pool_size: 5

# Reduce log noise during tests.
config :logger, level: :warning

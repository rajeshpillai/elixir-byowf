ExUnit.start()

# Ensure the test database is migrated before running tests.
# This mirrors what `mix ecto.migrate` does, but runs automatically.
Ecto.Migrator.run(MyApp.Repo, :up, all: true, log: false)

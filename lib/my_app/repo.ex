defmodule MyApp.Repo do
  @moduledoc """
  The database repository.

  Wraps Ecto's repository pattern — provides functions to insert, update,
  delete, and query records.

  Uses SQLite for zero-setup local development. To switch to PostgreSQL,
  change the adapter to `Ecto.Adapters.Postgres`, add `{:postgrex, "~> 0.19"}`
  to mix.exs, and update config/config.exs with connection details.
  """

  use Ecto.Repo,
    otp_app: :ignite,
    adapter: Ecto.Adapters.SQLite3
end

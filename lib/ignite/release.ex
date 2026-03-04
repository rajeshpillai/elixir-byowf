defmodule Ignite.Release do
  @moduledoc """
  Release tasks that can be run without Mix.

  In a release, `mix ecto.migrate` is not available because Mix is a
  build tool that is not shipped with the release. This module provides
  the same functionality, callable from the release binary.

  ## Usage

      # Run all pending migrations:
      bin/ignite eval "Ignite.Release.migrate()"

      # Rollback the last migration:
      bin/ignite eval "Ignite.Release.rollback(MyApp.Repo, 20240301120000)"

      # Create the database:
      bin/ignite eval "Ignite.Release.create_db()"
  """

  @app :ignite

  @doc """
  Runs all pending Ecto migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls back the given repo to the specified migration version.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Creates the database (ensures the SQLite file exists).
  """
  def create_db do
    load_app()

    for repo <- repos() do
      repo.__adapter__().storage_up(repo.config())
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:ecto_sql)
    Application.load(@app)
  end
end

defmodule MyApp.ApiController do
  @moduledoc """
  Demonstrates JSON API responses.
  """

  import Ignite.Controller

  def status(conn) do
    json(conn, %{
      status: "ok",
      framework: "Ignite",
      elixir_version: System.version(),
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    })
  end

  def echo(conn) do
    json(conn, %{
      echo: conn.params,
      received_at: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end

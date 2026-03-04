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

  def health(conn) do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_s = div(uptime_ms, 1000)

    json(conn, %{
      status: "ok",
      uptime_seconds: uptime_s,
      uptime_human: format_uptime(uptime_s),
      memory: %{
        total_mb: Float.round(memory[:total] / 1_048_576, 1),
        processes_mb: Float.round(memory[:processes] / 1_048_576, 1)
      },
      processes: :erlang.system_info(:process_count),
      atoms: :erlang.system_info(:atom_count),
      ports: :erlang.system_info(:port_count),
      schedulers: :erlang.system_info(:schedulers_online),
      otp_release: :erlang.system_info(:otp_release) |> List.to_string(),
      elixir_version: System.version(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    mins = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m #{secs}s"
      mins > 0 -> "#{mins}m #{secs}s"
      true -> "#{secs}s"
    end
  end
end

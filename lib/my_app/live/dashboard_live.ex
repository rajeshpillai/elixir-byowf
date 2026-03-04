defmodule MyApp.DashboardLive do
  @moduledoc """
  A live dashboard showing BEAM VM stats that update every second.

  Demonstrates server-push via handle_info/2 — the server sends
  updates to the browser without any user interaction.
  """

  use Ignite.LiveView

  def mount(_params, _session) do
    # Schedule the first tick — subsequent ticks are scheduled in handle_info
    Process.send_after(self(), :tick, 1000)
    {:ok, gather_stats()}
  end

  # Called every second by the handler via Process.send_after
  def handle_info(:tick, _assigns) do
    Process.send_after(self(), :tick, 1000)
    {:noreply, gather_stats()}
  end

  def handle_event("gc", _params, assigns) do
    :erlang.garbage_collect()
    {:noreply, assigns}
  end

  def render(assigns) do
    ~L"""
    <div id="dashboard" style="max-width: 600px; margin: 0 auto; text-align: left;">
      <h1>BEAM Dashboard</h1>
      <p style="color: #888; font-size: 14px;">Auto-refreshes every second</p>

      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 20px 0;">
        <div style="background: #f0f4ff; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Uptime</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.uptime %></div>
        </div>

        <div style="background: #f0fff4; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Processes</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.process_count %></div>
        </div>

        <div style="background: #fff8f0; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Memory (Total)</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.total_memory %> MB</div>
        </div>

        <div style="background: #fff0f0; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Memory (Processes)</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.process_memory %> MB</div>
        </div>

        <div style="background: #f5f0ff; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Atoms</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.atom_count %></div>
        </div>

        <div style="background: #f0ffff; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Ports</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.port_count %></div>
        </div>

        <div style="background: #fffff0; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">Schedulers</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.schedulers %></div>
        </div>

        <div style="background: #f0f0f0; padding: 16px; border-radius: 8px;">
          <div style="font-size: 14px; color: #666;">OTP Release</div>
          <div style="font-size: 24px; font-weight: bold;"><%= assigns.otp_release %></div>
        </div>
      </div>

      <button ignite-click="gc" style="padding: 8px 16px; background: #e74c3c; color: white; border: none; border-radius: 4px; cursor: pointer;">
        Run GC
      </button>

      <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #eee; text-align: center;">
        <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
        <a href="/counter" ignite-navigate="/counter" style="margin: 0 8px;">Counter</a>
        <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin: 0 8px;">Shared Counter</a>
      </div>
    </div>
    """
  end

  defp gather_stats do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      uptime: format_uptime(uptime_ms),
      process_count: :erlang.system_info(:process_count),
      total_memory: Float.round(memory[:total] / 1_048_576, 1),
      process_memory: Float.round(memory[:processes] / 1_048_576, 1),
      atom_count: :erlang.system_info(:atom_count),
      port_count: :erlang.system_info(:port_count),
      schedulers: :erlang.system_info(:schedulers_online),
      otp_release: :erlang.system_info(:otp_release) |> List.to_string()
    }
  end

  defp format_uptime(ms) do
    total_seconds = div(ms, 1000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
      minutes > 0 -> "#{minutes}m #{seconds}s"
      true -> "#{seconds}s"
    end
  end
end

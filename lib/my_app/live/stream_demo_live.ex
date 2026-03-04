defmodule MyApp.StreamDemoLive do
  @moduledoc """
  Demonstrates LiveView Streams — efficiently updating large lists.

  Instead of re-sending all items on every update, streams send only
  individual insert/delete operations over the wire. Adding one event
  to a list of 100 sends ~100 bytes, not the entire list's HTML.

  This demo auto-generates system events every 2 seconds and displays
  them in a scrollable log. Each new event is a single stream insert.
  """

  use Ignite.LiveView

  @event_types ["info", "warning", "debug", "error"]

  @impl true
  def mount(_params, _session) do
    Process.send_after(self(), :generate_event, 2000)

    assigns = %{event_count: 0}

    # Initialize the stream with a render function — this defines how each
    # item looks. The render function is called by the handler when building
    # the wire payload. Items are freed from memory after being sent.
    assigns =
      stream(assigns, :events, [],
        render: fn event ->
          color = event_color(event.type)

          """
          <div id="events-#{event.id}"
               style="padding: 8px 12px; margin: 4px 0; background: #{color};
                      border-radius: 6px; font-size: 14px; display: flex;
                      justify-content: space-between; align-items: center;">
            <span>
              <strong>[#{String.upcase(event.type)}]</strong> #{event.message}
            </span>
            <span style="color: #888; font-size: 12px;">#{event.time}</span>
          </div>
          """
        end
      )

    {:ok, assigns}
  end

  # Auto-generate a random event every 2 seconds
  @impl true
  def handle_info(:generate_event, assigns) do
    Process.send_after(self(), :generate_event, 2000)
    event = random_event(assigns.event_count + 1)

    assigns =
      assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  @impl true
  def handle_event("add_event", _params, assigns) do
    event = %{
      id: assigns.event_count + 1,
      type: "info",
      message: "Manual event from user",
      time: format_time()
    }

    assigns =
      assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  @impl true
  def handle_event("clear_log", _params, assigns) do
    assigns =
      assigns
      |> Map.put(:event_count, 0)
      |> stream(:events, [], reset: true)

    {:noreply, assigns}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div id="stream-demo" style="max-width: 700px; margin: 0 auto;">
      <h1>LiveView Streams Demo</h1>
      <p style="color: #888; font-size: 14px;">
        Events stream in every 2 seconds — only new items are sent over the wire
      </p>

      <div style="display: flex; gap: 12px; margin: 16px 0; align-items: center;">
        <button ignite-click="add_event"
                style="padding: 8px 16px; background: #3498db; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Add Event
        </button>
        <button ignite-click="clear_log"
                style="padding: 8px 16px; background: #e74c3c; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Clear Log
        </button>
        <span style="color: #666; font-size: 14px;">
          Total events: <strong><%= assigns.event_count %></strong>
        </span>
      </div>

      <div ignite-stream="events"
           style="max-height: 400px; overflow-y: auto; border: 1px solid #eee;
                  border-radius: 8px; padding: 8px;">
      </div>

      <div style="margin-top: 24px; padding: 16px; background: #f0fff4;
                  border-radius: 8px; text-align: left;">
        <strong>How it works:</strong>
        <ul style="margin: 8px 0; padding-left: 20px;">
          <li>Each event is a single <code>stream_insert</code> — NOT a full list re-render</li>
          <li>The wire sends <code>{"streams": {"events": {"inserts": [...]}}}</code></li>
          <li>The event count uses normal diffing: <code>{"d": {"0": "5"}}</code></li>
          <li>Open DevTools Network tab (WS) to see the tiny payloads</li>
          <li>"Clear Log" sends a <code>reset</code> operation — clears all items at once</li>
        </ul>
      </div>

      <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #eee;
                  text-align: center;">
        <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
        <a href="/" style="margin: 0 8px;">Home</a>
        <a href="/counter" ignite-navigate="/counter" style="margin: 0 8px;">Counter</a>
        <a href="/dashboard" ignite-navigate="/dashboard" style="margin: 0 8px;">Dashboard</a>
        <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin: 0 8px;">Shared Counter</a>
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp random_event(id) do
    type = Enum.random(@event_types)

    messages = %{
      "info" => [
        "System running normally",
        "Health check passed",
        "Cache refreshed",
        "New connection established",
        "Background job completed"
      ],
      "warning" => [
        "Memory usage high",
        "Response time slow",
        "Retry attempt #3",
        "Rate limit approaching",
        "Disk usage at 80%"
      ],
      "debug" => [
        "Query executed in 2ms",
        "Cache hit ratio: 94%",
        "GC cycle complete",
        "Process count: 158",
        "ETS table size: 1024"
      ],
      "error" => [
        "Connection timeout",
        "Invalid API key",
        "File not found",
        "Database connection lost",
        "Permission denied"
      ]
    }

    %{
      id: id,
      type: type,
      message: Enum.random(messages[type]),
      time: format_time()
    }
  end

  defp format_time do
    {{_, _, _}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end

  defp event_color("info"), do: "#e8f4f8"
  defp event_color("warning"), do: "#fff8e1"
  defp event_color("debug"), do: "#f3e5f5"
  defp event_color("error"), do: "#ffebee"
  defp event_color(_), do: "#f5f5f5"
end

defmodule MyApp.HooksDemoLive do
  @moduledoc """
  Demonstrates JS Hooks — client-side lifecycle callbacks for
  integrating third-party JavaScript with LiveView.

  Hooks receive mounted(), updated(), and destroyed() callbacks
  and can push events back to the server via pushEvent().
  """

  use Ignite.LiveView

  @impl true
  def mount(_params, _session) do
    {:ok, %{
      server_clicks: 0,
      hook_events: [],
      copy_text: "Hello from Ignite! Copy me to clipboard."
    }}
  end

  @impl true
  def handle_event("server_click", _params, assigns) do
    {:noreply, %{assigns | server_clicks: assigns.server_clicks + 1}}
  end

  # Receives events pushed from JS hooks via pushEvent()
  @impl true
  def handle_event("clipboard_result", params, assigns) do
    status = if params["success"] == "true", do: "copied", else: "failed"
    event = "Clipboard: #{status}"
    {:noreply, %{assigns | hook_events: [event | Enum.take(assigns.hook_events, 4)]}}
  end

  @impl true
  def handle_event("local_time", params, assigns) do
    event = "Client time: #{params["time"]}"
    {:noreply, %{assigns | hook_events: [event | Enum.take(assigns.hook_events, 4)]}}
  end

  @impl true
  def render(assigns) do
    events_html = if assigns.hook_events == [] do
      "<em>No hook events yet — click the buttons above</em>"
    else
      assigns.hook_events
      |> Enum.map(fn e -> "<li>#{e}</li>" end)
      |> Enum.join("\n")
    end

    """
    <div id="hooks-demo" style="max-width: 600px; margin: 0 auto;">
      <h1>JS Hooks Demo</h1>
      <p style="color: #888; font-size: 14px;">
        Client-side JS interop with server-rendered LiveView
      </p>

      <div style="margin: 24px 0; padding: 20px; background: #f8f9fa; border-radius: 8px;">
        <h3 style="margin-top: 0;">Server State</h3>
        <p>Server clicks: <strong>#{assigns.server_clicks}</strong></p>
        <button ignite-click="server_click"
                style="padding: 8px 16px; background: #3498db; color: white; border: none; border-radius: 6px; cursor: pointer;">
          Server Click
        </button>
      </div>

      <div style="margin: 24px 0; padding: 20px; background: #fff8f0; border-radius: 8px;">
        <h3 style="margin-top: 0;">Clipboard Hook</h3>
        <p style="font-size: 14px; color: #666;">Uses the Clipboard API — a pure JS operation that LiveView can't do server-side</p>
        <div id="clipboard-hook" ignite-hook="CopyToClipboard" data-text="#{assigns.copy_text}"
             style="display: flex; gap: 12px; align-items: center;">
          <code style="padding: 8px 12px; background: #eee; border-radius: 4px; flex: 1;">#{assigns.copy_text}</code>
          <button onclick="this.parentElement.querySelector('[ignite-hook]') || void(0)"
                  style="padding: 8px 16px; background: #9b59b6; color: white; border: none; border-radius: 6px; cursor: pointer; white-space: nowrap;"
                  id="copy-btn">
            Copy
          </button>
        </div>
      </div>

      <div style="margin: 24px 0; padding: 20px; background: #f0f4ff; border-radius: 8px;">
        <h3 style="margin-top: 0;">Local Time Hook</h3>
        <p style="font-size: 14px; color: #666;">Pushes the client's local time to the server via <code>pushEvent</code></p>
        <div id="time-hook" ignite-hook="LocalTime"
             style="display: flex; gap: 12px; align-items: center;">
          <span id="local-time-display" style="font-size: 18px; font-weight: bold;">--:--:--</span>
          <button id="send-time-btn"
                  style="padding: 8px 16px; background: #27ae60; color: white; border: none; border-radius: 6px; cursor: pointer;">
            Send to Server
          </button>
        </div>
      </div>

      <div style="margin: 24px 0; padding: 20px; background: #f0fff4; border-radius: 8px;">
        <h3 style="margin-top: 0;">Hook Events Log</h3>
        <p style="font-size: 14px; color: #666;">Events received from JS hooks via <code>pushEvent()</code></p>
        <ul style="margin: 8px 0; padding-left: 20px;">
          #{events_html}
        </ul>
      </div>

      <div style="margin-top: 24px; padding: 16px; background: #fffff0; border-radius: 8px; text-align: left;">
        <strong>How it works:</strong>
        <ul style="margin: 8px 0; padding-left: 20px;">
          <li>Register hooks: <code>window.IgniteHooks = { CopyToClipboard: { mounted() {...} } }</code></li>
          <li>Attach to elements: <code>&lt;div id="my-el" ignite-hook="CopyToClipboard"&gt;</code></li>
          <li><code>mounted()</code> — called when element first appears in the DOM</li>
          <li><code>updated()</code> — called when element is re-rendered by the server</li>
          <li><code>destroyed()</code> — called when element is removed from the DOM</li>
          <li><code>this.pushEvent(event, params)</code> — send events back to the server</li>
          <li><code>this.el</code> — reference to the DOM element</li>
        </ul>
      </div>

      <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #eee; text-align: center;">
        <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
        <a href="/counter" ignite-navigate="/counter" style="margin: 0 8px;">Counter</a>
        <a href="/components" ignite-navigate="/components" style="margin: 0 8px;">Components</a>
        <a href="/dashboard" ignite-navigate="/dashboard" style="margin: 0 8px;">Dashboard</a>
      </div>
    </div>
    """
  end
end

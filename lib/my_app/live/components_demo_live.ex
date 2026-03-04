defmodule MyApp.ComponentsDemoLive do
  @moduledoc """
  Demonstrates LiveComponents — reusable stateful widgets embedded in a LiveView.

  Each component manages its own state independently. The parent LiveView
  can also have its own state and events.
  """

  use Ignite.LiveView

  @impl true
  def mount(_params, _session) do
    {:ok, %{clicks: 0}}
  end

  @impl true
  def handle_event("parent_click", _params, assigns) do
    {:noreply, %{assigns | clicks: assigns.clicks + 1}}
  end

  @impl true
  def render(assigns) do
    """
    <div id="components-demo" style="max-width: 600px; margin: 0 auto;">
      <h1>LiveComponents Demo</h1>
      <p style="color: #888; font-size: 14px;">
        Each component manages its own state independently
      </p>

      <div style="margin: 24px 0; padding: 20px; background: #f8f9fa; border-radius: 8px;">
        <h3 style="margin-top: 0;">Parent LiveView State</h3>
        <p>Parent clicks: <strong>#{assigns.clicks}</strong></p>
        <button ignite-click="parent_click"
                style="padding: 8px 16px; background: #3498db; color: white; border: none; border-radius: 6px; cursor: pointer;">
          Click Parent
        </button>
      </div>

      <div style="margin: 24px 0; padding: 20px; background: #fff8f0; border-radius: 8px;">
        <h3 style="margin-top: 0;">Notification Badges</h3>
        <div style="display: flex; flex-direction: column; gap: 12px;">
          #{live_component(assigns, MyApp.Components.NotificationBadge, id: "alerts", label: "Alerts", count: 3)}
          #{live_component(assigns, MyApp.Components.NotificationBadge, id: "messages", label: "Messages", count: 7)}
        </div>
      </div>

      <div style="margin: 24px 0; padding: 20px; background: #f0f4ff; border-radius: 8px;">
        <h3 style="margin-top: 0;">Toggle Switches</h3>
        <div style="display: flex; gap: 12px; flex-wrap: wrap;">
          #{live_component(assigns, MyApp.Components.ToggleButton, id: "dark-mode", label: "Dark Mode")}
          #{live_component(assigns, MyApp.Components.ToggleButton, id: "notifications", label: "Notifications")}
          #{live_component(assigns, MyApp.Components.ToggleButton, id: "sound", label: "Sound")}
        </div>
      </div>

      <div style="margin-top: 24px; padding: 16px; background: #f0fff4; border-radius: 8px; text-align: left;">
        <strong>How it works:</strong>
        <ul style="margin: 8px 0; padding-left: 20px;">
          <li>Each component is a module with <code>mount/1</code>, <code>handle_event/3</code>, <code>render/1</code></li>
          <li>Components are rendered inline via <code>live_component(assigns, Module, id: "...")</code></li>
          <li>Events inside a component are automatically namespaced: <code>"alerts:dismiss"</code></li>
          <li>Component state is stored in the parent's assigns under <code>__components__</code></li>
          <li>Clicking a component button only updates that component's state</li>
        </ul>
      </div>

      <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #eee; text-align: center;">
        <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
        <a href="/" style="margin: 0 8px;">Home</a>
        <a href="/counter" ignite-navigate="/counter" style="margin: 0 8px;">Counter</a>
        <a href="/dashboard" ignite-navigate="/dashboard" style="margin: 0 8px;">Dashboard</a>
      </div>
    </div>
    """
  end
end

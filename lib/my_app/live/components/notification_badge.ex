defmodule MyApp.Components.NotificationBadge do
  @moduledoc """
  A reusable notification badge component.

  Shows a count with a dismiss button. Can be embedded in any LiveView.

  ## Props
    - `count` — number of notifications (default: 0)
    - `label` — badge label (default: "Notifications")
  """

  use Ignite.LiveComponent

  @impl true
  def mount(props) do
    {:ok, Map.merge(%{count: 0, label: "Notifications", dismissed: false}, props)}
  end

  @impl true
  def handle_event("dismiss", _params, assigns) do
    {:noreply, %{assigns | dismissed: true, count: 0}}
  end

  @impl true
  def handle_event("restore", _params, assigns) do
    {:noreply, %{assigns | dismissed: false}}
  end

  @impl true
  def render(assigns) do
    if assigns.dismissed do
      """
      <div style="display: inline-flex; align-items: center; gap: 8px;">
        <span style="color: #999; font-size: 13px;">#{assigns.label} dismissed</span>
        <button ignite-click="restore"
                style="padding: 2px 8px; font-size: 12px; background: #eee; border: 1px solid #ccc; border-radius: 4px; cursor: pointer;">
          Undo
        </button>
      </div>
      """
    else
      badge_color = if assigns.count > 0, do: "#e74c3c", else: "#95a5a6"

      """
      <div style="display: inline-flex; align-items: center; gap: 8px;">
        <span style="background: #{badge_color}; color: white; padding: 4px 10px; border-radius: 12px; font-size: 13px; font-weight: bold;">
          #{assigns.label}: #{assigns.count}
        </span>
        #{if assigns.count > 0 do
          ~s(<button ignite-click="dismiss" style="padding: 2px 8px; font-size: 12px; background: #eee; border: 1px solid #ccc; border-radius: 4px; cursor: pointer;">Dismiss</button>)
        else
          ""
        end}
      </div>
      """
    end
  end
end

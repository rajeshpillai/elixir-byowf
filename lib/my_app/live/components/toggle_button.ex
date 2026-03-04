defmodule MyApp.Components.ToggleButton do
  @moduledoc """
  A reusable toggle switch component.

  Shows an on/off button with customizable label.

  ## Props
    - `label` — button label (default: "Toggle")
    - `on` — initial state (default: false)
  """

  use Ignite.LiveComponent

  @impl true
  def mount(props) do
    {:ok, Map.merge(%{on: false, label: "Toggle"}, props)}
  end

  @impl true
  def handle_event("toggle", _params, assigns) do
    {:noreply, %{assigns | on: !assigns.on}}
  end

  @impl true
  def render(assigns) do
    {bg, text} =
      if assigns.on,
        do: {"#27ae60", "ON"},
        else: {"#95a5a6", "OFF"}

    """
    <button ignite-click="toggle"
            style="padding: 8px 16px; background: #{bg}; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 14px; min-width: 140px;">
      #{assigns.label}: #{text}
    </button>
    """
  end
end

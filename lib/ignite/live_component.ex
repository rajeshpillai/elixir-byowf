defmodule Ignite.LiveComponent do
  @moduledoc """
  Defines the LiveComponent behaviour for reusable stateful components.

  A LiveComponent lives inside a parent LiveView and manages its own state.
  Components are identified by a unique `id` and are rendered inline.

  ## Example

      defmodule MyApp.Components.ToggleButton do
        use Ignite.LiveComponent

        def mount(props) do
          {:ok, Map.merge(%{on: false, label: "Toggle"}, props)}
        end

        def handle_event("toggle", _params, assigns) do
          {:noreply, %{assigns | on: !assigns.on}}
        end

        def render(assigns) do
          status = if assigns.on, do: "ON", else: "OFF"
          \"""
          <button ignite-click="toggle">\#{assigns.label}: \#{status}</button>
          \"""
        end
      end

  Use it in a LiveView's render function:

      def render(assigns) do
        \"""
        <div>
          \#{live_component(assigns, MyApp.Components.ToggleButton, id: "my-toggle", label: "Dark Mode")}
        </div>
        \"""
      end
  """

  @doc "Called when the component is first created. Receives props from parent."
  @callback mount(props :: map()) :: {:ok, map()}

  @doc "Called when the component receives an event."
  @callback handle_event(event :: String.t(), params :: map(), assigns :: map()) ::
              {:noreply, map()}

  @doc "Returns the HTML string for the component."
  @callback render(assigns :: map()) :: String.t()

  @optional_callbacks [mount: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Ignite.LiveComponent
    end
  end
end

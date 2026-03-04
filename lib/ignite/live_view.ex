defmodule Ignite.LiveView do
  @moduledoc """
  Defines the LiveView behaviour for real-time server-rendered views.

  A LiveView is a stateful process that:
  1. Mounts with initial state
  2. Renders HTML based on that state
  3. Handles events from the browser (clicks, form submissions)
  4. Re-renders and pushes updates over WebSocket

  ## Example

      defmodule MyApp.CounterLive do
        use Ignite.LiveView

        def mount(_params, _session) do
          {:ok, %{count: 0}}
        end

        def handle_event("increment", _params, assigns) do
          {:noreply, %{assigns | count: assigns.count + 1}}
        end

        def render(assigns) do
          \"""
          <div>
            <h1>Count: \#{assigns.count}</h1>
            <button ignite-click="increment">+1</button>
          </div>
          \"""
        end
      end
  """

  @doc "Called when the LiveView process starts. Returns initial assigns."
  @callback mount(params :: map(), session :: map()) :: {:ok, map()}

  @doc "Called when the browser sends an event (click, form submit, etc.)."
  @callback handle_event(event :: String.t(), params :: map(), assigns :: map()) ::
              {:noreply, map()}

  @doc "Returns the HTML string for the current assigns."
  @callback render(assigns :: map()) :: String.t()

  @doc "Called when the process receives a message (e.g. PubSub broadcast, timer tick)."
  @callback handle_info(msg :: term(), assigns :: map()) :: {:noreply, map()}

  @optional_callbacks [handle_info: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Ignite.LiveView
    end
  end
end

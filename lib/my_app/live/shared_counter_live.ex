defmodule MyApp.SharedCounterLive do
  @moduledoc """
  A shared counter that syncs across all connected tabs and browsers.

  Demonstrates PubSub — when one user clicks "+", every other user
  watching the same page sees the count update in real time.

  Open this page in two browser tabs and click the buttons to see it work.
  """

  use Ignite.LiveView

  @topic "shared_counter"

  @impl true
  def mount(_params, _session) do
    Ignite.PubSub.subscribe(@topic)
    {:ok, %{count: 0}}
  end

  @impl true
  def handle_event("increment", _params, assigns) do
    new_count = assigns.count + 1
    Ignite.PubSub.broadcast(@topic, {:count_updated, new_count})
    {:noreply, %{assigns | count: new_count}}
  end

  @impl true
  def handle_event("decrement", _params, assigns) do
    new_count = assigns.count - 1
    Ignite.PubSub.broadcast(@topic, {:count_updated, new_count})
    {:noreply, %{assigns | count: new_count}}
  end

  # Receive broadcasts from other tabs/users
  @impl true
  def handle_info({:count_updated, count}, assigns) do
    {:noreply, %{assigns | count: count}}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div id="shared-counter" style="max-width: 500px; margin: 0 auto; text-align: center;">
      <h1>Shared Counter</h1>
      <p style="color: #888; font-size: 14px;">
        Open this page in multiple tabs — clicks sync in real time via PubSub
      </p>

      <p style="font-size: 4em; margin: 20px 0; font-weight: bold;"><%= assigns.count %></p>

      <div style="display: flex; gap: 16px; justify-content: center;">
        <button ignite-click="decrement"
                style="font-size: 1.5em; padding: 12px 28px; background: #e74c3c; color: white; border: none; border-radius: 8px; cursor: pointer;">
          &minus;
        </button>
        <button ignite-click="increment"
                style="font-size: 1.5em; padding: 12px 28px; background: #27ae60; color: white; border: none; border-radius: 8px; cursor: pointer;">
          +
        </button>
      </div>

      <div style="margin-top: 30px; padding: 16px; background: #f0f4ff; border-radius: 8px; text-align: left;">
        <strong>How it works:</strong>
        <ul style="margin: 8px 0; padding-left: 20px;">
          <li>Each tab is a separate Elixir process connected via WebSocket</li>
          <li>On click, the process updates its state and broadcasts via <code>Ignite.PubSub</code></li>
          <li>Other processes receive the message through <code>handle_info/2</code></li>
          <li>Built on Erlang's <code>:pg</code> process groups — zero external dependencies</li>
        </ul>
      </div>
    </div>
    """
  end
end

defmodule MyApp.CounterLive do
  @moduledoc """
  A simple live counter — demonstrates real-time updates without page refreshes.
  """

  use Ignite.LiveView

  @impl true
  def mount(_params, _session) do
    {:ok, %{count: 0}}
  end

  @impl true
  def handle_event("increment", _params, assigns) do
    {:noreply, %{assigns | count: assigns.count + 1}}
  end

  @impl true
  def handle_event("decrement", _params, assigns) do
    {:noreply, %{assigns | count: assigns.count - 1}}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div id="counter">
      <h1>Live Counter</h1>
      <p style="font-size: 3em; margin: 20px 0;"><%= assigns.count %></p>
      <button ignite-click="decrement" style="font-size: 1.5em; padding: 10px 20px;">-</button>
      <button ignite-click="increment" style="font-size: 1.5em; padding: 10px 20px;">+</button>

      <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee;">
        <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
        <a href="/dashboard" ignite-navigate="/dashboard" style="margin: 0 8px;">Dashboard</a>
        <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin: 0 8px;">Shared Counter</a>
      </div>
    </div>
    """
  end
end

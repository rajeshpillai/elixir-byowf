defmodule Ignite.LiveView.Handler do
  @moduledoc """
  Cowboy WebSocket handler for LiveView connections.

  Each browser tab gets its own handler process. The process:
  1. Mounts the LiveView and sends initial HTML
  2. Listens for events from the browser
  3. Updates state and pushes new HTML back

  This process stays alive as long as the browser tab is open.
  """

  @behaviour :cowboy_websocket

  require Logger

  # Called on the initial HTTP request before upgrading to WebSocket.
  # Returning {:cowboy_websocket, req, state} tells Cowboy to upgrade.
  @impl true
  def init(req, state) do
    {:cowboy_websocket, req, state}
  end

  # Called after the WebSocket connection is established.
  # We mount the LiveView and send the initial render.
  @impl true
  def websocket_init(state) do
    view_module = state.view

    case apply(view_module, :mount, [%{}, %{}]) do
      {:ok, assigns} ->
        html = apply(view_module, :render, [assigns])

        Logger.info("[LiveView] Mounted #{inspect(view_module)}")

        new_state = %{view: view_module, assigns: assigns}
        {:reply, {:text, Jason.encode!(%{html: html})}, new_state}
    end
  end

  # Called when the browser sends a message over the WebSocket.
  # We decode the event, call handle_event, re-render, and push back.
  @impl true
  def websocket_handle({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, %{"event" => event, "params" => params}} ->
        case apply(state.view, :handle_event, [event, params, state.assigns]) do
          {:noreply, new_assigns} ->
            new_html = apply(state.view, :render, [new_assigns])
            new_state = %{state | assigns: new_assigns}
            {:reply, {:text, Jason.encode!(%{html: new_html})}, new_state}
        end

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  # Called for Erlang messages sent to this process (e.g., PubSub).
  @impl true
  def websocket_info(_info, state) do
    {:ok, state}
  end
end

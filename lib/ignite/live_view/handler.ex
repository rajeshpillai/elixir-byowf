defmodule Ignite.LiveView.Handler do
  @moduledoc """
  Cowboy WebSocket handler for LiveView connections.

  Uses the diffing engine to send statics only once (on mount) and
  only dynamics on subsequent updates.
  """

  @behaviour :cowboy_websocket

  alias Ignite.LiveView.Engine

  require Logger

  @impl true
  def init(req, state) do
    {:cowboy_websocket, req, state}
  end

  # On mount: send both statics and dynamics
  @impl true
  def websocket_init(state) do
    view_module = state.view

    case apply(view_module, :mount, [%{}, %{}]) do
      {:ok, assigns} ->
        {statics, dynamics} = Engine.render(view_module, assigns)

        Logger.info("[LiveView] Mounted #{inspect(view_module)}")

        new_state = %{view: view_module, assigns: assigns}
        payload = Jason.encode!(%{s: statics, d: dynamics})
        {:reply, {:text, payload}, new_state}
    end
  end

  # On event: send only dynamics (statics haven't changed)
  @impl true
  def websocket_handle({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, %{"event" => event, "params" => params}} ->
        case apply(state.view, :handle_event, [event, params, state.assigns]) do
          {:noreply, new_assigns} ->
            # Check for pending redirect
            case Map.pop(new_assigns, :__redirect__) do
              {nil, clean_assigns} ->
                dynamics = Engine.render_dynamics(state.view, clean_assigns)
                new_state = %{state | assigns: clean_assigns}
                payload = Jason.encode!(%{d: dynamics})
                {:reply, {:text, payload}, new_state}

              {redirect_info, clean_assigns} ->
                new_state = %{state | assigns: clean_assigns}
                payload = Jason.encode!(%{redirect: redirect_info})
                {:reply, {:text, payload}, new_state}
            end
        end

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  # Server-push: handle messages sent to this process (e.g. :tick)
  @impl true
  def websocket_info(msg, state) do
    if function_exported?(state.view, :handle_info, 2) do
      case apply(state.view, :handle_info, [msg, state.assigns]) do
        {:noreply, new_assigns} ->
          dynamics = Engine.render_dynamics(state.view, new_assigns)
          new_state = %{state | assigns: new_assigns}
          payload = Jason.encode!(%{d: dynamics})
          {:reply, {:text, payload}, new_state}

        _ ->
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end
end

defmodule Ignite.LiveView.Handler do
  @moduledoc """
  Cowboy WebSocket handler for LiveView connections.

  Uses the diffing engine to send statics only once (on mount) and
  only dynamics on subsequent updates.

  Supports LiveComponents — component state is stored in
  `assigns.__components__` as `%{id => {module, comp_assigns}}`.
  Component events use the format `"component_id:event_name"`.
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

        # Collect component state that was created during render
        assigns = Ignite.LiveView.collect_components(assigns)

        # Extract pending stream operations (initial items from mount)
        {streams_payload, assigns} = Ignite.LiveView.Stream.extract_stream_ops(assigns)

        Logger.info("[LiveView] Mounted #{inspect(view_module)}")

        # Store prev_dynamics for future sparse diffing
        new_state = %{view: view_module, assigns: assigns, prev_dynamics: dynamics}

        # Include streams in mount payload if present
        payload_map = %{s: statics, d: dynamics}
        payload_map = if streams_payload, do: Map.put(payload_map, :streams, streams_payload), else: payload_map

        payload = Jason.encode!(payload_map)
        {:reply, {:text, payload}, new_state}
    end
  end

  # On event: send only dynamics (statics haven't changed)
  @impl true
  def websocket_handle({:text, json}, state) do
    case Jason.decode(json) do
      {:ok, %{"event" => event, "params" => params}} ->
        # Route component events (format: "component_id:event_name")
        {new_assigns, is_component_event} =
          handle_possible_component_event(event, params, state)

        new_assigns =
          if is_component_event do
            new_assigns
          else
            case apply(state.view, :handle_event, [event, params, state.assigns]) do
              {:noreply, assigns} -> assigns
            end
          end

        # Check for pending redirect
        case Map.pop(new_assigns, :__redirect__) do
          {nil, clean_assigns} ->
            send_render_update(state, clean_assigns)

          {redirect_info, clean_assigns} ->
            # Clear any pending stream ops since we're redirecting
            {_streams, clean_assigns} = Ignite.LiveView.Stream.extract_stream_ops(clean_assigns)
            new_state = %{state | assigns: clean_assigns}
            payload = Jason.encode!(%{redirect: redirect_info})
            {:reply, {:text, payload}, new_state}
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
          send_render_update(state, new_assigns)

        _ ->
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  # --- Private helpers ---

  # Renders the view, diffs against previous dynamics, and sends sparse update
  defp send_render_update(state, assigns) do
    {_statics, new_dynamics} = Engine.render(state.view, assigns)
    # Collect component state that was set during render
    assigns = Ignite.LiveView.collect_components(assigns)

    # Compute sparse diff against previous dynamics
    diff_payload =
      case Map.get(state, :prev_dynamics) do
        nil -> new_dynamics
        prev -> Engine.diff(prev, new_dynamics)
      end

    # Extract pending stream operations
    {streams_payload, assigns} = Ignite.LiveView.Stream.extract_stream_ops(assigns)

    new_state = %{state | assigns: assigns, prev_dynamics: new_dynamics}

    # Include streams in payload if present
    payload_map = %{d: diff_payload}
    payload_map = if streams_payload, do: Map.put(payload_map, :streams, streams_payload), else: payload_map

    payload = Jason.encode!(payload_map)
    {:reply, {:text, payload}, new_state}
  end

  # Checks if event is a component event ("id:event") and routes it
  defp handle_possible_component_event(event, params, state) do
    case String.split(event, ":", parts: 2) do
      [component_id, component_event] ->
        components = Map.get(state.assigns, :__components__, %{})

        case Map.get(components, component_id) do
          {module, comp_assigns} ->
            case apply(module, :handle_event, [component_event, params, comp_assigns]) do
              {:noreply, new_comp_assigns} ->
                new_components =
                  Map.put(components, component_id, {module, new_comp_assigns})

                new_assigns = Map.put(state.assigns, :__components__, new_components)
                {new_assigns, true}
            end

          nil ->
            {state.assigns, false}
        end

      _ ->
        {state.assigns, false}
    end
  end
end

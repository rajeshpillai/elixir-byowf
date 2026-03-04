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
    # Parse cookies from the WebSocket handshake request.
    # WebSocket upgrades carry cookies just like normal HTTP requests,
    # so LiveViews can access the same session data as controllers.
    cookie_header = :cowboy_req.header("cookie", req, "")
    cookies = Ignite.Session.parse_cookies(cookie_header)

    session =
      case Ignite.Session.decode(Map.get(cookies, Ignite.Session.cookie_name())) do
        {:ok, data} -> data
        :error -> %{}
      end

    {:cowboy_websocket, req, Map.put(state, :session, session)}
  end

  # On mount: send both statics and dynamics
  @impl true
  def websocket_init(state) do
    view_module = state.view
    session = Map.get(state, :session, %{})

    case apply(view_module, :mount, [%{}, session]) do
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
      # --- Upload protocol events ---

      {:ok, %{"event" => "__upload_validate__", "params" => %{"name" => name, "entries" => entries}}} ->
        upload_name = String.to_atom(name)
        new_assigns = Ignite.LiveView.UploadHelpers.validate_entries(state.assigns, upload_name, entries)

        # Let the view handle validation if it defines handle_event("validate", ...)
        new_assigns =
          if function_exported?(state.view, :handle_event, 3) do
            case apply(state.view, :handle_event, ["validate", %{"name" => name}, new_assigns]) do
              {:noreply, a} -> a
              _ -> new_assigns
            end
          else
            new_assigns
          end

        send_render_update_with_upload_config(state, new_assigns, upload_name)

      {:ok, %{"event" => "__upload_complete__", "params" => %{"name" => name, "ref" => ref}}} ->
        upload_name = String.to_atom(name)
        new_assigns = Ignite.LiveView.UploadHelpers.mark_complete(state.assigns, upload_name, ref)
        send_render_update(state, new_assigns)

      # --- Generic events ---

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

  # Binary frames carry file upload chunks
  # Protocol: [2 bytes: ref_len][ref_len bytes: ref_string][rest: chunk_data]
  @impl true
  def websocket_handle({:binary, data}, state) do
    case data do
      <<ref_len::16, ref::binary-size(ref_len), chunk_data::binary>> ->
        new_assigns = Ignite.LiveView.UploadHelpers.receive_chunk(state.assigns, ref, chunk_data)
        send_render_update(state, new_assigns)

      _ ->
        Logger.warning("[LiveView] Malformed binary upload frame")
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

  # Like send_render_update but also includes upload config for the JS client
  defp send_render_update_with_upload_config(state, assigns, upload_name) do
    {_statics, new_dynamics} = Engine.render(state.view, assigns)
    assigns = Ignite.LiveView.collect_components(assigns)

    diff_payload =
      case Map.get(state, :prev_dynamics) do
        nil -> new_dynamics
        prev -> Engine.diff(prev, new_dynamics)
      end

    {streams_payload, assigns} = Ignite.LiveView.Stream.extract_stream_ops(assigns)
    upload_config = Ignite.LiveView.UploadHelpers.build_upload_config(assigns, upload_name)

    new_state = %{state | assigns: assigns, prev_dynamics: new_dynamics}

    payload_map = %{d: diff_payload}
    payload_map = if streams_payload, do: Map.put(payload_map, :streams, streams_payload), else: payload_map
    payload_map = if upload_config, do: Map.put(payload_map, :upload, upload_config), else: payload_map

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

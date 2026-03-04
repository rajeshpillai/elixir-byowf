defmodule Ignite.Presence do
  @moduledoc """
  Tracks which processes are connected to which topics, with metadata.

  Built on `Process.monitor/1` for automatic cleanup when a process
  dies (e.g. a WebSocket disconnects). Broadcasts join/leave diffs
  via `Ignite.PubSub` so all subscribers see who's online.

  ## Example

      # In a LiveView's mount:
      Ignite.Presence.track("room:lobby", "user_123", %{name: "Jose"})
      Ignite.PubSub.subscribe("room:lobby")

      # All subscribers receive:
      {:presence_diff, %{joins: %{"user_123" => %{name: "Jose"}}, leaves: %{}}}

      # When the process dies:
      {:presence_diff, %{joins: %{}, leaves: %{"user_123" => %{name: "Jose"}}}}

      # Get current list:
      Ignite.Presence.list("room:lobby")
      #=> %{"user_123" => %{name: "Jose"}}
  """

  use GenServer

  require Logger

  # --- Public API ---

  @doc "Starts the Presence server."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Tracks the calling process under the given topic and key.

  The key is typically a user identifier (username, user_id, etc.).
  Meta is an arbitrary map of metadata (name, joined_at, etc.).

  If the same process calls `track` again with the same topic/key,
  the metadata is updated.
  """
  def track(topic, key, meta \\ %{}) do
    GenServer.call(__MODULE__, {:track, topic, key, meta, self()})
  end

  @doc """
  Removes the calling process from the given topic/key.
  """
  def untrack(topic, key) do
    GenServer.call(__MODULE__, {:untrack, topic, key, self()})
  end

  @doc """
  Returns a map of all tracked presences for the given topic.

  ## Example

      Ignite.Presence.list("room:lobby")
      #=> %{"user_123" => %{name: "Jose"}, "user_456" => %{name: "Chris"}}
  """
  def list(topic) do
    GenServer.call(__MODULE__, {:list, topic})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # State: %{
    #   presences: %{topic => %{key => %{pid: pid, meta: map, ref: reference}}},
    #   refs: %{reference => {topic, key}}
    # }
    {:ok, %{presences: %{}, refs: %{}}}
  end

  @impl true
  def handle_call({:track, topic, key, meta, pid}, _from, state) do
    topic_presences = Map.get(state.presences, topic, %{})

    # If already tracked with same key, update meta and reuse monitor
    state =
      case Map.get(topic_presences, key) do
        %{pid: ^pid, ref: ref} ->
          # Same process, same key — just update meta
          updated = Map.put(topic_presences, key, %{pid: pid, meta: meta, ref: ref})
          presences = Map.put(state.presences, topic, updated)
          %{state | presences: presences}

        %{pid: old_pid, ref: old_ref} when old_pid != pid ->
          # Different process claiming same key — remove old, track new
          Process.demonitor(old_ref, [:flush])
          state = remove_ref(state, old_ref)
          do_track(state, topic, key, meta, pid)

        nil ->
          # New tracking
          do_track(state, topic, key, meta, pid)
      end

    # Broadcast join
    Ignite.PubSub.broadcast(topic, {:presence_diff, %{joins: %{key => meta}, leaves: %{}}})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:untrack, topic, key, pid}, _from, state) do
    topic_presences = Map.get(state.presences, topic, %{})

    case Map.get(topic_presences, key) do
      %{pid: ^pid, ref: ref, meta: meta} ->
        Process.demonitor(ref, [:flush])
        state = remove_presence(state, topic, key, ref)

        # Broadcast leave
        Ignite.PubSub.broadcast(topic, {:presence_diff, %{joins: %{}, leaves: %{key => meta}}})

        {:reply, :ok, state}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:list, topic}, _from, state) do
    topic_presences = Map.get(state.presences, topic, %{})

    result =
      Map.new(topic_presences, fn {key, %{meta: meta}} ->
        {key, meta}
      end)

    {:reply, result, state}
  end

  # Process died — auto-untrack and broadcast leave
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.refs, ref) do
      {topic, key} ->
        topic_presences = Map.get(state.presences, topic, %{})
        meta = get_in(topic_presences, [key, :meta]) || %{}

        state = remove_presence(state, topic, key, ref)

        Logger.info("[Presence] #{key} left #{topic}")

        # Broadcast leave — use send directly since the dead process
        # can't be the sender (PubSub.broadcast excludes self())
        for pid <- :pg.get_members(Ignite.PubSub, topic) do
          send(pid, {:presence_diff, %{joins: %{}, leaves: %{key => meta}}})
        end

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  # --- Private helpers ---

  defp do_track(state, topic, key, meta, pid) do
    ref = Process.monitor(pid)
    topic_presences = Map.get(state.presences, topic, %{})
    updated = Map.put(topic_presences, key, %{pid: pid, meta: meta, ref: ref})

    %{
      state
      | presences: Map.put(state.presences, topic, updated),
        refs: Map.put(state.refs, ref, {topic, key})
    }
  end

  defp remove_presence(state, topic, key, ref) do
    topic_presences = Map.get(state.presences, topic, %{})
    updated = Map.delete(topic_presences, key)

    presences =
      if updated == %{} do
        Map.delete(state.presences, topic)
      else
        Map.put(state.presences, topic, updated)
      end

    %{state | presences: presences, refs: Map.delete(state.refs, ref)}
  end

  defp remove_ref(state, ref) do
    %{state | refs: Map.delete(state.refs, ref)}
  end
end

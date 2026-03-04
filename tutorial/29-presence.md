# Step 29: Presence Tracking

## What We're Building

A "Who's Online" system that tracks which LiveView processes are connected, broadcasts joins and leaves in real time, and auto-cleans when a WebSocket disconnects. Built on top of our existing PubSub (Step 17).

## The Problem

We have PubSub for broadcasting messages between processes, but no way to know *who* is currently connected. Questions like "how many users are on this page?" or "who's in this chat room?" have no answer yet.

## How Phoenix Does It

Phoenix.Presence is a CRDT-based system designed for distributed clusters. It tracks processes across multiple Erlang nodes using a heartbeat protocol.

For Ignite, we take a simpler approach: a single GenServer that uses `Process.monitor/1` to watch tracked processes. When a process dies (WebSocket disconnects), the monitor fires a `:DOWN` message, and we auto-untrack and broadcast the leave. This works perfectly for single-node deployments.

## Implementation

### 1. The Presence GenServer

`Ignite.Presence` maintains two maps:
- `presences`: `%{topic => %{key => %{pid, meta, ref}}}` — who's tracked where
- `refs`: `%{monitor_ref => {topic, key}}` — reverse lookup for `:DOWN` handling

```elixir
# lib/ignite/presence.ex

# Track a process under a topic with metadata
def track(topic, key, meta \\ %{}) do
  GenServer.call(__MODULE__, {:track, topic, key, meta, self()})
end

# Remove a process from a topic
def untrack(topic, key) do
  GenServer.call(__MODULE__, {:untrack, topic, key, self()})
end

# List all presences for a topic
def list(topic) do
  GenServer.call(__MODULE__, {:list, topic})
end
```

### 2. Process Monitoring

When `track/3` is called, the GenServer monitors the caller:

```elixir
defp do_track(state, topic, key, meta, pid) do
  ref = Process.monitor(pid)
  # Store the presence and the reverse ref mapping
  ...
end
```

When the monitored process dies:

```elixir
def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
  # Look up which topic/key this ref belongs to
  {topic, key} = state.refs[ref]
  # Remove from state and broadcast leave
  ...
end
```

### 3. Diff Broadcasting

Every join and leave broadcasts a `{:presence_diff, %{joins, leaves}}` message via PubSub:

```elixir
# On track:
Ignite.PubSub.broadcast(topic, {:presence_diff, %{joins: %{key => meta}, leaves: %{}}})

# On :DOWN:
for pid <- :pg.get_members(Ignite.PubSub, topic) do
  send(pid, {:presence_diff, %{joins: %{}, leaves: %{key => meta}}})
end
```

Note: For `:DOWN` handling, we send directly rather than using `PubSub.broadcast/2` because the dead process can't be excluded as a sender.

### 4. Supervision

Presence starts after PubSub in the supervision tree:

```elixir
# lib/ignite/application.ex
children = [
  Ignite.PubSub,
  Ignite.Presence,   # NEW — after PubSub
  # ... Cowboy ...
]
```

### 5. Demo: Who's Online

The `PresenceDemoLive` view:

```elixir
def mount(_params, _session) do
  username = "user_#{:rand.uniform(9999)}"
  Ignite.PubSub.subscribe("presence:demo")
  Ignite.Presence.track("presence:demo", username, %{joined_at: ...})
  online = Ignite.Presence.list("presence:demo")
  {:ok, %{username: username, online: online}}
end

def handle_info({:presence_diff, _diff}, assigns) do
  online = Ignite.Presence.list("presence:demo")
  {:noreply, %{assigns | online: online}}
end
```

## The Lifecycle

```
Tab 1 opens /presence
  → mount: track("presence:demo", "user_4231", %{joined_at: ...})
  → broadcast: {:presence_diff, %{joins: %{"user_4231" => ...}, leaves: %{}}}
  → list: %{"user_4231" => ...}

Tab 2 opens /presence
  → mount: track("presence:demo", "user_8876", ...)
  → broadcast: {:presence_diff, %{joins: %{"user_8876" => ...}, leaves: %{}}}
  → Tab 1 receives diff → refreshes list → sees both users
  → Tab 2 list: %{"user_4231" => ..., "user_8876" => ...}

Tab 2 closes
  → WebSocket process dies → :DOWN message to Presence GenServer
  → auto-untrack "user_8876"
  → broadcast: {:presence_diff, %{joins: %{}, leaves: %{"user_8876" => ...}}}
  → Tab 1 receives diff → refreshes list → sees only itself
```

## Testing

1. Open http://localhost:4000/presence in **2-3 browser tabs**
2. Each tab shows a random username and the full list of online users
3. Close one tab — it disappears from all others instantly
4. Open a new tab — it appears in all existing tabs

## Key Concepts

- **`Process.monitor/1`**: Returns a reference. When the monitored process dies, the monitoring process receives `{:DOWN, ref, :process, pid, reason}`. This is how we detect disconnects without polling.
- **GenServer state**: Centralized tracking in a single process. Simple and correct for single-node.
- **Diff broadcasting**: Instead of sending the full list on every change, we send only what changed (joins/leaves). The subscriber fetches the full list if needed.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Architecture | Single GenServer | CRDT (distributed) |
| Auto-cleanup | `Process.monitor/1` | `Process.monitor/1` + heartbeat |
| Multi-node | No (single node) | Yes (CRDT replication) |
| Diff format | `{:presence_diff, %{joins, leaves}}` | `%Phoenix.Presence.Diff{}` |
| Dependencies | None (built-in) | None (built-in) |

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/presence.ex` | **New** — GenServer with track/untrack/list + process monitoring |
| `lib/ignite/application.ex` | Added `Ignite.Presence` to supervision tree + WebSocket route |
| `lib/my_app/live/presence_demo_live.ex` | **New** — "Who's Online" demo LiveView |
| `lib/my_app/router.ex` | Added `GET /presence` route |
| `lib/my_app/controllers/welcome_controller.ex` | Added `presence/1` action + link on index |

# Step 17: PubSub — Real-Time Broadcasting Between LiveViews

In the previous steps, each LiveView process was **isolated** — it only responded to its own events or its own timers. But what if you want one user's action to update every other user's screen? That's what **PubSub** (publish/subscribe) is for.

We'll build a PubSub system using Erlang's built-in `:pg` (process groups) module — **zero external dependencies**.

## What You'll Learn

- Erlang's `:pg` module for process groups
- The publish/subscribe pattern
- Broadcasting messages between LiveView processes
- Automatic cleanup when processes die

## The Concept

PubSub follows a simple pattern:

1. **Subscribe** — A process joins a "topic" (a named group)
2. **Broadcast** — Any process can send a message to all subscribers of a topic
3. **Receive** — Each subscriber gets the message via `handle_info/2`
4. **Cleanup** — When a process dies, `:pg` automatically removes it from all groups

```
Tab A (Process #1)          PubSub              Tab B (Process #2)
    │                         │                       │
    │── subscribe("counter") ─│── subscribe("counter")│
    │                         │                       │
    │── increment ──────────> │                       │
    │   broadcast({:updated}) │──────────────────────>│
    │                         │            handle_info │
    │                         │            re-renders  │
```

## Erlang's `:pg` Module

`:pg` (process groups) is built into the Erlang standard library. It lets you:

- **Create named scopes** — isolated group namespaces
- **Join groups** — `join(scope, group, pid)` adds a process to a group
- **List members** — `get_members(scope, group)` returns all PIDs in a group
- **Auto-cleanup** — when a process dies, it's automatically removed

This is the same foundation that Phoenix.PubSub uses (though Phoenix adds a layer for distributed clustering across nodes).

## The Code

### 1. `lib/ignite/pub_sub.ex`

```elixir
defmodule Ignite.PubSub do
  @moduledoc """
  A lightweight publish/subscribe system built on Erlang's :pg.
  """

  def start_link(_opts) do
    :pg.start_link(__MODULE__)
  end

  def subscribe(topic) do
    :pg.join(__MODULE__, topic, self())
  end

  def broadcast(topic, message) do
    for pid <- :pg.get_members(__MODULE__, topic), pid != self() do
      send(pid, message)
    end
    :ok
  end

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end
end
```

**Key decisions:**

- `start_link/1` — Starts a `:pg` scope named `Ignite.PubSub`. This scope is isolated from any other `:pg` usage in the system.
- `subscribe/1` — Adds the calling process (`self()`) to the topic's group. No need to pass a PID — each LiveView handler process subscribes itself.
- `broadcast/2` — Sends the message to **all subscribers except the sender** (`pid != self()`). This prevents echo loops where a process receives its own broadcast.
- `child_spec/1` — Makes `Ignite.PubSub` compatible with `Supervisor.start_link/2`.

### 2. Add to Supervision Tree

In `lib/ignite/application.ex`, add `Ignite.PubSub` **before** the Cowboy listener:

```elixir
children = [
  Ignite.PubSub,  # Must start before LiveViews can subscribe
  %{id: :cowboy_listener, start: {:cowboy, :start_clear, [...]}}
] ++ dev_children()
```

PubSub must be running before any LiveView tries to subscribe — ordering in the children list guarantees this.

### 3. Formalize `handle_info` in the Behaviour

In `lib/ignite/live_view.ex`, add `handle_info/2` as an optional callback:

```elixir
@callback handle_info(msg :: term(), assigns :: map()) :: {:noreply, map()}
@optional_callbacks [handle_info: 2]
```

The handler already supports `handle_info` via `function_exported?/3` checks — this just makes the contract explicit.

### 4. The Shared Counter LiveView

```elixir
defmodule MyApp.SharedCounterLive do
  use Ignite.LiveView

  @topic "shared_counter"

  def mount(_params, _session) do
    Ignite.PubSub.subscribe(@topic)
    {:ok, %{count: 0}}
  end

  def handle_event("increment", _params, assigns) do
    new_count = assigns.count + 1
    Ignite.PubSub.broadcast(@topic, {:count_updated, new_count})
    {:noreply, %{assigns | count: new_count}}
  end

  def handle_event("decrement", _params, assigns) do
    new_count = assigns.count - 1
    Ignite.PubSub.broadcast(@topic, {:count_updated, new_count})
    {:noreply, %{assigns | count: new_count}}
  end

  def handle_info({:count_updated, count}, assigns) do
    {:noreply, %{assigns | count: count}}
  end

  def render(assigns) do
    """
    <div id="shared-counter">
      <h1>Shared Counter</h1>
      <p>Open in multiple tabs — clicks sync in real time via PubSub</p>
      <p style="font-size: 4em;">#{assigns.count}</p>
      <button ignite-click="decrement">-</button>
      <button ignite-click="increment">+</button>
    </div>
    """
  end
end
```

**How it works:**

1. On mount, the process subscribes to the `"shared_counter"` topic
2. When a user clicks "+", the handler updates its own count and broadcasts the new value
3. Other processes receive `{:count_updated, count}` via `handle_info/2`
4. Each process re-renders with the new count — morphdom patches the DOM

## The Message Flow

```
Tab A clicks "+"
  → handle_event("increment", ...) → count becomes 1
  → broadcast("shared_counter", {:count_updated, 1})
  → Returns {:noreply, %{count: 1}} — Tab A re-renders

Tab B's handler process receives {:count_updated, 1}
  → websocket_info dispatches to handle_info
  → handle_info({:count_updated, 1}, assigns)
  → Returns {:noreply, %{assigns | count: 1}} — Tab B re-renders
```

## Why `:pg` Instead of a Custom GenServer?

You could build PubSub with a `GenServer` that maintains a `%{topic => [pids]}` map. But `:pg` gives you:

- **Automatic cleanup** — no need to trap exits or monitor processes
- **Battle-tested** — part of Erlang/OTP since OTP 23, used in production for decades
- **Distribution-ready** — `:pg` works across clustered Erlang nodes out of the box
- **Zero overhead** — it's a built-in C-level implementation, not Elixir code

## Try It

1. Start the server: `iex -S mix`
2. Open http://localhost:4000/shared-counter in **two browser tabs**
3. Click "+" in Tab A — watch both tabs update simultaneously
4. Click "-" in Tab B — both tabs sync again
5. Close one tab — the other continues working normally

## What's Next

With PubSub, you can now build:

- **Chat rooms** — broadcast messages to all participants
- **Collaborative editing** — sync changes across users
- **Live notifications** — push alerts to specific users
- **Game state** — synchronize multiplayer game state

The next step toward Phoenix parity would be **Presence** — tracking which users are currently online using CRDT (Conflict-free Replicated Data Types).

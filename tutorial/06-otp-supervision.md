# Step 6: OTP Supervision

## What We're Building

Our server has a critical weakness: if it crashes, it's gone forever.
You'd have to manually restart it.

In this step, we wrap the server in an **OTP Supervisor** — a process
whose only job is to watch other processes and restart them when they crash.

After this change, the server starts automatically when the app boots and
self-heals on failure.

## Concepts You'll Learn

### What Is OTP?

OTP stands for **Open Telecom Platform**. Despite the name, it's not about
telephones — it's a set of libraries and design patterns for building
fault-tolerant applications.

The key OTP components we'll use:
- **Application** — the entry point for your app
- **Supervisor** — watches child processes and restarts them
- **GenServer** — a generic server process with a standard interface

### GenServer

A GenServer is a process with a well-defined lifecycle:

```
start_link → init → (handle_continue) → (handle_call/handle_cast/handle_info) → ...
```

When you write `use GenServer`, Elixir injects default implementations of
all the callbacks (just like `use Ignite.Router` injected `call/1` in Step 3).
You then override only the callbacks you need:


```elixir
use GenServer

def init(state) do
  {:ok, state}              # Initialize
end

def handle_continue(:task, state) do
  {:noreply, state}         # Run after init
end

def handle_call(:get, _from, state) do
  {:reply, state, state}    # Synchronous request
end

def handle_info(msg, state) do
  {:noreply, state}         # Async message
end
```

### @impl true

The `@impl true` annotation tells Elixir: "this function implements
a behavior callback." It helps catch mistakes — if you misspell a
callback name, the compiler warns you.

### handle_continue

`handle_continue` runs right after `init` returns. We use it because
`init` should return quickly — the supervisor is waiting!

```elixir
def init(port) do
  {:ok, state, {:continue, :listen}}  # Return fast, continue later
end

def handle_continue(:listen, state) do
  # Slow operations (opening sockets) happen here
  {:noreply, new_state}
end
```

### spawn_link vs spawn

`spawn_link` creates a process **linked** to the current one. If either
process crashes, the other crashes too:

```elixir
spawn(fn -> crash!() end)       # Crashes silently
spawn_link(fn -> crash!() end)  # Crashes the parent too!
```

We **want** this! If the acceptor loop crashes, the GenServer should
crash too, so the supervisor can restart the whole thing cleanly.

### Task.start vs spawn

`Task.start` is a better `spawn` — it integrates with OTP:

```elixir
Task.start(fn -> serve(client) end)
```

Benefits over `spawn`:
- Better error messages when it crashes
- Shows up in OTP debugging tools
- Proper exit signal handling

### Supervision Strategies

The supervisor uses `:one_for_one` — if a child crashes, only that
child gets restarted:

```elixir
opts = [strategy: :one_for_one, name: Ignite.Supervisor]
```

Other strategies:
- `:one_for_all` — if one crashes, restart ALL children
- `:rest_for_one` — if one crashes, restart it and all children started after it

### The "Let It Crash" Philosophy

In most languages, you write defensive code: `if error then handle`.
In Elixir, you write the **happy path** and let the supervisor handle
crashes. This leads to simpler, cleaner code.

## The Code

### `lib/ignite/server.ex` (Rewritten as GenServer)

**Replace `lib/ignite/server.ex` with** the GenServer-based version shown below.

The server is now split into two parts:

1. **Client API** (`start_link/1`) — how the supervisor starts us
2. **Callbacks** (`init/1`, `handle_continue/2`) — how we initialize

Key changes:
- `use GenServer` adds the GenServer behavior
- `start_link` replaces `start` — required for supervisors
- `init` returns immediately, `handle_continue` opens the socket
- `spawn_link` connects the acceptor loop to the GenServer
- `Task.start` replaces `spawn` for individual requests

### `mix.exs` (Tell OTP About Our Application)

For the supervisor to start automatically, you must add `mod:` to the
`application/0` function in `mix.exs`.

**Update `mix.exs`** — add `mod: {Ignite.Application, []}` to the `application/0` function:

```elixir
def application do
  [
    extra_applications: [:logger],
    mod: {Ignite.Application, []}
  ]
end
```

The `mod:` option tells the BEAM: "When this app starts, call
`Ignite.Application.start/2`." Without this line, nothing starts
automatically.

### `lib/ignite/application.ex` (The Supervisor)

**Replace `lib/ignite/application.ex` with:**

```elixir
defmodule Ignite.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Ignite.Server, 4000}
    ]

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

This tells the supervisor: "Start `Ignite.Server` with argument `4000`.
If it crashes, restart it."

## How It Works

```
Ignite.Application (Supervisor)
    │
    ├── Ignite.Server (GenServer)
    │       │
    │       └── loop_acceptor (linked process)
    │               │
    │               ├── Task: serve(client_1)
    │               ├── Task: serve(client_2)
    │               └── Task: serve(client_3)
    │
    └── (future children go here)
```

If a Task crashes (bad request), only that task dies.
If the acceptor crashes, the GenServer crashes, and the supervisor restarts it.

## Try It Out

1. Now the server starts **automatically** when you run `iex`:

```bash
iex -S mix
```

You should immediately see: `Ignite is heating up on http://localhost:4000`

No need to call `Ignite.Server.start()` — the supervisor did it for you!

2. Visit http://localhost:4000/ — still works!

3. Now test self-healing. In IEx:

```elixir
# Find the server's process ID
pid = Process.whereis(Ignite.Server)
#=> #PID<0.123.0>

# Kill it!
Process.exit(pid, :kill)

# Check again — it's back with a NEW pid!
Process.whereis(Ignite.Server)
#=> #PID<0.456.0>
```

4. Visit http://localhost:4000/ again — it still works!

The server crashed and restarted in milliseconds, with zero user impact.

## File Checklist

All files in the project after completing Step 6:

| File | Status |
|------|--------|
| `mix.exs` | **Modified** — added `mod:` to `application/0` |
| `lib/ignite.ex` | Unchanged |
| `lib/ignite/application.ex` | **Modified** — now starts `Ignite.Server` under a supervisor |
| `lib/ignite/server.ex` | **Modified** — rewritten as a GenServer |
| `lib/ignite/conn.ex` | Unchanged |
| `lib/ignite/parser.ex` | Unchanged |
| `lib/ignite/router.ex` | Unchanged |
| `lib/ignite/controller.ex` | Unchanged |
| `lib/my_app/router.ex` | Unchanged |
| `lib/my_app/controllers/welcome_controller.ex` | Unchanged |
| `lib/my_app/controllers/user_controller.ex` | Unchanged |
| `templates/` | Unchanged |

## What's Next

Our controllers return plain text. Real apps need HTML pages with
dynamic content (like showing a user's name).

In **Step 7**, we'll add an **EEx Template Engine** — Elixir's built-in
template system. You'll write HTML files with embedded Elixir code
(`<%= @name %>`) and render them from controllers with:

```elixir
render(conn, "profile", name: "Rajesh", id: 42)
```

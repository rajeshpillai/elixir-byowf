# Step 15: Hot Code Reloader

## What We're Building

Right now, changing a controller file requires restarting the server.
That's slow and kills your development flow.

We're building a GenServer that watches `lib/` for file changes and
**recompiles modules on the fly** — without restarting the server or
dropping any WebSocket connections.

This is possible because the BEAM VM supports **hot code swapping**.

## Concepts You'll Learn

### Hot Code Swapping

The BEAM VM can hold two versions of a module in memory at once: the
"current" version and the "old" version.

When you call `Code.compile_file("lib/my_app/router.ex")`, the VM:
1. Compiles the file into a new module version
2. Makes the new version "current"
3. Existing processes finish their current function call with the old version
4. The next function call uses the new version

No processes crash. No connections drop.

### File.stat/1

Returns metadata about a file, including its modification time:

```elixir
{:ok, stat} = File.stat("lib/ignite/server.ex")
stat.mtime  #=> {{2024, 3, 15}, {10, 30, 45}}
```

We compare mtimes to detect which files changed.

### Process.send_after/3

Schedules a message to be delivered to a process after a delay:

```elixir
Process.send_after(self(), :check, 1_000)
# After 1 second, this process receives the :check message
```

We use this to poll for changes every second. The GenServer's
`handle_info(:check, state)` callback handles the message.

### Path.wildcard/1

Finds files matching a glob pattern:

```elixir
Path.join("lib", "**/*.ex") |> Path.wildcard()
#=> ["lib/ignite.ex", "lib/ignite/server.ex", ...]
```

`**` means "any directory depth".

### Code.compile_file/1

Compiles an Elixir source file and loads the resulting modules:

```elixir
Code.compile_file("lib/my_app/controllers/welcome_controller.ex")
```

This replaces the in-memory module with the new version from the file.

### Dev-only Children

We only start the reloader in development mode:

```elixir
defp dev_children do
  if Mix.env() == :dev do
    [{Ignite.Reloader, [path: "lib"]}]
  else
    []
  end
end
```

In production, `Mix.env()` returns `:prod`, so the reloader isn't started.

### self()

`self()` returns the **PID** (Process ID) of the current process:

```elixir
self()  #=> #PID<0.123.0>
```

Every piece of Elixir code runs inside a process. `self()` lets a process refer to itself — here we use it with `Process.send_after(self(), :check, 1000)` to send a message to ourselves after a delay.

### handle_info

GenServer has three message handlers:
- `handle_call` — for synchronous requests (caller waits for a reply)
- `handle_cast` — for async fire-and-forget requests
- `handle_info` — for **all other messages** (timers, signals, raw `send/2`)

`Process.send_after` sends a raw message, so it arrives in `handle_info`, not `handle_call` or `handle_cast`.

## The Code

### `lib/ignite/reloader.ex`

A GenServer that:
1. On init: scans `lib/**/*.ex` and records all file modification times
2. Every second: re-scans and compares mtimes
3. If a file changed: calls `Code.compile_file/1` to hot-swap it
4. Errors in compilation are caught and logged (don't crash the reloader)

### Updated `lib/ignite/application.ex`

The reloader is added as a conditional child:
```elixir
children = [
  # ... cowboy ...
] ++ dev_children()
```

## How It Works

```
1. Server starts → Reloader starts → Records mtimes for all .ex files

2. Every 1 second:
   Reloader: Scan lib/**/*.ex
   Compare mtimes with saved versions
   Nothing changed → do nothing

3. You edit lib/my_app/controllers/welcome_controller.ex

4. Next check (within 1 second):
   Reloader: File mtime changed!
   → Code.compile_file("lib/my_app/.../welcome_controller.ex")
   → New module version loaded into VM
   → Next request uses the new code

5. No restart needed. No connections dropped.
```

## Try It Out

1. Start the server: `iex -S mix`

   You should see:
   ```
   [info] [Reloader] Watching lib/ for changes...
   ```

2. Visit http://localhost:4000/ → "Welcome to Ignite!"

3. **Without stopping the server**, open `lib/my_app/controllers/welcome_controller.ex`
   and change the index response:
   ```elixir
   def index(conn) do
     text(conn, "Welcome to Ignite! (hot reloaded)")
   end
   ```

4. Save the file. Check your terminal:
   ```
   [info] [Reloader] Recompiling: lib/my_app/controllers/welcome_controller.ex
   ```

5. Refresh http://localhost:4000/ → "Welcome to Ignite! (hot reloaded)"

   The change took effect without restarting the server!

6. If you have the `/counter` LiveView open in another tab, it still
   works with its current count — the reloader didn't affect it.

## What's Next

Our LiveView updates the DOM by replacing `innerHTML`. This works, but
it has a problem: if the user is typing in an input field and the server
pushes an update, the input loses focus and the text disappears.

In **Step 16**, we'll integrate **Morphdom** — a DOM diffing library
that only updates the elements that actually changed, preserving focus,
input state, and CSS animations.

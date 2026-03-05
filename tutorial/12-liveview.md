# Step 12: LiveView (WebSocket)

## What We're Building

Until now, every interaction required a full page reload. LiveView
changes that — the server keeps a **persistent connection** to the
browser via WebSocket, and can push HTML updates in real-time.

We're building:
1. `Ignite.LiveView` — a behaviour that defines the LiveView contract
2. `Ignite.LiveView.Handler` — a Cowboy WebSocket handler
3. `MyApp.CounterLive` — a live counter that increments without reloads

## Concepts You'll Learn

### WebSockets vs HTTP

**HTTP**: Browser sends request → Server sends response → Connection closes.
Every interaction is a new request.

**WebSocket**: Browser opens connection → Both sides can send messages at
any time → Connection stays open. It's a two-way pipe.

```
HTTP:     Browser ──request──> Server ──response──> done.
WebSocket: Browser <────────────────────────────> Server
           (persistent bidirectional connection)
```

### Behaviours and Callbacks

A **behaviour** defines a contract — a set of functions a module must
implement:

```elixir
@callback mount(params :: map(), session :: map()) :: {:ok, map()}
@callback handle_event(event :: String.t(), params :: map(), assigns :: map()) :: {:noreply, map()}
@callback render(assigns :: map()) :: String.t()
```

When you write `use Ignite.LiveView`, your module must implement all
three callbacks. The compiler warns you if any are missing.

### :cowboy_websocket Behaviour

Cowboy provides a WebSocket behaviour with these callbacks:

```elixir
init(req, state)              # HTTP request arrives — upgrade to WS
websocket_init(state)         # WebSocket connection established
websocket_handle(frame, state)  # Message received from browser
websocket_info(info, state)   # Erlang message received
```

### Stateful Processes

Unlike HTTP handlers (which die after each request), a WebSocket
handler is a **long-lived process**. It remembers state:

```elixir
# websocket_init: state starts as %{count: 0}
# User clicks +1
# websocket_handle: state becomes %{count: 1}
# User clicks +1 again
# websocket_handle: state becomes %{count: 2}
# ... the process stays alive, remembering the count
```

Each browser tab gets its own process. If one crashes, others are
unaffected.

### Jason (JSON Library)

We use Jason to encode/decode JSON for WebSocket messages:

```elixir
Jason.encode!(%{html: "<h1>Hello</h1>"})  #=> "{\"html\":\"<h1>Hello</h1>\"}"
Jason.decode!("{\"event\":\"inc\"}")        #=> %{"event" => "inc"}
```

### @callback and Type Specs

`@callback` defines a function that modules using this behaviour **must** implement. The `::` syntax describes the types:

```elixir
@callback mount(params :: map(), session :: map()) :: {:ok, map()}
#         ^name  ^arg     ^type   ^arg      ^type    ^return type
```

Read it as: "`mount` takes two maps and must return `{:ok, map}`. Functions ending in `!` (like `Jason.encode!`) raise an exception on failure instead of returning `{:error, reason}` — this is a convention throughout Elixir.

## The Code

### `lib/ignite/live_view.ex` (The Behaviour)

Defines the three callbacks every LiveView must implement:
- `mount/2` — initialize state (called once on connect)
- `handle_event/3` — process browser events (called on each interaction)
- `render/1` — generate HTML from current state

### `lib/ignite/live_view/handler.ex` (WebSocket Handler)

The lifecycle:

1. **`init/2`** — Cowboy calls this on the HTTP request. We return
   `{:cowboy_websocket, req, state}` to upgrade to WebSocket.

2. **`websocket_init/1`** — Connection established. We call the
   LiveView's `mount`, then `render`, and send the initial HTML.

3. **`websocket_handle/2`** — Browser sends a JSON event. We decode
   it, call `handle_event`, re-render, and push the new HTML back.

### `lib/my_app/live/counter_live.ex` (The Live Counter)

```elixir
def mount(_params, _session), do: {:ok, %{count: 0}}

def handle_event("increment", _params, assigns) do
  {:noreply, %{assigns | count: assigns.count + 1}}
end

def render(assigns) do
  "<h1>Count: #{assigns.count}</h1>
   <button ignite-click=\"increment\">+1</button>"
end
```

### Application Changes

Cowboy routing now has two entries:
- `/live` → `Ignite.LiveView.Handler` (WebSocket)
- `/[...]` → `Ignite.Adapters.Cowboy` (regular HTTP)

### The Host Page

The `/counter` route serves an HTML page with inline JavaScript that:
1. Opens a WebSocket to `/live`
2. Listens for `ignite-click` attributes on clicked elements
3. Sends events as JSON to the server
4. Updates `#ignite-app` innerHTML with server responses

## How It Works

```
1. Browser visits /counter
   → Server sends HTML page with JS

2. JS opens WebSocket to /live
   → Cowboy upgrades connection
   → Handler calls CounterLive.mount → {:ok, %{count: 0}}
   → Handler calls CounterLive.render(%{count: 0})
   → Sends {html: "<h1>Count: 0</h1>..."} to browser

3. User clicks "+1" button (has ignite-click="increment")
   → JS sends {event: "increment", params: {}}
   → Handler calls CounterLive.handle_event("increment", ...)
   → assigns becomes %{count: 1}
   → Handler calls CounterLive.render(%{count: 1})
   → Sends {html: "<h1>Count: 1</h1>..."} to browser
   → JS updates #ignite-app

4. Repeat — no page reload!
```

## Try It Out

1. Install the new dependency:

```bash
mix deps.get
```

2. Start the server: `iex -S mix`

3. Visit http://localhost:4000/counter

4. Click the **+1** button — the counter updates instantly
   without any page reload!

5. Open a second browser tab to the same URL — each tab has its own
   independent counter (its own BEAM process).

6. Check the terminal — you'll see the mount log:
   ```
   [info] [LiveView] Mounted MyApp.CounterLive
   ```

## What's Next

The JS is currently inline in the controller. In **Step 13**, we'll
extract it into a proper `assets/ignite.js` file and make the
LiveView host page a reusable template.

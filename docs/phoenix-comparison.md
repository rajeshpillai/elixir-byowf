# Ignite vs Phoenix — Architecture Comparison

A detailed comparison of how Ignite implements the same concepts as Phoenix, what's similar, what differs, and why.

## Overview

Ignite follows Phoenix's architectural patterns — the conn pipeline, macro-based routing, OTP supervision, LiveView with WebSockets — but makes different trade-offs for simplicity and educational clarity. Phoenix optimizes for production scale; Ignite optimizes for understandability while remaining functional for medium-scale apps.

| Aspect | Ignite | Phoenix |
|--------|--------|---------|
| HTTP Server | Cowboy (direct) | Cowboy or Bandit (via Plug adapter) |
| Request Struct | `%Ignite.Conn{}` | `%Plug.Conn{}` |
| Routing | Pattern-matched macros | Pattern-matched macros + verified routes |
| Templates | EEx + custom `~L` sigil | HEEx + `~H` sigil |
| LiveView | Custom WebSocket handler | Full-featured LiveView library |
| Diffing | Statics/dynamics + sparse diffs | Statics/dynamics + fingerprinted trees |
| PubSub | Erlang `:pg` wrapper | `Phoenix.PubSub` (`:pg2` / custom) |
| Dependencies | 2 (plug_cowboy, jason) | ~15+ (plug, phoenix_html, telemetry, etc.) |

---

## Conn Pipeline

### Similarities

Both frameworks model request/response as an immutable struct that flows through a pipeline:

```elixir
# Ignite
%Ignite.Conn{method: "GET", path: "/users/42", params: %{}, ...}

# Phoenix
%Plug.Conn{method: "GET", request_path: "/users/42", params: %{}, ...}
```

Both support middleware ("plugs") that transform the conn:

```elixir
# Ignite                              # Phoenix
plug :log_request                     plug :accepts, ["html"]
plug :add_server_header               plug :fetch_session
```

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Struct source | Custom `%Ignite.Conn{}` | Plug library's `%Plug.Conn{}` |
| Plug protocol | Functions only | Functions + Module plugs (`call/2` + `init/1`) |
| Halting | `conn.halted` boolean | `Plug.Conn.halt/1` |
| Assigns | `conn.assigns` map | `conn.assigns` map (same concept) |
| Response headers | Simple map | Keyword list with case-insensitive access |

Phoenix's `Plug.Conn` has ~30 fields covering sessions, cookies, query params, adapters, etc. Ignite's `Conn` has 8 fields — just enough for routing and response.

---

## Router DSL

### Similarities

Both use macros to generate pattern-matched function clauses at compile time:

```elixir
# Ignite
get "/users/:id", to: MyApp.UserController, action: :show

# Phoenix
get "/users/:id", UserController, :show
```

Both support scoped routes:

```elixir
# Ignite
scope "/api" do
  get "/status", to: MyApp.ApiController, action: :status
end

# Phoenix
scope "/api", MyApp do
  pipe_through :api
  get "/status", ApiController, :status
end
```

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Path helpers | Not implemented | `Routes.user_path(conn, :show, 42)` |
| Verified routes | Not implemented | `~p"/users/#{user}"` (compile-time checked) |
| Resource routes | Not implemented | `resources "/posts", PostController` |
| Pipelines | Single plug list | Named pipelines (`pipe_through :browser`) |
| Route info | Not available | `Phoenix.Router.routes/1` introspection |

Ignite's router compiles routes into `dispatch/2` function clauses using segment-based pattern matching. Phoenix does the same but adds a layer of metadata for introspection, path helper generation, and verified routes.

---

## Controllers

### Similarities

Both provide response helper functions:

```elixir
# Ignite                              # Phoenix
text(conn, "Hello")                   text(conn, "Hello")
html(conn, "<h1>Hi</h1>")            html(conn, "<h1>Hi</h1>")
json(conn, %{ok: true})              json(conn, %{ok: true})
render(conn, "show", user: user)      render(conn, :show, user: user)
```

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| View layer | Templates loaded at runtime | Views compiled at build time |
| Content negotiation | Manual | Built-in via `accepts` plug |
| Flash messages | Not implemented | `put_flash(conn, :info, "Saved!")` |
| Action fallback | Not implemented | `action_fallback MyFallbackController` |

---

## Templates

### Similarities

Both use EEx (Embedded Elixir) for server-side rendering with `<%= expression %>` syntax.

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Engine | Standard EEx + custom `~L` sigil | HEEx (HTML-aware EEx) |
| Sigil | `~L"""..."""` | `~H"""..."""` |
| Validation | No HTML validation | Compile-time HTML validation |
| Components | String interpolation | Function components (`<.button>`) |
| Assigns access | `assigns.count` | `@count` (sugar for `assigns.count`) |

Phoenix's HEEx engine validates HTML structure at compile time and provides function components with slots. Ignite's `~L` sigil splits templates into statics/dynamics for diffing but doesn't validate HTML.

---

## LiveView

This is where the frameworks diverge most significantly. Both implement the same core idea — server-rendered, stateful, real-time UI over WebSockets — but the implementation depth differs substantially.

### Similarities

Both define LiveViews with the same callback structure:

```elixir
# Ignite                              # Phoenix
def mount(_params, _session) do       def mount(_params, _session, socket) do
  {:ok, %{count: 0}}                   {:ok, assign(socket, count: 0)}
end                                   end

def handle_event("inc", _, assigns)   def handle_event("inc", _, socket) do
  {:noreply, %{assigns | count:         {:noreply, update(socket, :count,
    assigns.count + 1}}                   &(&1 + 1))}
end                                   end

def render(assigns) do                def render(assigns) do
  ~L"""                                 ~H"""
  <h1><%= assigns.count %></h1>         <h1>{@count}</h1>
  """                                   """
end                                   end
```

Both use WebSockets for bidirectional communication and push HTML diffs to the client.

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| State container | Plain map (`assigns`) | `%Phoenix.LiveView.Socket{}` |
| Change tracking | None — always re-renders all dynamics | Tracks which assigns changed |
| Event attributes | `ignite-click`, `ignite-submit` | `phx-click`, `phx-submit` |
| DOM patching | morphdom | Custom patcher (morphdom-inspired) |
| Uploads | Not implemented | Built-in file upload support |
| Testing | Manual (curl, browser) | `LiveViewTest` with DOM assertions |
| JS client | ~200 lines, single file | ~3000 lines, full lifecycle management |

**Change tracking** is the biggest architectural difference. Phoenix tracks which assigns changed between renders and only evaluates template expressions that reference changed assigns. Ignite always evaluates all expressions and relies on sparse diffing to minimize wire payload.

---

## Diffing Engine

### Similarities

Both split templates into **statics** (HTML that never changes) and **dynamics** (expression values):

```
Template: <h1>Count: <%= assigns.count %></h1>
Statics:  ["<h1>Count: ", "</h1>"]
Dynamics: ["42"]
```

Both send statics once on mount and only dynamics on updates. Both use sparse diffs — if dynamic at index 0 hasn't changed, it's omitted from the payload.

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Granularity | Per-expression | Per-expression + nested trees |
| Wire format | `{s: [...], d: [...]}` | `{s: [...], 0: "val", 1: "val"}` |
| Nested templates | Flat dynamics list | Recursive `%Rendered{}` trees |
| Fingerprinting | None | Static fingerprints skip unchanged subtrees |
| Comprehensions | Not tracked | `%Comprehension{}` for efficient list diffs |

Phoenix's diffing engine handles nested templates (components within components) as recursive rendered trees. Ignite flattens everything into a single statics/dynamics pair. This is simpler but means deeply nested views send more data.

---

## LiveView Streams

Both frameworks solve the same problem: efficiently managing large collections without re-sending the entire list when one item changes.

### Similarities

| Aspect | Ignite | Phoenix |
|--------|--------|---------|
| Core idea | Operation-based (insert/delete/reset) | Operation-based (insert/delete/reset) |
| Wire overhead | O(1) per operation | O(1) per operation |
| Memory | Items freed after render, only DOM IDs retained | Items freed from socket, only DOM IDs retained |
| API shape | `stream(assigns, :events, items, opts)` | `stream(socket, :events, items, opts)` |
| Insert | `stream_insert(assigns, :events, item, at: 0)` | `stream_insert(socket, :events, item, at: 0)` |
| Delete | `stream_delete(assigns, :events, item)` | `stream_delete(socket, :events, item)` |
| Reset | `stream(assigns, :events, [], reset: true)` | `stream(socket, :events, [], reset: true)` |
| Container | `<div ignite-stream="events">` | `<div id="events" phx-update="stream">` |

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| **Render function** | Explicit `render: fn item -> html end` at init | Items rendered inline in HEEx via `for` comprehension |
| **Template integration** | Empty container + separate render fn | `<div :for={{dom_id, item} <- @streams.events} id={dom_id}>` |
| **Wire channel** | Separate `streams` field alongside `d` | Integrated into the rendered tree as `%Comprehension{}` |
| **Change tracking** | None — render fn always called | Tracks which stream items changed |
| **Limits** | Not implemented | `stream(socket, :items, items, limit: 50)` caps client-side count |
| **Reordering** | Not supported | Specialized DOM patching handles reordering |
| **Configuration** | Options passed to `stream/4` | Separate `stream_configure/3` step |
| **DOM ID function** | `:id` option (default: `item.id`) | `:dom_id` option with prefix customization |
| **Bulk operations** | Via `stream/4` with items list | `stream/4` with items list |

### Why Ignite Uses a Render Function

Ignite's `~L` sigil compiles templates using a custom EEx engine that only captures output expressions (`<%= ... %>`). Non-output expressions like `for` loops are silently ignored. This means you can't iterate over a stream collection inside a `~L` template.

The explicit `render: fn item -> html end` approach solves this cleanly:

```elixir
# Ignite — render function provided at stream init
assigns = stream(assigns, :events, [],
  render: fn event ->
    ~s(<div id="events-#{event.id}" class="event">
      <span class="type">[#{event.type}]</span>
      #{event.message}
    </div>)
  end
)
```

```elixir
# Phoenix — items rendered inline in HEEx template
def render(assigns) do
  ~H"""
  <div id="events" phx-update="stream">
    <div :for={{dom_id, event} <- @streams.events} id={dom_id} class="event">
      <span class="type">[<%= event.type %>]</span>
      <%= event.message %>
    </div>
  </div>
  """
end
```

### Wire Protocol Comparison

**Ignite** sends stream operations as a separate `streams` field:
```json
{
  "d": {"0": "5"},
  "streams": {
    "events": {
      "inserts": [
        {"id": "events-5", "html": "<div id=\"events-5\">...</div>", "at": 0}
      ]
    }
  }
}
```

**Phoenix** integrates stream items into the rendered tree:
```json
{
  "0": "5",
  "s": ["<div id=\"events\" phx-update=\"stream\">", "</div>"],
  "stream": [
    [["events-5", -1, "<div id=\"events-5\">...</div>", null]]
  ]
}
```

### Bandwidth Comparison (Both Frameworks)

| Scenario | Without Streams | With Streams | Savings |
|----------|----------------|--------------|---------|
| Add 1 item to 10-item list | ~1,500 bytes | ~150 bytes | 90% |
| Add 1 item to 100-item list | ~15,000 bytes | ~150 bytes | 99% |
| Add 1 item to 1,000-item list | ~150,000 bytes | ~150 bytes | 99.9% |

Both frameworks achieve O(1) wire overhead per operation.

---

## PubSub

### Similarities

Both provide topic-based subscribe/broadcast for cross-process communication:

```elixir
# Ignite
Ignite.PubSub.subscribe("room:lobby")
Ignite.PubSub.broadcast("room:lobby", {:new_message, msg})

# Phoenix
Phoenix.PubSub.subscribe(MyApp.PubSub, "room:lobby")
Phoenix.PubSub.broadcast(MyApp.PubSub, "room:lobby", {:new_message, msg})
```

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Backend | Erlang `:pg` (process groups) | Configurable (`:pg2`, Redis, custom) |
| Distributed | Single node only | Multi-node via `Phoenix.PubSub.PG2` or Redis |
| Named instance | Singleton | Multiple named PubSub instances |
| Cleanup | Auto (`:pg` removes dead processes) | Auto |

---

## LiveComponents

### Similarities

Both support reusable stateful components within a LiveView:

```elixir
# Ignite
live_component(assigns, MyApp.ToggleButton, id: "dark-mode", label: "Dark Mode")

# Phoenix
<.live_component module={MyApp.ToggleButton} id="dark-mode" label="Dark Mode" />
```

Both use `mount/1`, `handle_event/3`, and `render/1` callbacks.

### Differences

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| State storage | Parent's `__components__` map | Dedicated component process/CID |
| Event routing | String prefix: `"dark-mode:toggle"` | Automatic via component target |
| Update callback | Not implemented | `update/2` for prop changes |
| Slots | Not implemented | Named slots for composable templates |

---

## Infrastructure

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Hot reloading | File timestamp polling + `Code.compile_file/1` | `Phoenix.CodeReloader` + file watchers |
| Asset pipeline | Static file serving via Cowboy | esbuild + tailwind + digest |
| Telemetry | Not implemented | Built-in `:telemetry` events |
| Error pages | Basic HTML 500 page | Dev: interactive debug page, Prod: custom templates |
| Clustering | Not implemented | Distributed Erlang + PubSub adapters |
| Releases | Not configured | `mix release` with runtime config |

---

## Summary

Ignite covers the **core 80%** of what Phoenix provides for building real-time web applications:

- Conn pipeline with plugs
- Macro-based routing with dynamic params and scoped routes
- Controllers with response helpers
- EEx templates with server-side rendering
- LiveView with WebSocket, events, and server push
- Fine-grained diffing with statics/dynamics separation
- LiveView Streams for efficient collections
- LiveComponents for reusable stateful widgets
- PubSub for cross-process broadcasting
- JS Hooks for client-side interop
- Hot code reloading
- OTP supervision for fault tolerance

The remaining **20%** — change tracking, verified routes, HEEx validation, file uploads, distributed PubSub, telemetry, and production tooling — is what makes Phoenix suitable for large-scale production deployments.

For learning Elixir and understanding how frameworks work, Ignite exposes every layer that Phoenix abstracts away. For deploying to production, Phoenix provides the battle-tested edge cases, security hardening, and ecosystem integration that a teaching framework intentionally omits.

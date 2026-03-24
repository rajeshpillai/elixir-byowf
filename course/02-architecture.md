> **Tip:** Open `course/assets/viewer.html` in a browser for an interactive view with dark/light theme, navigable diagrams, and animated walkthroughs.

# Architecture Deep Dive

<!-- metadata: generated=2026-03-24 -->

## System Architecture

```mermaid
graph TD
    Browser[Browser / curl] -->|HTTP| Cowboy[Cowboy HTTP Server]
    Browser -->|WebSocket| WSHandler[LiveView Handler]

    subgraph "Ignite Framework"
        Cowboy -->|init/2| Adapter[Cowboy Adapter]
        Adapter -->|%Conn{}| Middleware[Middleware Pipeline]
        Middleware -->|plugs| Security[CSRF · CSP · HSTS · Rate Limit]
        Security --> Router[Router DSL]
        Router -->|dispatch| Controllers[Controllers]
        Controllers -->|render| Templates[EEx Templates]

        WSHandler -->|mount/event| LiveView[LiveView Engine]
        LiveView -->|render| Diffing[Diffing Engine]
        LiveView -->|streams| Streams[Stream Manager]
        LiveView -->|components| Components[LiveComponents]
        Diffing -->|JSON patches| Browser

        PubSub[PubSub :pg] <-->|broadcast| LiveView
        Presence[Presence Tracker] --> PubSub
    end

    subgraph "Persistence"
        Controllers -->|Ecto| Repo[(SQLite via Ecto)]
        LiveView -->|Ecto| Repo
    end

    subgraph "Frontend"
        Browser --- JS[ignite.js]
        JS -->|morphdom| DOM[DOM Patching]
        JS -->|hooks| Hooks[JS Hooks]
    end

    click Adapter "?page=modules/03-cowboy-adapter.md" "View Cowboy Adapter module"
    click Security "?page=modules/06-security.md" "View Security module"
    click Router "?page=modules/02-router-dsl.md" "View Router DSL module"
    click Controllers "?page=modules/12-sample-app.md" "View Sample App module"
    click LiveView "?page=modules/04-liveview.md" "View LiveView module"
    click PubSub "?page=modules/05-pubsub-presence.md" "View PubSub & Presence module"
    click Presence "?page=modules/05-pubsub-presence.md" "View PubSub & Presence module"
    click Repo "?page=modules/08-persistence.md" "View Persistence module"
    click JS "?page=modules/09-frontend-js.md" "View Frontend JS module"
```

## Module Dependencies

```dep-graph
{
  "nodes": [
    {"id": "core-http", "label": "Core HTTP", "complexity": "moderate", "file": "modules/01-core-http.md"},
    {"id": "router-dsl", "label": "Router DSL", "complexity": "complex", "file": "modules/02-router-dsl.md"},
    {"id": "cowboy-adapter", "label": "Cowboy Adapter", "complexity": "moderate", "file": "modules/03-cowboy-adapter.md"},
    {"id": "liveview", "label": "LiveView", "complexity": "critical", "file": "modules/04-liveview.md"},
    {"id": "pubsub", "label": "PubSub & Presence", "complexity": "moderate", "file": "modules/05-pubsub-presence.md"},
    {"id": "security", "label": "Security", "complexity": "complex", "file": "modules/06-security.md"},
    {"id": "otp", "label": "OTP & Supervision", "complexity": "moderate", "file": "modules/07-otp-supervision.md"},
    {"id": "persistence", "label": "Persistence", "complexity": "moderate", "file": "modules/08-persistence.md"},
    {"id": "frontend", "label": "Frontend JS", "complexity": "complex", "file": "modules/09-frontend-js.md"},
    {"id": "static", "label": "Static Assets", "complexity": "simple", "file": "modules/10-static-assets.md"},
    {"id": "devtools", "label": "DevTools", "complexity": "moderate", "file": "modules/11-devtools.md"},
    {"id": "sample-app", "label": "Sample App", "complexity": "moderate", "file": "modules/12-sample-app.md"}
  ],
  "edges": [
    {"source": "router-dsl", "target": "core-http", "label": "uses %Conn{}"},
    {"source": "cowboy-adapter", "target": "core-http", "label": "builds %Conn{}"},
    {"source": "cowboy-adapter", "target": "router-dsl", "label": "calls Router.call/1"},
    {"source": "liveview", "target": "core-http", "label": "session access"},
    {"source": "liveview", "target": "pubsub", "label": "subscribe/broadcast"},
    {"source": "liveview", "target": "frontend", "label": "WebSocket protocol"},
    {"source": "security", "target": "core-http", "label": "transforms %Conn{}"},
    {"source": "otp", "target": "cowboy-adapter", "label": "supervises"},
    {"source": "otp", "target": "pubsub", "label": "supervises"},
    {"source": "otp", "target": "persistence", "label": "supervises Repo"},
    {"source": "devtools", "target": "core-http", "label": "error pages"},
    {"source": "sample-app", "target": "router-dsl", "label": "use Ignite.Router"},
    {"source": "sample-app", "target": "liveview", "label": "use Ignite.LiveView"},
    {"source": "sample-app", "target": "persistence", "label": "Ecto queries"},
    {"source": "sample-app", "target": "security", "label": "plugs"}
  ]
}
```

## Complexity Heatmap

```complexity-heatmap
{
  "title": "Ignite Codebase Complexity Map",
  "root": "lib",
  "items": [
    {"path": "lib/ignite/live_view", "files": 8, "complexity": "critical", "loc": 1540},
    {"path": "lib/ignite/router.ex", "files": 2, "complexity": "complex", "loc": 577},
    {"path": "lib/ignite/adapters/cowboy.ex", "files": 1, "complexity": "moderate", "loc": 262},
    {"path": "lib/ignite/conn.ex + parser.ex + server.ex + controller.ex", "files": 4, "complexity": "moderate", "loc": 430},
    {"path": "lib/ignite/security (csrf, csp, hsts, session, ssl)", "files": 5, "complexity": "complex", "loc": 498},
    {"path": "lib/ignite/pub_sub.ex + presence.ex", "files": 2, "complexity": "moderate", "loc": 249},
    {"path": "lib/ignite/application.ex + rate_limiter.ex + reloader.ex", "files": 3, "complexity": "moderate", "loc": 395},
    {"path": "lib/ignite/static.ex", "files": 1, "complexity": "simple", "loc": 90},
    {"path": "lib/ignite/debug_page.ex + conn_test.ex + mix tasks", "files": 4, "complexity": "moderate", "loc": 705},
    {"path": "lib/my_app", "files": 15, "complexity": "moderate", "loc": 1979},
    {"path": "assets", "files": 3, "complexity": "complex", "loc": 826}
  ]
}
```

## Architecture Minimap

```arch-minimap
{
  "components": [
    {"id": "overview", "label": "Overview", "page": "01-overview.md", "x": 50, "y": 3},
    {"id": "architecture", "label": "Architecture", "page": "02-architecture.md", "x": 50, "y": 12},
    {"id": "core-http", "label": "Core HTTP", "page": "modules/01-core-http.md", "x": 15, "y": 25},
    {"id": "router", "label": "Router DSL", "page": "modules/02-router-dsl.md", "x": 38, "y": 25},
    {"id": "adapter", "label": "Cowboy Adapter", "page": "modules/03-cowboy-adapter.md", "x": 62, "y": 25},
    {"id": "liveview", "label": "LiveView", "page": "modules/04-liveview.md", "x": 85, "y": 25},
    {"id": "pubsub", "label": "PubSub", "page": "modules/05-pubsub-presence.md", "x": 15, "y": 45},
    {"id": "security", "label": "Security", "page": "modules/06-security.md", "x": 38, "y": 45},
    {"id": "otp", "label": "OTP", "page": "modules/07-otp-supervision.md", "x": 62, "y": 45},
    {"id": "persistence", "label": "Persistence", "page": "modules/08-persistence.md", "x": 85, "y": 45},
    {"id": "frontend", "label": "Frontend JS", "page": "modules/09-frontend-js.md", "x": 15, "y": 65},
    {"id": "static", "label": "Static Assets", "page": "modules/10-static-assets.md", "x": 38, "y": 65},
    {"id": "devtools", "label": "DevTools", "page": "modules/11-devtools.md", "x": 62, "y": 65},
    {"id": "sample-app", "label": "Sample App", "page": "modules/12-sample-app.md", "x": 85, "y": 65}
  ],
  "connections": [
    {"from": "overview", "to": "architecture"},
    {"from": "adapter", "to": "core-http"},
    {"from": "adapter", "to": "router"},
    {"from": "router", "to": "core-http"},
    {"from": "liveview", "to": "pubsub"},
    {"from": "liveview", "to": "frontend"},
    {"from": "security", "to": "core-http"},
    {"from": "otp", "to": "adapter"},
    {"from": "otp", "to": "persistence"},
    {"from": "sample-app", "to": "router"},
    {"from": "sample-app", "to": "liveview"}
  ]
}
```

---

## Component Descriptions

### Core HTTP (`lib/ignite/conn.ex`, `parser.ex`, `server.ex`, `controller.ex`)

The `%Ignite.Conn{}` struct (`lib/ignite/conn.ex:13`) is the central data structure — every request creates one, every plug/controller transforms it, and the adapter reads the final result to send the HTTP response. The parser (`lib/ignite/parser.ex`) splits raw HTTP text into method, path, headers, and body. The controller (`lib/ignite/controller.ex`) provides helpers like `text/3`, `html/3`, `json/3`, and `render/3` that set the response fields on the conn.

### Router DSL (`lib/ignite/router.ex`)

The `__using__` macro (`lib/ignite/router.ex:29`) sets up module attributes for plug accumulation and route metadata. Route macros (`get`, `post`, `put`, `patch`, `delete`) define `dispatch/3` function clauses via `defmacro`. The `@before_compile` hook generates `call/1` (which chains all plugs then dispatches), a `Helpers` submodule with `_path` functions, and a `__routes__/0` introspection function.

### Cowboy Adapter (`lib/ignite/adapters/cowboy.ex`)

Implements `:cowboy_handler` behaviour. The `init/2` callback (`lib/ignite/adapters/cowboy.ex:15`) converts Cowboy's request to `%Conn{}`, generates a request ID, runs the router pipeline, handles session cookies, logs timing, and sends the response. Error handling wraps the pipeline in `try/rescue` to show the debug error page in dev.

### LiveView System (`lib/ignite/live_view.ex`, `lib/ignite/live_view/`)

The behaviour module (`lib/ignite/live_view.ex:1`) defines `mount/2`, `handle_event/3`, `render/1`, and optional `handle_info/2` callbacks. The WebSocket handler (`lib/ignite/live_view/handler.ex`) manages the lifecycle: mount sends statics+dynamics, events trigger re-render and sparse diffs. The diffing engine (`lib/ignite/live_view/engine.ex`) compares previous and current dynamics to produce minimal patches. Custom EEx engines (`eex_engine.ex`, `feex_engine.ex`) separate templates into static strings and dynamic expressions at compile time.

### PubSub & Presence (`lib/ignite/pub_sub.ex`, `lib/ignite/presence.ex`)

PubSub wraps Erlang's `:pg` process groups — `subscribe/1` joins the calling process to a topic, `broadcast/2` sends to all members except self. Presence (`lib/ignite/presence.ex`) is a GenServer that tracks connected users via `Process.monitor`, broadcasting join/leave events through PubSub.

### Security Layer (`lib/ignite/csrf.ex`, `csp.ex`, `hsts.ex`, `session.ex`, `ssl.ex`)

Each security feature is a standalone module that transforms `%Conn{}`. CSRF uses XOR-masked tokens with `Plug.Crypto.secure_compare/2`. CSP generates per-request nonces. Sessions are signed cookies using HMAC. SSL configuration supports both custom certs and auto-generated self-signed certs via the `mix ignite.gen.cert` task.

### OTP & Supervision (`lib/ignite/application.ex`)

The application supervisor (`lib/ignite/application.ex:13`) starts children in dependency order: Repo → PubSub → Presence → RateLimiter → Cowboy. The rate limiter (`lib/ignite/rate_limiter.ex`) uses ETS for lock-free concurrent access with a sliding window algorithm. The reloader (`lib/ignite/reloader.ex`) watches the `lib/` directory for file changes and triggers BEAM hot code swapping.

---

## Data Flow Walkthrough

**HTTP Request:**
```
Browser → Cowboy listener → Adapter.init/2 (lib/ignite/adapters/cowboy.ex:15)
  → cowboy_to_conn() builds %Conn{} (cowboy.ex:90+)
  → MyApp.Router.call/1 (lib/my_app/router.ex, generated by @before_compile)
    → rate_limit plug → add_server_header → set_hsts_header → set_csp_headers → verify_csrf_token
    → dispatch/3 matches route → Controller action
    → Controller sets conn.resp_body, conn.status
  → Adapter encodes session cookie, adds x-request-id header
  → :cowboy_req.reply() sends response
```

**LiveView WebSocket:**
```
Browser ignite.js → WebSocket /live/* → Handler.init/2 (handler.ex:20)
  → Parse cookies, decode session
  → websocket_init → view_module.mount/2 → Engine.render → {statics, dynamics}
  → Send JSON: {s: statics, d: dynamics, streams: ...}
  → User click → ignite.js sends ["event", {event, params}]
  → websocket_handle → view_module.handle_event/3 → new assigns
  → Engine.render → Engine.diff(prev_dynamics, new_dynamics) → sparse patch
  → Send JSON: {d: [null, null, "changed_value"]}
  → ignite.js applies morphdom patch to DOM
```

---

## Control Flow Walkthrough

1. `Ignite.Application.start/2` (`lib/ignite/application.ex:13`) boots the supervision tree
2. Cowboy listens on the configured port with a dispatch table mapping paths to handlers
3. HTTP requests hit `Ignite.Adapters.Cowboy.init/2` → router pipeline → controller → response
4. WebSocket requests hit `Ignite.LiveView.Handler` → stateful process per connection
5. LiveView processes subscribe to PubSub topics and receive broadcasts via `handle_info/2`
6. The reloader (dev only) watches files and hot-swaps modules on change

---

## External Dependency Map

| Dependency | Role | Used By |
|-----------|------|---------|
| **Cowboy** (via plug_cowboy) | HTTP/HTTPS server, WebSocket support | Adapter, LiveView Handler, SSL |
| **Jason** | JSON encoding/decoding | LiveView diffs, API controllers |
| **Ecto** (via ecto_sql) | Database query builder, changesets, migrations | Repo, schemas, controllers |
| **ecto_sqlite3** | SQLite3 database adapter | MyApp.Repo |
| **Plug.Crypto** | HMAC signing, secure compare | Session, CSRF |
| **Erlang :pg** | Process groups (built-in) | PubSub |
| **Erlang :gen_tcp** | Raw TCP sockets (used in early tutorial steps) | Server (step 1) |
| **morphdom** | Client-side DOM diffing/patching | Frontend JS (vendored) |

---

## Knowledge Graph

```
Core HTTP ← Router DSL (routes dispatch through %Conn{})
Core HTTP ← Cowboy Adapter (builds %Conn{} from Cowboy request)
Core HTTP ← Security (transforms %Conn{} with security headers/checks)
Core HTTP ← Controller (sets response fields on %Conn{})
Core HTTP ← DevTools (debug page renders into %Conn{})

Router DSL ← Sample App.Router (use Ignite.Router, defines routes)
Router DSL → Controller (dispatch to action functions)

Cowboy Adapter → Router DSL (calls Router.call/1)
Cowboy Adapter → Session (encodes/decodes signed cookies)
Cowboy Adapter → Debug Page (rescue renders error page)

LiveView → PubSub (subscribe/broadcast for real-time sync)
LiveView → Presence (track connected users)
LiveView → Diffing Engine (render → diff → sparse patch)
LiveView → Streams (efficient list rendering without full re-render)
LiveView → LiveComponents (nested stateful components)
LiveView → Upload (file upload handling over WebSocket)
LiveView ↔ Frontend JS (WebSocket JSON protocol)

Frontend JS → morphdom (DOM patching library)
Frontend JS → JS Hooks (lifecycle callbacks for custom behavior)

PubSub → Erlang :pg (process group membership)
Presence → PubSub (broadcasts join/leave diffs)
Presence → Process.monitor (detects disconnects)

OTP Supervisor → Repo (database connection pool)
OTP Supervisor → PubSub (process group scope)
OTP Supervisor → Presence (GenServer)
OTP Supervisor → RateLimiter (ETS-backed GenServer)
OTP Supervisor → Cowboy (HTTP listener)
OTP Supervisor → Reloader (dev-only file watcher)

Persistence (Ecto) → SQLite (via ecto_sqlite3 adapter)
Persistence ← Sample App controllers (CRUD operations)
Persistence ← Todo App LiveView (Ecto queries in handle_event)

Config → Application (port, env, rate_limit settings)
Config → Repo (database path, pool_size)
Config → SSL (cert paths, HSTS settings)
```

---

## Key Flows

### 1. HTTP Request Lifecycle
**Start:** `lib/ignite/adapters/cowboy.ex:15`
**Modules:** Cowboy Adapter → Security → Router DSL → Core HTTP
**What it teaches:** The full journey of an HTTP request through a layered framework — adapter pattern, middleware pipeline, macro-compiled dispatch, and functional response building.

### 2. LiveView Mount & Event
**Start:** `lib/ignite/live_view/handler.ex:20`
**Modules:** LiveView → Frontend JS → PubSub & Presence
**What it teaches:** How stateful server processes pair with WebSocket connections, how the diffing engine minimizes bandwidth, and how events flow bidirectionally.

### 3. Router Macro Expansion
**Start:** `lib/ignite/router.ex:29`
**Modules:** Router DSL
**What it teaches:** Elixir metaprogramming — how macros transform DSL declarations into compiled pattern-matching functions at compile time.

### 4. PubSub Broadcast
**Start:** `lib/ignite/pub_sub.ex:29`
**Modules:** PubSub & Presence → LiveView
**What it teaches:** Erlang's built-in process group mechanism, cross-process messaging without external brokers, and how LiveView processes react to broadcasts.

### 5. Fine-Grained Diffing Pipeline
**Start:** `lib/ignite/live_view/eex_engine.ex:1`
**Modules:** LiveView → Frontend JS
**What it teaches:** Compile-time template analysis separating static HTML from dynamic expressions, runtime sparse diffing, and efficient DOM patching.

---

### Understanding the Ignite Architecture

**The Big Picture:** Think of Ignite as a postal service. The **Cowboy Adapter** is the mailroom — it receives incoming HTTP letters, translates them into a standard internal envelope (`%Conn{}`), and passes them down the corridor. The **middleware pipeline** is a series of security checkpoints (rate limiting, CSRF, CSP). The **Router** is the sorting office that reads the address and sends each envelope to the right **Controller** desk. For real-time conversations (LiveView), there's a dedicated phone line (WebSocket) where a persistent operator keeps state and pushes updates when things change.

<details>
<summary>Intermediate: How it works</summary>

The framework follows a functional pipeline pattern where `%Ignite.Conn{}` is the single data structure threaded through every layer. Each plug is a function `conn -> conn` that can inspect or transform the connection. The router compiles route definitions into Elixir pattern-matching clauses, giving O(1) dispatch performance.

LiveView operates differently: each connection spawns a stateful process. The handler (`lib/ignite/live_view/handler.ex`) manages the WebSocket lifecycle, calling `mount/2` on connect, `handle_event/3` on user interaction, and `handle_info/2` on server-side messages. The diffing engine (`lib/ignite/live_view/engine.ex`) compares previous and current render output, sending only the changed dynamic segments as JSON patches.

The PubSub system (`lib/ignite/pub_sub.ex`) leverages Erlang's `:pg` module for zero-dependency process groups. When a LiveView calls `broadcast/2`, the message is sent to all processes in the topic group, each of which re-renders and pushes diffs to their client.

</details>

<details>
<summary>Advanced: Under the hood</summary>

**Macro compilation:** The `@before_compile` hook in `Ignite.Router` (`lib/ignite/router.ex:44`) triggers at module compilation. It reads accumulated `@plugs` and `@route_info` attributes to generate: (1) `call/1` which chains plugs via `Enum.reduce` then calls `dispatch/3`, (2) a `Helpers` submodule with path helper functions, (3) a `__routes__/0` function for introspection.

**Diffing strategy:** Templates compiled with `~L` (EEx engine) or `~F` (FEEx engine) produce `%Rendered{statics: [...], dynamics: [...]}` structs at compile time. Statics are the literal HTML strings between dynamic expressions — these are sent once on mount. Dynamics are evaluated at render time. The engine (`lib/ignite/live_view/engine.ex`) compares each dynamic slot against its previous value, producing sparse diffs where unchanged slots are `null`.

**Stream operations:** `Ignite.LiveView.Stream` (`lib/ignite/live_view/stream.ex`) implements efficient list management. Items are assigned DOM IDs and tracked by the framework. Insert, delete, and upsert operations are batched and sent as stream commands rather than re-rendering the entire list.

**Session security:** `Ignite.Session` (`lib/ignite/session.ex`) signs session data with HMAC-SHA256. The signing key is derived from `Application.get_env(:ignite, :secret_key_base)`. CSRF tokens use XOR masking — the stored token is masked before embedding in forms, and unmasked for comparison using `Plug.Crypto.secure_compare/2` to prevent timing attacks.

</details>

---
[< Previous: Overview](01-overview.md) | [Index](01-overview.md)

# Ignite — Build a Phoenix-like Web Framework from Scratch

A step-by-step tutorial that teaches Elixir by building **Ignite**, a real web framework inspired by [Phoenix](https://www.phoenixframework.org/). You'll go from a raw TCP socket to a full-stack framework with LiveView, WebSockets, PubSub, and DOM diffing — all in 24 incremental commits.

By the end, you'll understand every layer that powers production Elixir web applications: the conn pipeline, macro-based routing, OTP supervision, EEx templates, middleware plugs, real-time LiveView with efficient DOM patching, and PubSub for cross-process broadcasting.

## Features

### Framework Core
- **Macro-based Router DSL** — `get "/users/:id", to: Controller, action: :show` with dynamic path params
- **Conn Pipeline** — immutable request/response struct flows through the system, just like Phoenix
- **Controller Helpers** — `text/3`, `html/3`, `json/3`, `render/3` for clean response building
- **JSON API Support** — automatic JSON body parsing and `json/3` response helper
- **Full HTTP Methods** — `get`, `post`, `put`, `patch`, `delete` route macros
- **Scoped Routes** — `scope "/api" do ... end` for grouping routes under a common prefix
- **Middleware (Plugs)** — composable `plug :log_request` pipeline with halting support
- **EEx Templates** — server-side rendering with `<%= @name %>` assigns
- **POST Body Parsing** — form-urlencoded body parsing with `URI.decode_query/1`
- **Error Handling** — `try/rescue` boundary catches crashes and renders 500 pages

### Real-time (LiveView)
- **WebSocket Server** — persistent stateful connections via `:cowboy_websocket`
- **LiveView Behaviour** — `mount/2`, `handle_event/3`, `render/1` callbacks
- **Server Push** — `handle_info/2` for server-initiated updates (timers, external events)
- **Fine-Grained Diffing** — `~L` sigil with custom EEx engine splits templates at compile time; sends only changed values as sparse updates
- **Morphdom DOM Patching** — efficient client-side updates that preserve input focus and animations
- **LiveView Navigation** — SPA-like page transitions with `ignite-navigate` and `push_redirect/2`
- **LiveComponents** — reusable stateful components with `live_component/3`, auto-namespaced events
- **JS Hooks** — client-side lifecycle callbacks (`mounted`, `updated`, `destroyed`) for third-party JS interop

### Frontend Events
- **`ignite-click`** — click events with optional `ignite-value`
- **`ignite-change`** — real-time input validation (sends field name + value on every keystroke)
- **`ignite-submit`** — form submission with all fields collected via `FormData`

### PubSub
- **Process Group Broadcasting** — built on Erlang's `:pg` with zero external dependencies
- **Topic-based Subscribe/Broadcast** — LiveViews subscribe to topics and receive broadcasts via `handle_info/2`
- **Auto-cleanup** — dead processes are automatically removed from groups

### Infrastructure
- **OTP Supervision** — self-healing server with `one_for_one` strategy
- **Cowboy Adapter** — production-grade HTTP server (HTTP/1.1, connection pooling, SSL-ready)
- **Hot Code Reloader** — edit code, see changes without restarting the server
- **Multiple LiveViews** — configurable WebSocket paths via `data-live-path` attribute

## Demo Applications Included

| Route | Demo | What It Shows |
|-------|------|---------------|
| `/` | Landing page | Controller + HTML response |
| `/hello` | Text response | Plain text controller |
| `/users/42` | User profile | EEx templates + dynamic route params |
| `/counter` | Live counter | LiveView + click events |
| `/register` | Registration form | Real-time validation + form submit |
| `/dashboard` | BEAM dashboard | Server-push with auto-refreshing stats |
| `/shared-counter` | Shared counter | PubSub broadcasting across tabs |
| `/components` | Components demo | LiveComponents with independent state |
| `/hooks` | JS Hooks demo | Clipboard copy, local time, pushEvent |
| `/crash` | Error page | Error handler + 500 page |
| `POST /users` | Create user | POST body parsing |
| `PUT /users/42` | Update user | PUT/PATCH methods + JSON response |
| `DELETE /users/42` | Delete user | DELETE method |
| `/api/status` | API status | JSON response helper |
| `POST /api/echo` | Echo API | JSON body parsing |

## What You Can Build With Ignite

Ignite is a real framework. You can use it to build:

- **Admin dashboards** — real-time metrics, live charts, system monitoring
- **Chat applications** — WebSocket-based messaging with PubSub broadcasting
- **Form-heavy apps** — multi-step forms with live validation
- **Internal tools** — CRUD interfaces with server-side rendering
- **IoT control panels** — live device status with server-push updates
- **Prototypes** — quickly test ideas with minimal dependencies

## What You'll Build (Tutorial Steps)

| Layer | Component | Step |
|-------|-----------|------|
| Networking | TCP Socket → Cowboy | 1, 10 |
| Parsing | HTTP Parser | 2, 9 |
| Routing | Macro-based DSL | 3, 5 |
| Controllers | Response helpers | 4 |
| Reliability | OTP Supervision | 6 |
| Templates | EEx Engine | 7 |
| Middleware | Plug pipeline | 8 |
| Error Handling | try/rescue boundary | 11 |
| Real-time | LiveView + WebSocket | 12, 13 |
| Optimization | Diffing Engine | 14 |
| Dev Tools | Hot Code Reloader | 15 |
| UI Performance | Morphdom DOM diffing | 16 |
| Broadcasting | PubSub | 17 |
| Navigation | LiveView Navigation | 18 |
| Components | LiveComponents | 19 |
| JS Interop | JS Hooks | 20 |
| API | JSON helpers | 21 |
| REST | PUT/PATCH/DELETE | 22 |
| Organization | Scoped routes | 23 |
| Optimization | Fine-grained diffing | 24 |

## Prerequisites

- Elixir >= 1.14 installed (`elixir --version`)
- Basic terminal/command line skills
- A text editor or IDE
- A web browser and `curl` for testing

No prior Elixir experience required — each step explains the language concepts as they come up.

## How to Follow Along

Each step is tagged in git. To jump to any step:

```bash
git checkout step-01   # TCP Socket Foundation
git checkout step-02   # Conn Struct & Parser
# ... etc
```

Or follow along commit-by-commit and build everything yourself.

## Tutorial Steps

| Step | Topic | Tutorial | Key Concepts |
|------|-------|----------|-------------|
| 0 | Project Setup | You are here | Mix, project structure |
| 1 | [TCP Socket Foundation](tutorial/01-tcp-socket.md) | `lib/ignite/server.ex` | Modules, functions, `:gen_tcp`, processes |
| 2 | [Conn Struct & Parser](tutorial/02-conn-struct.md) | `lib/ignite/conn.ex`, `parser.ex` | Structs, pattern matching, HTTP parsing |
| 3 | [Router DSL](tutorial/03-router-dsl.md) | `lib/ignite/router.ex` | Macros, `quote`/`unquote`, metaprogramming |
| 4 | [Response Helpers](tutorial/04-response-helpers.md) | `lib/ignite/controller.ex` | Functional transforms, immutability |
| 5 | [Dynamic Routes](tutorial/05-dynamic-routes.md) | Router `:params` | List matching, URL segments |
| 6 | [OTP Supervision](tutorial/06-otp-supervision.md) | GenServer + Supervisor | OTP, fault tolerance, "let it crash" |
| 7 | [EEx Templates](tutorial/07-templates.md) | `templates/*.html.eex` | EEx, server-side rendering, assigns |
| 8 | [Middleware Pipeline](tutorial/08-middleware.md) | Plugs system | Module attributes, pipelines |
| 9 | [POST Body Parser](tutorial/09-post-parser.md) | Form data parsing | HTTP bodies, URI decoding |
| 10 | [Cowboy Adapter](tutorial/10-cowboy-adapter.md) | Production HTTP server | Dependencies, adapter pattern |
| 11 | [Error Handler](tutorial/11-error-handler.md) | 500 pages | `try/rescue`, graceful errors |
| 12 | [LiveView](tutorial/12-liveview.md) | WebSocket server | Behaviours, stateful processes |
| 13 | [Frontend JS Glue](tutorial/13-frontend-glue.md) | `assets/ignite.js` | WebSocket API, event delegation |
| 14 | [Diffing Engine](tutorial/14-diffing.md) | Statics + dynamics | Bandwidth optimization |
| 15 | [Hot Code Reloader](tutorial/15-hot-reloader.md) | Dev reloader | BEAM hot swapping |
| 16 | [Morphdom](tutorial/16-morphdom.md) | DOM diffing | Efficient UI updates |
| 17 | [PubSub](tutorial/17-pubsub.md) | Cross-process broadcasting | `:pg` process groups, subscribe/broadcast |
| 18 | [LiveView Navigation](tutorial/18-live-navigation.md) | SPA-like transitions | `history.pushState`, `ignite-navigate` |
| 19 | [LiveComponents](tutorial/19-live-components.md) | Reusable stateful widgets | Behaviours, process dictionary, event namespacing |
| 20 | [JS Hooks](tutorial/20-js-hooks.md) | Client-side JS interop | Lifecycle callbacks, `pushEvent`, DOM cleanup |
| 21 | [JSON API](tutorial/21-json-api.md) | `json/3` helper + body parsing | `Jason.encode!`, content-type matching |
| 22 | [HTTP Methods](tutorial/22-http-methods.md) | PUT/PATCH/DELETE macros | REST conventions, macro reuse |
| 23 | [Scoped Routes](tutorial/23-scoped-routes.md) | `scope "/api" do ... end` | `__CALLER__`, compile-time state, nesting |
| 24 | [Fine-Grained Diffing](tutorial/24-fine-grained-diffing.md) | `~L` sigil + EEx engine | Custom EEx engines, compile-time splitting, sparse diffs |

## Quick Start

```bash
# Clone the repo (main branch has the complete framework)
git clone https://github.com/rajeshpillai/elixir-byowf.git
cd elixir-byowf

# Install dependencies
mix deps.get

# Start the server
iex -S mix

# Try these routes:
# http://localhost:4000            → Landing page with all demo links
# http://localhost:4000/hello      → Controller response
# http://localhost:4000/users/42   → EEx template with dynamic params
# http://localhost:4000/counter    → LiveView (real-time counter)
# http://localhost:4000/register   → LiveView form with real-time validation
# http://localhost:4000/dashboard  → Live BEAM dashboard (auto-refresh)
# http://localhost:4000/shared-counter → PubSub shared counter (open in 2 tabs!)
# http://localhost:4000/components    → LiveComponents demo
# http://localhost:4000/hooks         → JS Hooks demo (clipboard, time)
# http://localhost:4000/crash      → Error handler (500 page)
# curl -X POST -d "username=Jose" http://localhost:4000/users  → POST parsing
# http://localhost:4000/api/status   → JSON API response
# curl -X POST -H "Content-Type: application/json" -d '{"name":"Jose"}' http://localhost:4000/api/echo
# curl -X PUT -H "Content-Type: application/json" -d '{"username":"Updated"}' http://localhost:4000/users/42
# curl -X DELETE http://localhost:4000/users/42
```

## Project Structure

```
ignite/
├── lib/
│   ├── ignite.ex              # Framework top-level module
│   ├── ignite/
│   │   ├── application.ex     # OTP Application & Supervisor
│   │   ├── server.ex          # TCP/HTTP server
│   │   ├── conn.ex            # %Ignite.Conn{} request/response struct
│   │   ├── parser.ex          # HTTP request parser
│   │   ├── controller.ex      # Response helpers (text, html, render)
│   │   ├── router.ex          # Router DSL macros
│   │   ├── live_view.ex       # LiveView behaviour + component helpers
│   │   ├── live_component.ex  # LiveComponent behaviour
│   │   ├── pub_sub.ex         # PubSub (Erlang :pg wrapper)
│   │   ├── live_view/
│   │   │   ├── handler.ex     # WebSocket handler
│   │   │   └── engine.ex      # Diffing engine
│   │   ├── reloader.ex        # Hot code reloader
│   │   └── adapters/
│   │       └── cowboy.ex      # Cowboy HTTP adapter
│   └── my_app/                # Sample application
│       ├── router.ex
│       ├── controllers/
│       └── live/
├── templates/                 # EEx HTML templates
├── assets/                    # Frontend JavaScript
│   ├── ignite.js              # LiveView client glue
│   ├── hooks.js               # Example JS Hooks
│   └── morphdom.min.js        # DOM diffing library
├── tutorial/                  # Step-by-step tutorial docs
├── mix.exs                    # Project config & dependencies
└── skills.md                  # Reference code snippets
```

## Dependencies

| Dependency | Added at | Purpose |
|-----------|---------|---------|
| `plug_cowboy` | Step 10 | Production HTTP server |
| `jason` | Step 12 | JSON for LiveView diffs |

Steps 1-9 use **zero external dependencies** — only Elixir's standard library and Erlang's `:gen_tcp`.

## Roadmap: Nice-to-Have (Compared to Phoenix/LiveView)

Features that would bring Ignite closer to Phoenix for production use:

### Routing & Controllers
- [x] ~~Scoped routes (`scope "/api" do ... end`)~~ (Step 23)
- [ ] Path helpers (`user_path(conn, :show, 42)` generating `/users/42`)
- [ ] Resource routes (`resources "/posts", PostController`)
- [x] ~~PUT/PATCH/DELETE HTTP methods~~ (Step 22)
- [x] ~~JSON response helper (`json(conn, %{ok: true})`)~~ (Step 21)

### LiveView
- [x] ~~Fine-grained diffing (track individual dynamic expressions, not whole HTML)~~ (Step 24)
- [x] ~~LiveView navigation (`live_redirect`, `push_patch` without full page reload)~~ (Step 18)
- [x] ~~LiveComponents (reusable stateful components within a LiveView)~~ (Step 19)
- [ ] Streams for large collections (append/prepend without re-rendering lists)
- [ ] File uploads via LiveView
- [x] ~~JS hooks (`phx-hook` equivalent for interop with JS libraries)~~ (Step 20)

### Security
- [ ] CSRF token generation and validation on forms
- [ ] Signed/encrypted session cookies
- [ ] Content Security Policy headers
- [ ] Rate limiting middleware

### Data & State
- [ ] Ecto integration for database access
- [x] ~~PubSub for broadcasting between LiveView processes~~ (Step 17)
- [ ] Presence tracking (who's online)
- [ ] Flash messages (`put_flash(conn, :info, "Saved!")`)

### Developer Experience
- [ ] Mix tasks (`mix ignite.routes` to list all routes)
- [ ] Debug error page with stacktrace (like Phoenix's dev error page)
- [ ] Logger metadata (request ID, timing)
- [ ] Static asset pipeline (CSS/JS bundling, fingerprinting)
- [ ] Test helpers (`ConnTest` for controller testing)

### Production
- [ ] SSL/TLS configuration
- [ ] Clustering (distributed Erlang nodes)
- [ ] Telemetry integration for metrics
- [ ] Deployment with `mix release`
- [ ] Health check endpoint

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](LICENSE) for the full text.

This means you are free to use, modify, and distribute this code, but if you run a modified version as a network service, you must make your source code available to users of that service.

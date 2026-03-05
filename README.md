# Ignite — Build Your Own Web Framework in Elixir

**A hands-on training guide** that teaches Elixir by building **Ignite**, a production-grade web framework inspired by [Phoenix](https://www.phoenixframework.org/). Go from a raw TCP socket to a full-stack framework with LiveView, WebSockets, PubSub, Presence, and DOM diffing — all in 40 incremental, well-documented steps.

---

## Training Overview

| | |
|---|---|
| **Total time** | ~40–50 hours (self-paced) |
| **Steps** | 40 commits, each with a detailed tutorial |
| **Prerequisites** | Basic programming experience (any language) |
| **Elixir required?** | No — Elixir concepts are introduced as you build |
| **Format** | Read tutorial → write code → verify → move on |
| **Dependencies** | Only 3 libraries added across 40 steps |

### What You'll Learn

By the end of this guide you'll understand every layer that powers production Elixir web applications:

- **Networking & OTP** — TCP sockets, GenServer, Supervisors, fault tolerance
- **Functional web pipelines** — the Conn struct, middleware plugs, macro-based routing
- **Server-side rendering** — EEx templates, controllers, response helpers
- **Real-time UI** — WebSockets, LiveView, DOM diffing with Morphdom, PubSub
- **Data persistence** — Ecto schemas, changesets, migrations (SQLite)
- **Security** — signed sessions, CSRF protection, CSP headers, rate limiting, SSL/TLS
- **Production deployment** — `mix release`, runtime config, health checks, HSTS

### How to Use This Guide

Each step is a git tag. You can follow along commit-by-commit, or jump to any step:

```bash
git checkout step-01   # Start from Step 1
git checkout step-40   # Jump to the final step
git checkout main      # See the complete framework
```

Every step has a matching tutorial doc in `tutorial/` with:
- What we built and why
- Full code with explanations
- Key concepts introduced
- Verification commands to confirm it works

---

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
- **Multipart File Uploads** — streaming multipart parser with `%Ignite.Upload{}` struct and temp file cleanup
- **Flash Messages** — `put_flash/3` + `get_flash/2` with one-time read semantics across redirects
- **Signed Sessions** — cookie-based sessions using `Plug.Crypto.MessageVerifier` (zero new deps)
- **Redirect Helper** — `redirect(conn, to: "/")` with 302 status and location header
- **Presence Tracking** — GenServer-based "Who's Online" with `Process.monitor/1` auto-cleanup
- **Ecto Database** — schema, changesets, migrations with SQLite (swappable to PostgreSQL)
- **CSRF Protection** — per-session tokens with XOR masking (BREACH-safe), automatic form validation
- **Content Security Policy** — nonce-based CSP headers, blocks injected scripts, allows WebSocket for LiveView
- **Mix Tasks** — `mix ignite.routes` prints all registered routes in a formatted table
- **Debug Error Page** — rich dev error page with stacktrace, request context, and session (generic in prod)
- **Logger Metadata** — per-request ID for log correlation, response timing, `x-request-id` header
- **Health Check** — `GET /health` returns JSON with uptime, memory, process count, scheduler info
- **Static Asset Pipeline** — content-hashed URLs (`?v=abc123`) for cache busting, ETS manifest, reloader integration
- **Test Helpers (ConnTest)** — `build_conn`, `get/post/put/patch/delete`, `html_response`, `json_response`, CSRF helpers for form tests
- **SSL/TLS Support** — config-driven HTTPS via Cowboy `:start_tls`, HTTP→HTTPS redirect, HSTS headers, `mix ignite.gen.cert`
- **Rate Limiting** — ETS-based sliding window per-IP rate limiter with `x-ratelimit-*` headers and 429 responses
- **`mix release` Support** — `runtime.exs` for env vars, release migration tasks, configurable session secret
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
- **File Uploads** — chunked binary WebSocket uploads with `allow_upload/3`, progress tracking, drag-and-drop

### Frontend Events
- **`ignite-click`** — click events with optional `ignite-value`
- **`ignite-change`** — real-time input validation (sends field name + value on every keystroke)
- **`ignite-submit`** — form submission with all fields collected via `FormData`

### PubSub & Presence
- **Process Group Broadcasting** — built on Erlang's `:pg` with zero external dependencies
- **Topic-based Subscribe/Broadcast** — LiveViews subscribe to topics and receive broadcasts via `handle_info/2`
- **Auto-cleanup** — dead processes are automatically removed from groups
- **Presence Tracking** — track connected users per topic with `Process.monitor/1` for automatic disconnect handling
- **Presence Diffs** — `{:presence_diff, %{joins, leaves}}` broadcasts on every join/leave

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
| `/users/42` | User profile | Ecto DB query + EEx template |
| `/counter` | Live counter | LiveView + click events |
| `/register` | Registration form | Real-time validation + form submit |
| `/dashboard` | BEAM dashboard | Server-push with auto-refreshing stats |
| `/shared-counter` | Shared counter | PubSub broadcasting across tabs |
| `/components` | Components demo | LiveComponents with independent state |
| `/hooks` | JS Hooks demo | Clipboard copy, local time, pushEvent |
| `/streams` | Streams demo | LiveView Streams for efficient list updates |
| `/upload` | File upload form | Multipart HTTP POST upload |
| `/upload-demo` | LiveView uploads | Chunked WebSocket uploads + progress |
| `/presence` | Who's Online | Presence tracking + auto-cleanup on disconnect |
| `/users` | User list (JSON) | Ecto DB query + resource routes |
| `/crash` | Debug error page | Rich stacktrace + request context (dev) |
| `POST /users` | Create user | Ecto changeset validation + flash + redirect |
| `PUT /users/42` | Update user | PUT/PATCH methods + JSON response |
| `DELETE /users/42` | Delete user | DELETE method |
| `/health` | Health check | BEAM runtime metrics (JSON) |
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

## Curriculum — 41 Steps, 9 Modules

Each step is a git tag with a detailed tutorial in `tutorial/`. Estimated times assume you're reading the explanation, writing the code, and verifying it works.

> **Total estimated time: ~41–52 hours**

---

### Module 1: HTTP Foundations *(~10 hours)*

Build a web server from scratch — raw TCP, then a proper Conn pipeline with routing, templates, and middleware.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 0 | [Project Setup](tutorial/00-project-setup.md) | Mix, project structure | 30m |
| 1 | [TCP Socket Foundation](tutorial/01-tcp-socket.md) | Modules, functions, `:gen_tcp`, processes | 1h |
| 2 | [Conn Struct & Parser](tutorial/02-conn-struct.md) | Structs, pattern matching, HTTP parsing | 1h |
| 3 | [Router DSL](tutorial/03-router-dsl.md) | Macros, `quote`/`unquote`, metaprogramming | 1.5h |
| 4 | [Response Helpers](tutorial/04-response-helpers.md) | Functional transforms, immutability | 45m |
| 5 | [Dynamic Routes](tutorial/05-dynamic-routes.md) | List matching, URL segments | 1h |
| 6 | [OTP Supervision](tutorial/06-otp-supervision.md) | OTP, fault tolerance, "let it crash" | 1.5h |
| 7 | [EEx Templates](tutorial/07-templates.md) | EEx, server-side rendering, assigns | 45m |
| 8 | [Middleware Pipeline](tutorial/08-middleware.md) | Module attributes, pipelines | 45m |
| 9 | [POST Body Parser](tutorial/09-post-parser.md) | HTTP bodies, URI decoding | 30m |
| 10 | [Cowboy Adapter](tutorial/10-cowboy-adapter.md) | Dependencies, adapter pattern | 1h |
| 11 | [Error Handler](tutorial/11-error-handler.md) | `try/rescue`, graceful errors | 30m |

**Milestone:** You have a working HTTP framework with routing, templates, and middleware — similar to early Sinatra or Express.

---

### Module 2: LiveView & Real-time *(~6 hours)*

Add persistent WebSocket connections, server-rendered UI updates, and efficient DOM patching.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 12 | [LiveView](tutorial/12-liveview.md) | Behaviours, stateful processes | 1.5h |
| 13 | [Frontend JS Glue](tutorial/13-frontend-glue.md) | WebSocket API, event delegation | 1h |
| 14 | [Diffing Engine](tutorial/14-diffing.md) | Bandwidth optimization | 1.5h |
| 15 | [Hot Code Reloader](tutorial/15-hot-reloader.md) | BEAM hot swapping | 1h |
| 16 | [Morphdom](tutorial/16-morphdom.md) | Efficient UI updates | 1h |

**Milestone:** Real-time counter that updates without page refreshes — your own LiveView.

---

### Module 3: Broadcasting & Components *(~5 hours)*

Build PubSub for cross-process messaging, SPA-like navigation, reusable components, and JS interop.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 17 | [PubSub](tutorial/17-pubsub.md) | `:pg` process groups, subscribe/broadcast | 1.5h |
| 18 | [LiveView Navigation](tutorial/18-live-navigation.md) | `history.pushState`, `ignite-navigate` | 1h |
| 19 | [LiveComponents](tutorial/19-live-components.md) | Behaviours, process dictionary, event namespacing | 1.5h |
| 20 | [JS Hooks](tutorial/20-js-hooks.md) | Lifecycle callbacks, `pushEvent`, DOM cleanup | 1h |

**Milestone:** A shared counter that syncs across browser tabs via PubSub.

---

### Module 4: REST API & Advanced Features *(~8 hours)*

Full REST support, fine-grained diffing, file uploads, and code-generated path helpers.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 21 | [JSON API](tutorial/21-json-api.md) | `Jason.encode!`, content-type matching | 1h |
| 22 | [HTTP Methods](tutorial/22-http-methods.md) | REST conventions, macro reuse | 45m |
| 23 | [Scoped Routes](tutorial/23-scoped-routes.md) | `__CALLER__`, compile-time state, nesting | 1h |
| 24 | [Fine-Grained Diffing](tutorial/24-fine-grained-diffing.md) | Custom EEx engines, sparse diffs | 1.5h |
| 25 | [LiveView Streams](tutorial/25-streams.md) | Stream ops, DOM manipulation, O(1) updates | 1h |
| 26 | [File Uploads](tutorial/26-file-uploads.md) | Cowboy streaming, binary WebSocket frames | 1.5h |
| 27 | [Path Helpers & Resource Routes](tutorial/27-path-helpers.md) | `@before_compile`, code generation | 1h |

**Milestone:** Full CRUD API with resource routes, file uploads, and optimized LiveView rendering.

---

### Module 5: Data & State *(~4 hours)*

Signed sessions, flash messages, presence tracking, and database persistence.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 28 | [Flash Messages](tutorial/28-flash-messages.md) | `Plug.Crypto`, signed cookies, session lifecycle | 1.5h |
| 29 | [Presence Tracking](tutorial/29-presence.md) | `Process.monitor/1`, GenServer state, presence diffs | 1.5h |
| 30 | [Ecto Integration](tutorial/30-ecto-integration.md) | Database persistence with SQLite (Ecto) | 1h |

**Milestone:** Users are persisted in a database, with sessions, flash messages, and "Who's Online" tracking.

---

### Module 6: Security *(~2 hours)*

Protect forms from CSRF attacks and lock down inline scripts with Content Security Policy.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 31 | [CSRF Protection](tutorial/31-csrf-protection.md) | Per-session tokens, XOR masking, form validation | 1h |
| 32 | [CSP Headers](tutorial/32-csp-headers.md) | Nonce-based Content Security Policy, script protection | 1h |

**Milestone:** Forms are CSRF-protected and scripts are locked down — ready for real users.

---

### Module 7: Developer Experience *(~5 hours)*

Mix tasks, error pages, structured logging, static assets, and test helpers.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 33 | [`mix ignite.routes`](tutorial/33-mix-ignite-routes.md) | Custom Mix tasks, compile-time route introspection | 45m |
| 34 | [Debug Error Page](tutorial/34-debug-error-page.md) | Rich dev error page, stacktrace formatting, dev/prod branching | 1h |
| 35 | [Logger Metadata](tutorial/35-logger-metadata.md) | Request ID, response timing, `Logger.metadata`, `x-request-id` header | 1h |
| 37 | [Static Asset Pipeline](tutorial/37-static-asset-pipeline.md) | Content-hashed URLs, ETS manifest, `static_path/1` helper | 1h |
| 38 | [Test Helpers](tutorial/38-test-helpers.md) | ConnTest module, response assertions, CSRF helpers, plug execution fix | 1h |

**Milestone:** Professional DX — rich error pages, structured logs, cache-busting assets, and test infrastructure.

---

### Module 8: Production *(~4 hours)*

Health checks, SSL/TLS, rate limiting, and `mix release` for deployment.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 36 | [Health Check](tutorial/36-health-check.md) | `/health` endpoint with BEAM runtime metrics | 45m |
| 39 | [SSL/TLS Support](tutorial/39-ssl-tls.md) | Config-driven HTTPS, HTTP→HTTPS redirect, HSTS, `mix ignite.gen.cert` | 1.5h |
| 40 | [Deployment & Rate Limiting](tutorial/40-release-and-rate-limit.md) | `mix release`, `runtime.exs`, ETS rate limiter, release migration tasks | 1.5h |

**Milestone:** Framework is production-deployable — HTTPS, rate-limited, health-monitored, and packaged as a release.

---

### Module 9: Optimizations *(~1 hour)*

Close the remaining gaps with Phoenix's stream system.

| Step | Tutorial | Topics | Est. |
|------|----------|--------|------|
| 41 | [Stream Upsert & Limit](tutorial/41-stream-upsert-limit.md) | Upsert by DOM ID, `:limit` for bounded lists, order tracking | 1h |

**Milestone:** Streams support upsert (update-in-place) and bounded lists — matching Phoenix's core stream features.

---

## Quick Start

```bash
# Clone the repo (main branch has the complete framework)
git clone https://github.com/rajeshpillai/elixir-byowf.git
cd elixir-byowf

# Install dependencies
mix deps.get

# Set up the database (SQLite — no server needed)
mix ecto.create
mix ecto.migrate

# List all routes
mix ignite.routes

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
# http://localhost:4000/streams      → LiveView Streams (efficient lists)
# http://localhost:4000/upload       → File upload form (multipart POST)
# http://localhost:4000/upload-demo  → LiveView uploads (chunked WebSocket + progress)
# http://localhost:4000/presence    → Presence tracking (open in 2+ tabs!)
# http://localhost:4000/users       → Resource route (JSON user list)
# http://localhost:4000/crash      → Error handler (500 page)
# http://localhost:4000/health    → Health check (JSON system metrics)
# curl -X POST -d "username=Jose" http://localhost:4000/users  → Flash + redirect
# http://localhost:4000/api/status   → JSON API response
# curl -X POST -H "Content-Type: application/json" -d '{"name":"Jose"}' http://localhost:4000/api/echo
# curl -X PUT -H "Content-Type: application/json" -d '{"username":"Updated"}' http://localhost:4000/users/42
# curl -F "file=@README.md" http://localhost:4000/upload  → Multipart file upload
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
│   │   ├── session.ex         # Signed cookie session encode/decode
│   │   ├── csrf.ex            # CSRF token generation & validation
│   │   ├── csp.ex             # Content Security Policy headers
│   │   ├── debug_page.ex     # Rich dev error page rendering
│   │   ├── router/
│   │   │   └── helpers.ex     # Path helper generation
│   │   ├── live_view.ex       # LiveView behaviour + component helpers
│   │   ├── live_component.ex  # LiveComponent behaviour
│   │   ├── pub_sub.ex         # PubSub (Erlang :pg wrapper)
│   │   ├── presence.ex        # Presence tracking (who's online)
│   │   ├── live_view/
│   │   │   ├── handler.ex     # WebSocket handler
│   │   │   ├── engine.ex      # Diffing engine
│   │   │   ├── eex_engine.ex  # Custom EEx engine for ~L sigil
│   │   │   ├── rendered.ex    # %Rendered{} struct
│   │   │   ├── stream.ex      # LiveView Streams
│   │   │   └── upload.ex      # LiveView upload helpers
│   │   ├── upload.ex          # %Ignite.Upload{} struct + temp file utils
│   │   ├── reloader.ex        # Hot code reloader
│   │   ├── rate_limiter.ex    # ETS-based rate limiting
│   │   ├── release.ex         # Release tasks (migrate, rollback)
│   │   ├── ssl.ex             # SSL/TLS config + Cowboy child spec
│   │   ├── ssl/
│   │   │   └── redirect_handler.ex  # HTTP→HTTPS 301 redirect
│   │   ├── hsts.ex            # HSTS header plug
│   │   └── adapters/
│   │       └── cowboy.ex      # Cowboy HTTP adapter
│   ├── mix/
│   │   └── tasks/
│   │       ├── ignite.routes.ex    # mix ignite.routes task
│   │       └── ignite.gen.cert.ex  # mix ignite.gen.cert task
│   └── my_app/                # Sample application
│       ├── repo.ex            # Ecto Repo (database connection)
│       ├── router.ex
│       ├── schemas/
│       │   └── user.ex        # User schema + changeset
│       ├── controllers/
│       └── live/
├── config/
│   ├── config.exs             # Application config (database, etc.)
│   ├── test.exs               # Test config (port 4002, test DB)
│   ├── prod.exs               # Production config (SSL, HSTS)
│   └── runtime.exs            # Runtime config (env vars for releases)
├── priv/
│   └── repo/
│       └── migrations/        # Ecto database migrations
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
| `ecto_sql` + `ecto_sqlite3` | Step 30 | Database persistence (SQLite) |

Steps 1-9 use **zero external dependencies** — only Elixir's standard library and Erlang's `:gen_tcp`.

## Roadmap: Nice-to-Have (Compared to Phoenix/LiveView)

Features that would bring Ignite closer to Phoenix for production use:

### Routing & Controllers
- [x] ~~Scoped routes (`scope "/api" do ... end`)~~ (Step 23)
- [x] ~~Path helpers (`user_path(:show, 42)` generating `/users/42`)~~ (Step 27)
- [x] ~~Resource routes (`resources "/posts", PostController`)~~ (Step 27)
- [x] ~~PUT/PATCH/DELETE HTTP methods~~ (Step 22)
- [x] ~~JSON response helper (`json(conn, %{ok: true})`)~~ (Step 21)

### LiveView
- [x] ~~Fine-grained diffing (track individual dynamic expressions, not whole HTML)~~ (Step 24)
- [x] ~~LiveView navigation (`live_redirect`, `push_patch` without full page reload)~~ (Step 18)
- [x] ~~LiveComponents (reusable stateful components within a LiveView)~~ (Step 19)
- [x] ~~Streams for large collections (append/prepend without re-rendering lists)~~ (Step 25)
- [x] ~~File uploads via LiveView~~ (Step 26)
- [x] ~~JS hooks (`phx-hook` equivalent for interop with JS libraries)~~ (Step 20)

### Security
- [x] ~~CSRF token generation and validation on forms~~ (Step 31)
- [x] ~~Signed/encrypted session cookies~~ (Step 28)
- [x] ~~Content Security Policy headers~~ (Step 32)
- [x] ~~Rate limiting middleware~~ (Step 40)

### Data & State
- [x] ~~Ecto integration for database access~~ (Step 30)
- [x] ~~PubSub for broadcasting between LiveView processes~~ (Step 17)
- [x] ~~Presence tracking (who's online)~~ (Step 29)
- [x] ~~Flash messages (`put_flash(conn, :info, "Saved!")`)~~ (Step 28)

### Developer Experience
- [x] ~~Mix tasks (`mix ignite.routes` to list all routes)~~ (Step 33)
- [x] ~~Debug error page with stacktrace (like Phoenix's dev error page)~~ (Step 34)
- [x] ~~Logger metadata (request ID, timing)~~ (Step 35)
- [x] ~~Static asset pipeline (CSS/JS bundling, fingerprinting)~~ (Step 37)
- [x] Test helpers (`ConnTest` for controller testing)

### Production
- [x] ~~SSL/TLS configuration~~ (Step 39)
- [ ] Telemetry integration for metrics
- [x] ~~Deployment with `mix release`~~ (Step 40)
- [x] ~~Health check endpoint~~ (Step 36)

## Using Ignite for New Projects (Future)

Currently, Ignite is a monolithic project where the framework (`lib/ignite/`) and the sample app (`lib/my_app/`) live in the same repo. To use Ignite as a standalone framework for new projects, there are two planned steps:

### Step 1: Publish as a Hex Package

Extract `lib/ignite/` into its own repo and publish to Hex. New projects would add it as a dependency:

```elixir
# New project's mix.exs
defp deps do
  [{:ignite, "~> 0.1"}]
end
```

Then users write their own router, controllers, and LiveViews — exactly like they do with Phoenix.

### Step 2: Project Generator (`mix ignite.new`)

Create a `mix ignite.new` task (like `mix phx.new`) that scaffolds a new project:

```bash
mix archive.install hex ignite_new
mix ignite.new my_blog
cd my_blog
mix deps.get
iex -S mix
```

This would generate:

```
my_blog/
├── mix.exs              # with {:ignite, "~> 0.1"} dep
├── lib/my_blog/
│   ├── router.ex        # use Ignite.Router
│   ├── application.ex   # OTP Application
│   ├── controllers/
│   └── live/
├── templates/
├── assets/
│   └── ignite.js
├── config/
│   ├── config.exs
│   └── runtime.exs
└── test/
```

This is the same pattern Phoenix uses — `phx_new` is a separate package that generates the scaffolding.

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](LICENSE) for the full text.

This means you are free to use, modify, and distribute this code, but if you run a modified version as a network service, you must make your source code available to users of that service.

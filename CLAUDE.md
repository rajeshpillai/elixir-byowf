# Ignite — Build a Phoenix-like Web Framework from Scratch

A step-by-step tutorial for Elixir beginners. Each step is one commit with working code and a detailed explanation.

## Prerequisites

- Elixir >= 1.14 installed (`elixir --version`)
- Basic terminal/command line skills
- A text editor or IDE
- A web browser and `curl` for testing

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
| 17 | [PubSub](tutorial/17-pubsub.md) | Cross-process messaging | `:pg`, broadcast, shared state |
| 18 | [Live Navigation](tutorial/18-live-navigation.md) | Client-side nav | `pushState`, route maps |
| 19 | [LiveComponents](tutorial/19-live-components.md) | Reusable components | Behaviours, process dictionary |
| 20 | [JS Hooks](tutorial/20-js-hooks.md) | Client-side hooks | DOM lifecycle, custom events |
| 21 | [JSON API](tutorial/21-json-api.md) | `json/3` helper | Content-type handling, Jason |
| 22 | [HTTP Methods](tutorial/22-http-methods.md) | PUT/PATCH/DELETE | REST, macro reuse |
| 23 | [Scoped Routes](tutorial/23-scoped-routes.md) | `scope` macro | AST transformation, nesting |
| 24 | [Fine-Grained Diffing](tutorial/24-fine-grained-diffing.md) | `~L` sigil, EEx engine | Compile-time separation, sparse diffs |
| 25 | [Streams](tutorial/25-streams.md) | LiveView streams | Efficient list rendering |
| 26 | [File Uploads](tutorial/26-file-uploads.md) | Multipart + WS uploads | Binary protocols, temp files |
| 27 | [Path Helpers](tutorial/27-path-helpers.md) | `_path` helpers, `resources` | Compile-time code generation |
| 28 | [Flash Messages](tutorial/28-flash-messages.md) | Signed cookie sessions | `Plug.Crypto`, redirect lifecycle |
| 29 | [Presence](tutorial/29-presence.md) | Who's online | `Process.monitor`, GenServer |
| 30 | [Ecto Integration](tutorial/30-ecto-integration.md) | Database persistence | Repo, Schema, Changeset, SQLite |
| 31 | [CSRF Protection](tutorial/31-csrf-protection.md) | Form security | XOR masking, `secure_compare` |
| 32 | [CSP Headers](tutorial/32-csp-headers.md) | Content Security Policy | Nonces, security headers |
| 33 | [Mix Routes Task](tutorial/33-mix-ignite-routes.md) | `mix ignite.routes` | Mix tasks, introspection |
| 34 | [Debug Error Page](tutorial/34-debug-error-page.md) | Rich dev errors | Stacktraces, HTML escaping |
| 35 | [Logger Metadata](tutorial/35-logger-metadata.md) | Request IDs, timing | `Logger.metadata`, monotonic time |
| 36 | [Health Check](tutorial/36-health-check.md) | `/health` endpoint | BEAM introspection, load balancers |
| 37 | [Static Assets](tutorial/37-static-asset-pipeline.md) | Cache-busting pipeline | ETS manifest, content hashing |
| 38 | [Test Helpers](tutorial/38-test-helpers.md) | `ConnTest` module | Test infrastructure, plug ordering fix |
| 39 | [SSL/TLS](tutorial/39-ssl-tls.md) | HTTPS support | Config-driven, HSTS, cert generation |
| 40 | [Release + Rate Limit](tutorial/40-release-and-rate-limit.md) | Production deploy | `mix release`, ETS rate limiter |

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
│   │   ├── controller.ex      # Response helpers (text, render)
│   │   ├── router.ex          # Router DSL macros
│   │   ├── live_view.ex       # LiveView behaviour
│   │   ├── live_view/
│   │   │   ├── handler.ex     # WebSocket handler
│   │   │   ├── engine.ex      # Diffing engine
│   │   │   ├── eex_engine.ex  # Custom EEx engine for ~L sigil
│   │   │   ├── rendered.ex    # %Rendered{} struct
│   │   │   └── stream.ex      # LiveView streams
│   │   ├── live_component.ex  # LiveComponent behaviour
│   │   ├── pub_sub.ex         # PubSub messaging
│   │   ├── presence.ex        # Presence tracking
│   │   ├── session.ex         # Signed cookie sessions
│   │   ├── csrf.ex            # CSRF protection
│   │   ├── csp.ex             # Content Security Policy
│   │   ├── hsts.ex            # HSTS headers
│   │   ├── ssl.ex             # SSL/TLS configuration
│   │   ├── static.ex          # Static asset pipeline
│   │   ├── upload.ex          # File upload handling
│   │   ├── debug_page.ex      # Dev error page
│   │   ├── rate_limiter.ex    # ETS rate limiter
│   │   ├── release.ex         # Release migration tasks
│   │   ├── conn_test.ex       # Test helpers
│   │   ├── reloader.ex        # Hot code reloader
│   │   ├── router/
│   │   │   └── helpers.ex     # Path helpers
│   │   └── adapters/
│   │       └── cowboy.ex      # Cowboy HTTP adapter
│   └── my_app/                # Sample application
│       ├── router.ex
│       ├── controllers/
│       └── live/
├── templates/                 # EEx HTML templates
├── assets/                    # Frontend JavaScript
│   └── ignite.js
├── tutorial/                  # Step-by-step tutorial docs
├── mix.exs                    # Project config & dependencies
└── skills.md                  # Reference code snippets
```

## Dependencies

| Dependency | Added at | Purpose |
|-----------|---------|---------|
| `plug_cowboy` | Step 10 | Production HTTP server |
| `jason` | Step 12 | JSON for LiveView diffs |
| `ecto_sql` | Step 30 | Database query builder, migrations |
| `ecto_sqlite3` | Step 30 | SQLite3 adapter for Ecto |

Steps 1–9 use **zero external dependencies** — only Elixir's standard library and Erlang's `:gen_tcp`.

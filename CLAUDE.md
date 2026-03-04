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

Steps 1–9 use **zero external dependencies** — only Elixir's standard library and Erlang's `:gen_tcp`.

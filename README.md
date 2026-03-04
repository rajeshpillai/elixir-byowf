# Ignite — Build a Phoenix-like Web Framework from Scratch

A step-by-step tutorial that teaches Elixir by building **Ignite**, a real web framework inspired by [Phoenix](https://www.phoenixframework.org/). You'll go from a raw TCP socket to a full-stack framework with LiveView, WebSockets, and DOM diffing — all in 16 incremental commits.

By the end, you'll understand every layer that powers production Elixir web applications: the conn pipeline, macro-based routing, OTP supervision, EEx templates, middleware plugs, and real-time LiveView with efficient DOM patching.

## What You'll Build

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
# http://localhost:4000            → Welcome text
# http://localhost:4000/hello      → Controller response
# http://localhost:4000/users/42   → EEx template with dynamic params
# http://localhost:4000/counter    → LiveView (real-time counter)
# http://localhost:4000/register   → LiveView form with real-time validation
# http://localhost:4000/crash      → Error handler (500 page)
# curl -X POST -d "username=Jose" http://localhost:4000/users  → POST parsing
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
│   ├── ignite.js              # LiveView client glue
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

Steps 1–9 use **zero external dependencies** — only Elixir's standard library and Erlang's `:gen_tcp`.

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](LICENSE) for the full text.

This means you are free to use, modify, and distribute this code, but if you run a modified version as a network service, you must make your source code available to users of that service.

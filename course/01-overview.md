> **Tip:** Open `course/assets/viewer.html` in a browser for an interactive view with dark/light theme, navigable diagrams, and animated walkthroughs.

# Ignite — A Phoenix-like Web Framework from Scratch

<!-- metadata: system_type=Modular monolith | languages=Elixir, JavaScript | generated=2026-03-24 -->

## What Is This?

**Ignite** is a fully functional Phoenix-like web framework built from scratch in Elixir as a step-by-step tutorial (44 steps). It is both a learning tool and a working framework that demonstrates how real web frameworks work under the hood — from raw TCP sockets to LiveView with real-time DOM patching.

## Problem It Solves

Most developers use frameworks as black boxes. Ignite demystifies web framework internals by building every layer incrementally: HTTP parsing, router DSL via macros, middleware pipelines, server-rendered templates, WebSocket-powered LiveView, diffing engines, PubSub, presence tracking, CSRF protection, and database integration — all with clear explanations at each step.

## Key Architectural Decisions

| Decision | Why |
|----------|-----|
| **Zero deps for steps 1–9** | Teaches fundamentals using only Elixir stdlib and Erlang's `:gen_tcp` before introducing external libraries |
| **Cowboy as HTTP server** | Industry-standard Erlang HTTP server, same as Phoenix; adapter pattern keeps framework code decoupled |
| **Macro-based Router DSL** | Demonstrates Elixir metaprogramming — routes compile into pattern-matching function clauses for O(1) dispatch |
| **Custom diffing engine** | Separates template statics (sent once) from dynamics (sent on change) — the core of LiveView's efficiency |
| **`:pg` for PubSub** | Erlang's built-in process groups — no external broker, automatic cleanup on process death |
| **SQLite via Ecto** | Zero-infrastructure database for tutorials; Ecto's adapter pattern makes switching to PostgreSQL trivial |
| **Signed cookie sessions** | Stateless sessions using `Plug.Crypto` HMAC signing — no server-side session store needed |

## Technology Stack

- **Elixir** on the BEAM VM (OTP supervision, hot code reloading, lightweight processes)
- **Cowboy** for production HTTP/HTTPS serving
- **Ecto** + **SQLite3** for database persistence
- **Jason** for JSON encoding (LiveView diffs, API responses)
- **morphdom** for efficient client-side DOM patching
- **Vanilla JavaScript** WebSocket client with event delegation

## How the Pieces Fit Together

The system is organized as a layered framework with a sample application on top:

1. **Core HTTP layer** — `%Ignite.Conn{}` struct flows through every request, carrying request data in and response data out
2. **Router DSL** — macros (`get`, `post`, `scope`, `resources`) compile into dispatch functions; middleware plugs run before dispatch
3. **Cowboy Adapter** — bridges Cowboy's request format to `%Conn{}`, handles sessions, logging, and error pages
4. **LiveView system** — WebSocket handler mounts stateful view processes, diffing engine minimizes payloads, client JS patches the DOM
5. **Security layer** — CSRF, CSP, HSTS, SSL/TLS, rate limiting — all implemented as middleware plugs
6. **Sample App** — controllers, LiveViews, and a Todo capstone app demonstrate all framework features

For the full architecture with diagrams and dependency graphs, see [Architecture Deep Dive](02-architecture.md).

---
[Index](01-overview.md) | [Next: Architecture Deep Dive >](02-architecture.md)

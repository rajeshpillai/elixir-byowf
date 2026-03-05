# Step 34: Debug Error Page

## What We're Building

A rich development error page that shows the exception type, message, full stacktrace with file:line info, and request context (method, path, headers, params, session) — like Phoenix's colorful dev error page. In production, a generic "Something went wrong" page is shown instead, leaking no internal details.

## The Problem

Before this step, when a controller crashes, the user sees:

```html
<h1>500 — Internal Server Error</h1>
<pre>This is a test crash!</pre>
```

No stacktrace. No file or line numbers. No request context. The developer must switch to the terminal to find the `Logger.error` output and mentally map the trace back to their code.

## How Phoenix Does It

Phoenix uses `Plug.Debugger` — a plug that catches exceptions and renders a detailed HTML page with:
- Exception type and message
- Stacktrace with syntax-highlighted source code snippets
- Request details (conn fields)
- Session data

Phoenix checks `Mix.env()` to decide whether to show the debug page or a generic error.

## Design Decision: Separate Module vs Inline

| Approach | Pros | Cons |
|----------|------|------|
| Inline in adapter | Less files | Clutters the adapter with 200+ lines of HTML/CSS |
| **Separate module** | Clean separation, testable, reusable | One more file |

We use a **separate `Ignite.DebugPage` module**. The Cowboy adapter stays focused on request handling; the debug page handles error presentation.

## Implementation

### 1. The DebugPage Module

**Create `lib/ignite/debug_page.ex`:**

```elixir
# lib/ignite/debug_page.ex
defmodule Ignite.DebugPage do
  def render(exception, stacktrace, conn) do
    if Application.get_env(:ignite, :env) == :prod do
      render_prod()
    else
      render_dev(exception, stacktrace, conn)
    end
  end

  defp render_prod do
    """
    <!DOCTYPE html>
    <html>
    <head><title>500 — Internal Server Error</title></head>
    <body style="font-family: system-ui; max-width: 600px; margin: 80px auto; text-align: center;">
      <h1 style="color: #e74c3c;">500 — Internal Server Error</h1>
      <p>Something went wrong. Please try again later.</p>
      <p><a href="/">Back to Home</a></p>
    </body>
    </html>
    """
  end

  defp render_dev(exception, stacktrace, conn) do
    exception_type = exception.__struct__ |> inspect() |> html_escape()
    message = Exception.message(exception) |> html_escape()
    trace_html = Enum.map_join(stacktrace, "\n", &format_entry/1)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{exception_type} — Ignite Debug</title>
      <style>
        body { font-family: system-ui, sans-serif; margin: 0; background: #f5f5f5; }
        header { background: #e74c3c; color: #fff; padding: 24px 32px; }
        header h1 { font-size: 1.4em; }
        header pre { background: rgba(0,0,0,0.2); padding: 12px; border-radius: 6px; }
        nav { background: #fff; border-bottom: 2px solid #e0e0e0; padding: 0 32px; }
        .tab { background: none; border: none; padding: 12px 20px; cursor: pointer; }
        .tab.active { color: #e74c3c; border-bottom: 3px solid #e74c3c; font-weight: 600; }
        .panel { display: none; padding: 24px 32px; }
        .panel.active { display: block; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 6px 12px; border-bottom: 1px solid #eee; font-family: monospace; }
        tr.app td { font-weight: 600; }
        tr.dep td { color: #999; }
      </style>
    </head>
    <body>
      <header><h1>#{exception_type}</h1><pre>#{message}</pre></header>
      <nav>
        <button class="tab active" onclick="showTab('stacktrace')">Stacktrace</button>
        <button class="tab" onclick="showTab('request')">Request</button>
        <button class="tab" onclick="showTab('session')">Session</button>
      </nav>
      <section id="stacktrace" class="panel active">
        <table><tbody>#{trace_html}</tbody></table>
      </section>
      <section id="request" class="panel">#{format_request(conn)}</section>
      <section id="session" class="panel">#{format_session(conn)}</section>
      <script>
        function showTab(id) {
          document.querySelectorAll('.panel').forEach(function(p) { p.classList.remove('active'); });
          document.querySelectorAll('.tab').forEach(function(t) { t.classList.remove('active'); });
          document.getElementById(id).classList.add('active');
          event.target.classList.add('active');
        }
      </script>
    </body>
    </html>
    """
  end
  # ... format_entry, format_request, format_session, html_escape below ...
end
```

**`render/3`** — The entry point. Uses `Application.get_env(:ignite, :env)` instead of
`Mix.env()` (since `Mix` is not available in releases — see Step 40).

### 2. Dev Mode: Rich Error Page

The dev page has three sections, switchable via inline JavaScript tabs:

**Stacktrace** — Each entry shows `Module.function/arity` and `file:line`. App frames (files under `lib/my_app/` or `lib/ignite/`) are shown bold; dependency frames are dimmed. This makes it easy to spot your code in a long trace.

**Request** — Method, path, parameters, and headers from `conn`.

**Session** — Session data (CSRF token, flash messages, etc.).

All CSS and JS are inlined — no external assets. This ensures the error page works even when the static asset pipeline is broken.

### 3. Stacktrace Entry Formatting

Elixir stacktraces are lists of `{module, function, arity_or_args, location}` tuples:

```elixir
[
  {MyApp.WelcomeController, :crash, 1,
   [file: ~c"lib/my_app/controllers/welcome_controller.ex", line: 114]},
  {Ignite.Adapters.Cowboy, :init, 2,
   [file: ~c"lib/ignite/adapters/cowboy.ex", line: 23]},
  {:cowboy_handler, :execute, 2,
   [file: ~c".../deps/cowboy/src/cowboy_handler.erl", line: 37]}
]
```

We format each entry into an HTML table row:

```elixir
defp format_entry({mod, fun, arity, location}) do
  arity_val = if is_list(arity), do: length(arity), else: arity
  func = "#{inspect(mod)}.#{fun}/#{arity_val}"
  file = Keyword.get(location, :file, ~c"") |> to_string()
  line = Keyword.get(location, :line, "?")
  app_class = if app_frame?(file), do: "app", else: "dep"

  "<tr class=\"#{app_class}\"><td>#{func}</td><td>#{file}:#{line}</td></tr>"
end
```

**`arity_or_args`** — Sometimes `arity` is the actual argument list (when the exception occurs during function call). We handle both cases: `is_list(arity)` → use `length`, otherwise use the integer directly.

**`app_frame?/1`** — Checks if the file path starts with `lib/my_app` or `lib/ignite`. App frames get the CSS class `app` (bold, dark text); everything else gets `dep` (light gray).

### 4. Wiring Into the Cowboy Adapter

The key change: move `conn` construction **before** the `try` block so it's accessible in `rescue`.

**Update `lib/ignite/adapters/cowboy.ex`** — move `conn` before `try` and replace `error_page/1` with `Ignite.DebugPage.render/3`:

```elixir
# lib/ignite/adapters/cowboy.ex
def init(req, state) do
  # Build conn OUTSIDE try — available in rescue for debug context
  conn = cowboy_to_conn(req)

  req =
    try do
      conn = MyApp.Router.call(conn)
      cookie_value = Ignite.Session.encode(conn.session)
      req = :cowboy_req.set_resp_cookie(Ignite.Session.cookie_name(), cookie_value, req,
              %{path: "/", http_only: true, same_site: :lax})
      :cowboy_req.reply(conn.status, conn.resp_headers, conn.resp_body, req)
    rescue
      exception ->
        Logger.error("""
        [Ignite] Request crashed:
        #{Exception.format(:error, exception, __STACKTRACE__)}
        """)

        # Pass conn for request context in the debug page
        :cowboy_req.reply(
          500,
          %{"content-type" => "text/html"},
          Ignite.DebugPage.render(exception, __STACKTRACE__, conn),
          req
        )
    end

  {:ok, req, state}
end
```

**Why move `conn` out?** Variables assigned inside a `try` block are not accessible in `rescue`. By building the conn before `try`, we can pass it to the debug page even when the router or controller crashes.

### 5. Production Safety

In production, the same `render/3` call returns a generic page:

```html
<h1>500 — Internal Server Error</h1>
<p>Something went wrong. Please try again later.</p>
```

No exception type, no message, no stacktrace, no request details. This prevents information leakage that attackers could exploit.

### 6. HTML Escaping

All dynamic content is HTML-escaped before rendering:

```elixir
defp html_escape(str) when is_binary(str) do
  str
  |> String.replace("&", "&amp;")
  |> String.replace("<", "&lt;")
  |> String.replace(">", "&gt;")
  |> String.replace("\"", "&quot;")
end
```

This prevents XSS in the error page itself — if an exception message contains `<script>`, it's rendered as text, not executed.

### 7. Self-Contained Design

The error page uses **inline CSS and JS** (no external assets). This is intentional: if the error is caused by a broken static asset pipeline or misconfigured routes, external stylesheets wouldn't load. By inlining everything, the error page always renders correctly.

## The Error Page Layout

```
┌─────────────────────────────────────────┐
│  RuntimeError                    (red)  │
│  ┌─────────────────────────────────┐    │
│  │ This is a test crash!           │    │
│  └─────────────────────────────────┘    │
├─────────────────────────────────────────┤
│ [Stacktrace]  [Request]  [Session]      │
├─────────────────────────────────────────┤
│ Module.function/arity         File      │
│ ──────────────────────────────────────  │
│ MyApp.WelcomeController.crash/1  (bold) │
│   lib/my_app/controllers/...ex:114      │
│ Ignite.Adapters.Cowboy.init/2    (bold) │
│   lib/ignite/adapters/cowboy.ex:23      │
│ :cowboy_handler.execute/2        (dim)  │
│   .../deps/cowboy/src/...erl:37         │
└─────────────────────────────────────────┘
```

## Testing

```bash
mix compile
iex -S mix

# 1. Visit the crash route
# http://localhost:4000/crash
# → Red header with "RuntimeError" and "This is a test crash!"
# → Stacktrace tab shows file:line for each frame
# → App frames (MyApp, Ignite) are bold; deps are dimmed

# 2. Click "Request" tab
# → Shows GET /crash, headers (host, user-agent, etc.)

# 3. Click "Session" tab
# → Shows _csrf_token value

# 4. Verify HTML escaping — raise with special chars
# In IEx: change crash action to raise "<script>alert(1)</script>"
# → The script tag appears as text, not executed
```

## Key Concepts

- **`Application.get_env(:ignite, :env)`** — Returns the current environment (`:dev`, `:test`, `:prod`). We use application config instead of `Mix.env()` because `Mix` is not available in compiled releases (see Step 40).
- **Stacktrace tuples** — `{module, function, arity_or_args, location}` where `location` is a keyword list with `:file` and `:line`. The `arity` field is sometimes the actual arguments list, not an integer.
- **Variable scoping in try/rescue** — Variables assigned inside `try` are not available in `rescue`. Move shared state before the `try` block.
- **Self-contained error pages** — Inline all CSS/JS so the error page works even when external assets are broken.
- **HTML escaping** — Always escape dynamic content in HTML output to prevent XSS, even in developer-only pages.
- **`__struct__` field** — Every Elixir struct has a hidden `__struct__` key that holds the module name. We use it to display the exception type (e.g., "RuntimeError", "KeyError") in the error page header:
  ```elixir
  exception.__struct__  #=> RuntimeError
  ```
- **`~c""` charlist sigil** — Creates a **charlist** (list of character codes), which is what Erlang uses for strings. Elixir stacktraces contain charlists for file paths because they come from the Erlang runtime. Use `to_string/1` to convert a charlist to an Elixir binary string:
  ```elixir
  ~c"lib/my_app/controllers/welcome_controller.ex"
  # Same as: 'lib/my_app/controllers/welcome_controller.ex'
  ```

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Module | `Ignite.DebugPage` | `Plug.Debugger` |
| Triggered by | `try/rescue` in adapter | `Plug.Debugger` plug |
| Stacktrace | File:line with app/dep highlighting | File:line with source code snippets |
| Request context | Method, path, headers, params, session | Full conn fields |
| Source code | Not shown (file:line only) | Shows surrounding lines |
| Dev/prod | `Mix.env()` check | Configurable via plug options |
| Styling | Inline CSS with tabs | Inline CSS with expandable sections |

Phoenix's `Plug.Debugger` goes further by showing actual source code lines around the error. Our version shows file:line references which are sufficient for navigating to the issue.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/debug_page.ex` | **New** — rich dev error page with stacktrace, request, session tabs |
| `lib/ignite/adapters/cowboy.ex` | Moved `conn` before `try`, replaced `error_page/1` with `Ignite.DebugPage.render/3` |

## File Checklist

- [ ] `lib/ignite/debug_page.ex` — **New**
- [ ] `lib/ignite/adapters/cowboy.ex` — **Modified** (move `conn` before `try`, use `Ignite.DebugPage.render/3`)

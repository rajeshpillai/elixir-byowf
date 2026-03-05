# Step 11: Error Handler

## What We're Building

When a controller crashes (nil access, bad math, database timeout),
the user should see a helpful error page — not a blank screen or a
"connection reset" error.

We're wrapping our adapter's request handling in `try/rescue` to catch
any exception, log the stacktrace, and return a styled 500 error page.

## Concepts You'll Learn

### try/rescue

Catches exceptions (errors raised with `raise`):

```elixir
try do
  raise "something broke"
rescue
  exception ->
    IO.puts("Caught: #{Exception.message(exception)}")
end
```

### __STACKTRACE__

Inside a `rescue` block, `__STACKTRACE__` gives you the call stack
that led to the error:

```elixir
rescue
  exception ->
    Logger.error(Exception.format(:error, exception, __STACKTRACE__))
```

This prints something like:
```
** (RuntimeError) This is a test crash!
    lib/my_app/controllers/welcome_controller.ex:18: MyApp.WelcomeController.crash/1
    lib/my_app/router.ex:15: MyApp.Router.dispatch/2
```

### Exception Module

Elixir provides helper functions for working with exceptions:

```elixir
Exception.message(exception)  # Human-readable message
Exception.format(:error, exception, stacktrace)  # Full formatted output
```

### The "Let It Crash" Boundary

In Elixir, you don't wrap every function in try/catch. Instead, you
define **boundaries** where errors are caught:

```
Controller (let it crash freely)
    ↓
Router (let it crash freely)
    ↓
Adapter (CATCHES HERE — the boundary)
    ↓
Cowboy (always replies to the browser)
```

The adapter is our error boundary. Everything inside can crash without
worrying about error handling.

## The Code

### Updated `lib/ignite/adapters/cowboy.ex`

**Update `lib/ignite/adapters/cowboy.ex`** — replace the `init/2` function and add `error_page/1` and `html_escape/1`:

```elixir
def init(req, state) do
  req =
    try do
      conn = cowboy_to_conn(req)
      conn = MyApp.Router.call(conn)
      :cowboy_req.reply(conn.status, conn.resp_headers, conn.resp_body, req)
    rescue
      exception ->
        Logger.error("[Ignite] Request crashed:\n" <>
          Exception.format(:error, exception, __STACKTRACE__))
        :cowboy_req.reply(500, %{"content-type" => "text/html"}, error_page(exception), req)
    end

  {:ok, req, state}
end
```

The `error_page/1` function generates a styled HTML page:

```elixir
defp error_page(exception) do
  message = Exception.message(exception) |> html_escape()

  """
  <!DOCTYPE html>
  <html>
  <head><title>500 — Internal Server Error</title></head>
  <body style="font-family: system-ui; max-width: 600px; margin: 50px auto;">
    <h1 style="color: #e74c3c;">Something went wrong</h1>
    <pre style="background: #f8f9fa; padding: 16px; border-radius: 8px;">#{message}</pre>
    <p><a href="/">Back to Home</a></p>
  </body>
  </html>
  """
end

defp html_escape(text) do
  text
  |> String.replace("&", "&amp;")
  |> String.replace("<", "&lt;")
  |> String.replace(">", "&gt;")
end
```

The `html_escape/1` function prevents XSS — without it, a crafted
exception message could inject JavaScript into the error page. In
production, you'd replace this with a generic "Something went wrong"
page that hides the exception details.

### Test Route

**Update `lib/my_app/controllers/welcome_controller.ex`** — add this `crash/1` function:

```elixir
def crash(_conn) do
  raise "This is a test crash!"
end
```

**Update `lib/my_app/router.ex`** — add a route for the crash test:

```elixir
get "/crash", to: MyApp.WelcomeController, action: :crash
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/crash

You should see a styled error page with the message "This is a test crash!"

3. Check your terminal — you'll see the full stacktrace:

```
[error] [Ignite] Request crashed:
** (RuntimeError) This is a test crash!
    lib/my_app/controllers/welcome_controller.ex:18: ...
```

4. Visit http://localhost:4000/ — the server is still running!
   The crash was contained to that single request.

## File Checklist

All files in the project after completing Step 11:

| File | Status |
|------|--------|
| `mix.exs` | Unchanged |
| `mix.lock` | Unchanged |
| `lib/ignite.ex` | Unchanged |
| `lib/ignite/application.ex` | Unchanged |
| `lib/ignite/server.ex` | Unchanged |
| `lib/ignite/conn.ex` | Unchanged |
| `lib/ignite/parser.ex` | Unchanged |
| `lib/ignite/router.ex` | Unchanged |
| `lib/ignite/controller.ex` | Unchanged |
| `lib/ignite/adapters/cowboy.ex` | **Modified** — added `try/rescue` error handling, `error_page/1`, and `html_escape/1` |
| `lib/my_app/router.ex` | **Modified** — added `/crash` test route |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — added `crash/1` action |
| `lib/my_app/controllers/user_controller.ex` | Unchanged |
| `templates/profile.html.eex` | Unchanged |

## What's Next

We have a solid HTTP framework. Now it's time for the "wow" feature:
**LiveView** — real-time UI updates without page refreshes.

In **Step 12**, we'll add WebSocket support so the server can **push**
updates to the browser. You'll build a live counter that increments
without any page reload.

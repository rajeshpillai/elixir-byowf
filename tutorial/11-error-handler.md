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

The `init/2` function now wraps the entire request pipeline in try/rescue:

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

The `error_page/1` function generates a styled HTML page showing the
error message. In production, you'd replace this with a generic
"Something went wrong" page.

### Test Route

We added a `/crash` route that intentionally raises:

```elixir
def crash(_conn) do
  raise "This is a test crash!"
end
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

## What's Next

We have a solid HTTP framework. Now it's time for the "wow" feature:
**LiveView** — real-time UI updates without page refreshes.

In **Step 12**, we'll add WebSocket support so the server can **push**
updates to the browser. You'll build a live counter that increments
without any page reload.

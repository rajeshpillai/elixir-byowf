# Step 8: Middleware Pipeline (Plugs)

## What We're Building

We want to run code **before** every request reaches the controller.
Common middleware tasks:
- Log every request
- Add security headers
- Check authentication
- Rate limiting

We're adding a `plug` macro so you can write:

```elixir
plug :log_request
plug :authenticate
```

If any plug sets `halted: true` on the conn, the pipeline stops and
the controller never runs — perfect for auth checks.

## Concepts You'll Learn

### Module Attributes with Accumulation

Module attributes are metadata stored on a module at compile time:

```elixir
Module.register_attribute(__MODULE__, :plugs, accumulate: true)

@plugs :log_request      # @plugs is now [:log_request]
@plugs :add_header        # @plugs is now [:add_header, :log_request]
```

With `accumulate: true`, each `@plugs` call **prepends** to a list
(that's why we reverse later).

### Enum.reduce/3

`reduce` transforms a list into a single value by passing an accumulator:

```elixir
Enum.reduce([1, 2, 3], 0, fn num, acc -> acc + num end)
#=> 6
```

For our plugs, the accumulator is the conn:

```elixir
Enum.reduce([:log_request, :add_header], conn, fn plug, conn ->
  apply(__MODULE__, plug, [conn])
end)
```

Each plug receives the conn, may modify it, and passes it to the next.

### The Pipeline Pattern

This is the core architecture of both Ignite and Phoenix:

```
Request → Plug 1 → Plug 2 → Plug 3 → Router → Controller → Response
              ↑                            ↑
        (can halt here)             (pattern matches)
```

Each step receives the conn and returns a (possibly modified) conn.
If any plug sets `conn.halted = true`, everything after it is skipped.

### Halting

A plug that rejects a request returns a halted conn:

```elixir
def authenticate(conn) do
  if valid_token?(conn) do
    conn
  else
    Ignite.Controller.text(conn, "Unauthorized", 401)
    # text/3 sets halted: true
  end
end
```

## The Code

### Updated Router (`lib/ignite/router.ex`)

Two new additions:

1. **`plug` macro** — registers a function name in `@plugs`:
   ```elixir
   defmacro plug(function_name) do
     quote do
       @plugs unquote(function_name)
     end
   end
   ```

2. **Updated `call/1`** — runs plugs before dispatching:
   ```elixir
   def call(conn) do
     conn = Enum.reduce(Enum.reverse(@plugs), conn, fn plug_func, acc ->
       if acc.halted, do: acc, else: apply(__MODULE__, plug_func, [acc])
     end)

     if conn.halted do
       conn
     else
       segments = String.split(conn.path, "/", trim: true)
       dispatch(conn, segments)
     end
   end
   ```

### Updated App Router (`lib/my_app/router.ex`)

```elixir
plug :log_request
plug :add_server_header

# Plug implementations
def log_request(conn) do
  Logger.info("[Ignite] #{conn.method} #{conn.path}")
  conn
end

def add_server_header(conn) do
  new_headers = Map.put(conn.resp_headers, "x-powered-by", "Ignite")
  %Ignite.Conn{conn | resp_headers: new_headers}
end
```

## How It Works

```
Request: GET /users/42

1. call(conn)
2. Run plugs:
   → log_request(conn)     # Prints "[Ignite] GET /users/42"
   → add_server_header(conn)  # Adds x-powered-by header
3. Not halted → dispatch
4. dispatch(conn, ["users", "42"])
5. UserController.show(conn)
6. Response includes x-powered-by: Ignite header
```

If a plug halts:
```
1. call(conn)
2. Run plugs:
   → authenticate(conn)    # Returns text(conn, "Unauthorized", 401)
   → conn.halted is true   # Skip remaining plugs
3. Halted → skip dispatch
4. Return 401 response directly
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit any URL — check your terminal for the log line:
   ```
   [info] [Ignite] GET /
   ```

3. Inspect response headers in your browser's Network tab:
   - Open DevTools (F12) → Network tab → click the request
   - Look for `x-powered-by: Ignite`

4. Every request — even 404s — goes through the plugs first.

## What's Next

Our framework can handle GET requests, but modern web apps need **forms**.
When a user submits a login form, the browser sends a POST request with
the form data in the **body**.

In **Step 9**, we'll build a **POST Body Parser** that reads the request
body and turns form data like `username=jose&password=secret` into
`conn.params`.

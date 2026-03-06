# Step 4: Response Helpers

## What We're Building

In Step 3, our controllers manually updated the conn struct:

```elixir
%Ignite.Conn{conn | resp_body: "Hello!"}
```

This is error-prone — we'd forget to set the status code, content type,
or the `halted` flag. We need helper functions like Phoenix has:

```elixir
text(conn, "Hello!")           # Plain text
html(conn, "<h1>Hello</h1>")  # HTML
```

We'll also move the HTTP response building out of the server into a
proper `send_resp/1` function.

## Concepts You'll Learn

### Import

`import` brings a module's functions into scope so you can call them
without the module prefix:

```elixir
import Ignite.Controller

# Now instead of:
Ignite.Controller.text(conn, "Hello")
# You can write:
text(conn, "Hello")
```

This is why Phoenix controllers can use `text`, `json`, `render` directly.

### Struct Update Syntax

The `%StructName{existing | key: new_value}` syntax creates a **new**
struct with some fields changed. The `|` (pipe) separates the existing
struct from the fields you want to override:

```elixir
conn = %Ignite.Conn{status: 200, resp_body: ""}
new_conn = %Ignite.Conn{conn | status: 404, resp_body: "Not Found"}
#                        ^^^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#                        base   fields to override

conn.status      #=> 200  (unchanged!)
new_conn.status  #=> 404  (new copy)
```

Read it as: "create a new `Ignite.Conn` starting from `conn`, but with
`status` set to 404 and `resp_body` set to `"Not Found"`."

This is **immutability** in action. You never modify data — you create
new versions. This makes debugging easier because you can always trace
back to the original.

> **Note:** Plain maps use `%{map | key: value}` (no struct name).
> Structs use `%StructName{struct | key: value}`. The `|` syntax only
> updates existing keys — it raises if you try to set a key that doesn't
> exist in the struct definition.

### Enum.map and Enum.join

We use these to convert the headers map into HTTP header strings:

```elixir
%{"content-type" => "text/plain", "content-length" => "5"}
|> Enum.map(fn {k, v} -> "#{k}: #{v}\r\n" end)
|> Enum.join()
#=> "content-type: text/plain\r\ncontent-length: 5\r\n"
```

### Multi-clause Functions (Again)

`status_text/1` uses pattern matching to map status codes:

```elixir
defp status_text(200), do: "OK"
defp status_text(404), do: "Not Found"
defp status_text(500), do: "Internal Server Error"
defp status_text(_),   do: "OK"
```

The `_` matches anything — it's the default/fallback clause.

## The Code

### `lib/ignite/controller.ex`

**Create `lib/ignite/controller.ex`.** Two response helpers and one serializer:

- **`text/3`** — sets plain text body, status, and content-type
- **`html/3`** — sets HTML body, status, and content-type
- **`send_resp/1`** — converts a conn into a raw HTTP string

The key pattern: helpers return a **modified conn**, not a string.
The conn accumulates response data as it flows through the system,
and `send_resp` converts it all at the end.

### Updated controllers

**Replace `lib/my_app/controllers/welcome_controller.ex` with:**

```elixir
defmodule MyApp.WelcomeController do
  import Ignite.Controller

  def index(conn), do: text(conn, "Welcome to Ignite!")
  def hello(conn), do: text(conn, "Hello from the Controller!")
end
```

### Updated server

**Update `lib/ignite/server.ex`** — replace the response-building code in `serve/1` with `Ignite.Controller.send_resp/1`, and remove the `build_response/2` function. The server no longer builds HTTP strings itself:

```elixir
response = Ignite.Controller.send_resp(conn)
:gen_tcp.send(client_socket, response)
```

The response building is now the controller module's responsibility.

## How It Works

The conn flows through the system, accumulating data:

```
Parser              Router              Controller          Server
  |                   |                    |                  |
  | %Conn{            |                    |                  |
  |   method: "GET",  |                    |                  |
  |   path: "/"       |                    |                  |
  | }                 |                    |                  |
  |------------------>|                    |                  |
  |                   | dispatch(conn)     |                  |
  |                   |------------------->|                  |
  |                   |                    | text(conn, "Hi") |
  |                   |                    |                  |
  |                   |  %Conn{            |                  |
  |                   |    status: 200,    |                  |
  |                   |    resp_body: "Hi" |                  |
  |                   |  }                 |                  |
  |                   |<-------------------|                  |
  |                   |                    |   send_resp(conn)|
  |                   |                    |   → HTTP string  |
```

## Try It Out

1. Start the server:

```bash
iex -S mix
iex> Ignite.Server.start()
```

2. Visit http://localhost:4000/ → "Welcome to Ignite!"

3. Visit http://localhost:4000/nope → "404 — Not Found"

4. Check the response headers in your browser's Network tab:
   - `content-type: text/plain`
   - `content-length: 18`
   - `connection: close`

The behavior looks the same as before, but the internals are now much
cleaner and the controller code is minimal.

## File Checklist

After this step, your project should have these files:

| File | Status | Purpose |
|------|--------|---------|
| `lib/ignite/controller.ex` | **New** | Response helpers (`text/3`, `html/3`, `send_resp/1`) |
| `lib/ignite/server.ex` | **Modified** | Uses `Ignite.Controller.send_resp/1` instead of raw HTTP strings |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** | Now uses `import Ignite.Controller` and `text/2` helper |
| `lib/ignite/conn.ex` | Unchanged | Conn struct (from Step 2) |
| `lib/ignite/parser.ex` | Unchanged | HTTP parser (from Step 2) |
| `lib/ignite/router.ex` | Unchanged | Router DSL (from Step 3) |
| `lib/my_app/router.ex` | Unchanged | App routes (from Step 3) |

## What's Next

Our router only matches exact paths like `"/hello"`. Real apps need
**dynamic segments** like `/users/42` or `/posts/my-first-post`.

In **Step 5**, we'll upgrade the router to handle path parameters:

```elixir
get "/users/:id", to: UserController, action: :show
```

The `:id` will be captured into `conn.params[:id]`.

---

[← Previous: Step 3 - Router DSL (Macros)](03-router-dsl.md) | [Next: Step 5 - Dynamic Route Matching →](05-dynamic-routes.md)

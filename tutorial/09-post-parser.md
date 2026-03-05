# Step 9: POST Body Parser

## What We're Building

When a user submits an HTML form, the browser sends a POST request with
the form data in the **body**:

```
POST /users HTTP/1.1
Content-Type: application/x-www-form-urlencoded
Content-Length: 25

username=jose&password=123
```

We need to read that body and parse it into `conn.params` so our
controller can use it:

```elixir
def create(conn) do
  username = conn.params["username"]  #=> "jose"
end
```

## Concepts You'll Learn

### HTTP Request Bodies

GET requests have no body — all data is in the URL. POST/PUT/PATCH
requests carry data in the body, after the headers.

The **Content-Length** header tells us how many bytes to read.
The **Content-Type** header tells us how to parse those bytes.

### :inet.setopts — Switching Socket Modes

Our socket uses `packet: :http`, which means Erlang automatically
parses HTTP request lines and headers. But the body is just raw bytes.

After reading headers, we switch the socket to raw mode:

```elixir
:inet.setopts(socket, packet: :raw)
```

Then we can read exactly `content_length` bytes:

```elixir
:gen_tcp.recv(socket, content_length)
```

### URI.decode_query/1

Parses URL-encoded form data:

```elixir
URI.decode_query("username=jose&password=123")
#=> %{"username" => "jose", "password" => "123"}
```

This handles:
- `&` as the separator between key-value pairs
- `=` as the separator between key and value
- `%20` as space, `%40` as `@`, etc. (percent-encoding)

### String Pattern Matching

We use `<>` (string concatenation) in pattern matching:

```elixir
defp parse_body(body, "application/x-www-form-urlencoded" <> _) do
  URI.decode_query(body)
end
```

The `<> _` means "starts with this string, ignore the rest." This handles
content types like `application/x-www-form-urlencoded; charset=UTF-8`.

## The Code

### Updated Parser (`lib/ignite/parser.ex`)

**Update `lib/ignite/parser.ex`** — add `read_body/2` and `parse_body/2`, and update `parse/1` to call `read_body` after reading headers:

First, update your existing `parse/1` to read the body and store it in params:

```elixir
def parse(client_socket) do
  {method, path} = read_request_line(client_socket)
  headers = read_headers(client_socket)

  # Parse body for POST/PUT/PATCH requests
  body_params = read_body(client_socket, headers)

  %Conn{
    method: to_string(method),
    path: path,
    headers: headers,
    params: body_params
  }
end
```

Then add these two private functions at the bottom of the module:

`read_body/2` checks for a Content-Length header, switches the socket from HTTP packet mode to raw binary mode, reads the body bytes, and delegates to `parse_body/2`:

```elixir
defp read_body(socket, headers) do
  case Map.get(headers, "content-length") do
    nil -> %{}
    length_str ->
      content_length = String.to_integer(length_str)
      :inet.setopts(socket, packet: :raw)

      case :gen_tcp.recv(socket, content_length) do
        {:ok, body} -> parse_body(body, Map.get(headers, "content-type", ""))
        _ -> %{}
      end
  end
end
```

`parse_body/2` uses pattern matching on the content-type string to decide how to parse. For form data, it uses `URI.decode_query/1`. For anything else, it returns the raw body:

```elixir
# Parses "username=jose&password=secret" into %{"username" => "jose", ...}
defp parse_body(body, "application/x-www-form-urlencoded" <> _) do
  URI.decode_query(body)
end

# Unknown content type — return body as-is under "_body" key
defp parse_body(body, _content_type) do
  %{"_body" => body}
end
```

### Updated Router

**Update `lib/my_app/router.ex`** — add this POST route:

```elixir
post "/users", to: MyApp.UserController, action: :create
```

### Updated UserController

**Update `lib/my_app/controllers/user_controller.ex`** — add this `create/1` function:

```elixir
def create(conn) do
  username = conn.params["username"] || "anonymous"
  text(conn, "User '#{username}' created successfully!", 201)
end
```

Note: POST body params use **string keys** (`"username"`), while URL
params use **atom keys** (`:id`). This matches Phoenix's behavior.

## How It Works

```
curl -X POST -d "username=jose" http://localhost:4000/users

1. Parser reads: POST /users HTTP/1.1
2. Parser reads headers:
   content-type: application/x-www-form-urlencoded
   content-length: 13
3. Parser switches to raw mode, reads 13 bytes: "username=jose"
4. URI.decode_query → %{"username" => "jose"}
5. conn.params = %{"username" => "jose"}
6. Router dispatches to UserController.create
7. Response: "User 'jose' created successfully!" (201)
```

## Try It Out

1. Start the server: `iex -S mix`

2. Test with curl:

```bash
curl -X POST http://localhost:4000/users \
     -d "username=jose" \
     -H "Content-Type: application/x-www-form-urlencoded"
```

You should see: `User 'jose' created successfully!`

3. Try with multiple fields:

```bash
curl -X POST http://localhost:4000/users \
     -d "username=jose&email=jose@elixir.org"
```

4. GET routes still work: http://localhost:4000/users/42

## File Checklist

All files in the project after completing Step 9:

| File | Status |
|------|--------|
| `mix.exs` | Unchanged |
| `lib/ignite.ex` | Unchanged |
| `lib/ignite/application.ex` | Unchanged |
| `lib/ignite/server.ex` | Unchanged |
| `lib/ignite/conn.ex` | Unchanged |
| `lib/ignite/parser.ex` | **Modified** — added `read_body/2` and `parse_body/2` for POST bodies |
| `lib/ignite/router.ex` | Unchanged |
| `lib/ignite/controller.ex` | Unchanged |
| `lib/my_app/router.ex` | **Modified** — added POST `/users` route |
| `lib/my_app/controllers/welcome_controller.ex` | Unchanged |
| `lib/my_app/controllers/user_controller.ex` | **Modified** — added `create/1` action |
| `templates/profile.html.eex` | Unchanged |

## What's Next

We've been using `:gen_tcp` — our hand-built TCP server. It works, but
it doesn't handle many edge cases that production apps need: HTTP/2,
SSL/TLS, keep-alive connections, and protection against malformed requests.

In **Step 10**, we'll replace our TCP server with **Cowboy** — the
battle-tested HTTP server used by Phoenix. We'll create an **adapter**
that translates between Cowboy and our `%Ignite.Conn{}` struct.

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

New `read_body/2` function:

1. Check if `content-length` header exists
2. If yes, switch socket to raw mode and read that many bytes
3. Parse the body based on content-type
4. Return params map

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

### Updated Router

Added a POST route:
```elixir
post "/users", to: MyApp.UserController, action: :create
```

### Updated UserController

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

## What's Next

We've been using `:gen_tcp` — our hand-built TCP server. It works, but
it doesn't handle many edge cases that production apps need: HTTP/2,
SSL/TLS, keep-alive connections, and protection against malformed requests.

In **Step 10**, we'll replace our TCP server with **Cowboy** — the
battle-tested HTTP server used by Phoenix. We'll create an **adapter**
that translates between Cowboy and our `%Ignite.Conn{}` struct.

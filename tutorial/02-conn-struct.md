# Step 2: The Conn Struct & Parser

## What We're Building

In Step 1, our server treated every request the same. Now we need to *understand*
what the browser is asking for.

We'll create two things:
1. **`%Ignite.Conn{}`** — a struct that holds all request and response data
2. **`Ignite.Parser`** — a module that reads the TCP socket and fills in the struct

This is the same pattern Phoenix uses with `%Plug.Conn{}`. The conn flows through
your entire application: parser → router → controller → response.

## Concepts You'll Learn

### Structs

A **struct** is a map with a fixed set of keys and default values:

```elixir
defmodule Ignite.Conn do
  defstruct [
    method: nil,
    path: nil,
    status: 200,
    resp_body: ""
  ]
end
```

You create one with `%Ignite.Conn{}`:

```elixir
conn = %Ignite.Conn{method: "GET", path: "/hello"}
conn.path   #=> "/hello"
conn.status #=> 200 (the default)
```

Unlike plain maps, structs **catch typos at compile time**:

```elixir
conn.nonexistent  #=> ** (KeyError) - Elixir catches this!
```

### The Alias Keyword

`alias` creates a shortcut so you don't have to type the full module name:

```elixir
alias Ignite.Conn

# Now you can write:
%Conn{method: "GET"}
# Instead of:
%Ignite.Conn{method: "GET"}
```

### `:gen_tcp.recv/2` — Reading from a Socket

`:gen_tcp.recv(socket, 0)` reads the next chunk of data from the TCP socket.
The `0` means "read whatever is available" (as opposed to a fixed number of bytes).

Because we set `packet: :http_bin` on the socket in Step 1, Erlang's built-in
HTTP parser automatically breaks the raw bytes into structured tuples:

| Raw bytes | Erlang returns |
|-----------|----------------|
| `GET /hello HTTP/1.1\r\n` | `{:ok, {:http_request, :GET, {:abs_path, "/hello"}, ...}}` |
| `Host: localhost:4000\r\n` | `{:ok, {:http_header, _, :Host, _, "localhost:4000"}}` |
| `\r\n` (blank line = end of headers) | `{:ok, :http_eoh}` |

This means we never have to manually split strings or parse HTTP ourselves —
Erlang does the heavy lifting, and we pattern match on the results.

### Accumulator Pattern

When reading headers, we use a common Elixir pattern — passing an accumulator
through recursive calls:

```elixir
defp read_headers(socket, acc \\ %{}) do
  case :gen_tcp.recv(socket, 0) do
    {:ok, :http_eoh} ->
      acc                                           # Done! Return what we collected

    {:ok, {:http_header, _, name, _, value}} ->
      key = name |> to_string() |> String.downcase()
      read_headers(socket, Map.put(acc, key, value))  # Add to acc, keep going
  end
end
```

The `name` from Erlang's HTTP parser might be an atom (`:Host`) or a string,
so we normalize it: convert to string, then lowercase. This ensures headers
are always accessed as `"host"`, `"content-type"`, etc.

The `\\` gives `acc` a default value of `%{}` (empty map), so callers don't
need to pass it.

### The Pipe Operator

The `|>` (pipe) operator passes the result of one function as the first
argument to the next:

```elixir
# Without pipe:
String.downcase(to_string(name))

# With pipe (reads top-to-bottom):
name |> to_string() |> String.downcase()
```

## The Code

### `lib/ignite/conn.ex`

**Create `lib/ignite/conn.ex`.** The struct definition below goes inside a `defmodule Ignite.Conn do ... end` block. Each field represents a piece of the request/response lifecycle:

```elixir
defstruct [
  # Request fields (filled by the parser)
  method: nil,       # "GET", "POST", etc.
  path: nil,         # "/users/42"
  headers: %{},      # %{"host" => "localhost:4000", ...}
  params: %{},       # URL and body parameters (used later)

  # Response fields (filled by controllers)
  status: 200,
  resp_headers: %{"content-type" => "text/plain"},
  resp_body: "",

  # Control flow
  halted: false      # When true, stops the middleware pipeline
]
```

### `lib/ignite/parser.ex`

**Create `lib/ignite/parser.ex`.** The parser reads from the socket and returns a filled-in `%Conn{}`. Here is the key function — see below for the complete file:

```elixir
def parse(client_socket) do
  {method, path} = read_request_line(client_socket)
  headers = read_headers(client_socket)

  %Conn{
    method: to_string(method),   # :GET → "GET"
    path: path,                  # "/hello"
    headers: headers             # %{"host" => "localhost:4000"}
  }
end
```

Key detail: `to_string(method)` converts the Erlang atom `:GET` into the
string `"GET"`, which is easier to work with in our router.

### Updated `lib/ignite/server.ex`

**Update `lib/ignite/server.ex`** — replace the `serve/1` function with the version below. The server now uses the parser:

```elixir
defp serve(client_socket) do
  conn = Ignite.Parser.parse(client_socket)

  body =
    case conn.path do
      "/fire" -> "Everything is on fire!"
      _ -> "Hello, Ignite! You requested: #{conn.path}"
    end

  response = build_response(200, body)
  :gen_tcp.send(client_socket, response)
  :gen_tcp.close(client_socket)
end
```

We've gone from "raw TCP data" to "structured Elixir data." The rest of
the framework will always work with `%Ignite.Conn{}` — never raw sockets.

## How It Works

```
TCP Socket ──→ Ignite.Parser.parse/1 ──→ %Ignite.Conn{
                                             method: "GET",
                                             path: "/fire",
                                             headers: %{"host" => "localhost:4000"}
                                           }
```

The parser is the **bridge** between the network layer (bytes on a wire)
and the application layer (Elixir data structures).

## Try It Out

1. Start the server:

```bash
iex -S mix
iex> Ignite.Server.start()
```

2. Visit http://localhost:4000/ — you'll see "Hello, Ignite! You requested: /"

3. Visit http://localhost:4000/fire — you'll see "Everything is on fire!"

4. Visit http://localhost:4000/anything — you'll see the path echoed back

5. Check your terminal — you'll see structured log output like:

```
[info] GET /
[info] GET /fire
```

## File Checklist

After this step, your project should have these files:

| File | Status | Purpose |
|------|--------|---------|
| `lib/ignite/conn.ex` | **New** | `%Ignite.Conn{}` struct for request/response data |
| `lib/ignite/parser.ex` | **New** | Reads TCP socket and fills in a `%Conn{}` |
| `lib/ignite/server.ex` | **Modified** | Now uses `Ignite.Parser` instead of raw reads |

## What's Next

The `case conn.path do` approach works, but it's not scalable. Imagine having
100 routes all in one big `case` statement!

In **Step 3**, we'll build a **Router DSL** using Elixir macros. You'll be
able to write clean, declarative routes like:

```elixir
get "/", to: WelcomeController, action: :index
get "/fire", to: WelcomeController, action: :fire
```

This is where Elixir's metaprogramming superpowers come in.

---

[← Previous: Step 1 - The TCP Socket Foundation](01-tcp-socket.md) | [Next: Step 3 - Router DSL (Macros) →](03-router-dsl.md)

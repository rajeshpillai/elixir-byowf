# Step 1: The TCP Socket Foundation

## What We're Building

Every web framework — Phoenix, Rails, Express, Django — is fundamentally just a program
that:

1. **Listens** on a TCP port (like port 4000)
2. **Accepts** a connection from a browser
3. **Reads** the HTTP request text
4. **Sends** back an HTTP response

In this step, we build exactly that: a TCP server that responds "Hello, Ignite!" to
every request.

## Concepts You'll Learn

### Modules and Functions

In Elixir, code lives inside **modules**. Think of a module as a named container for
related functions:

```elixir
defmodule Ignite.Server do
  def start(port \\ 4000) do
    # ...
  end
end
```

- `defmodule` defines a module
- `def` defines a public function
- `defp` defines a private function (only callable inside its module)
- `\\` sets a default argument value (`port` defaults to `4000`)

### Pattern Matching

Elixir uses `=` for **pattern matching**, not just assignment:

```elixir
{:ok, socket} = :gen_tcp.listen(port, opts)
```

This says: "I expect `gen_tcp.listen` to return a tuple starting with `:ok`.
Bind the second element to `socket`." If it returns `{:error, reason}` instead,
the program crashes — and that's intentional! (More on this in Step 6.)

### Atoms

Words starting with `:` are **atoms** — constants whose name is their value:

```elixir
:ok        # Success marker
:binary    # A flag for binary mode
:http      # A flag for HTTP parsing mode
```

They're used everywhere in Elixir for tags, options, and status codes.

### Erlang Interop

Elixir runs on the Erlang VM (BEAM). We can call Erlang modules directly
by using their atom names:

```elixir
:gen_tcp.listen(port, opts)   # Calls Erlang's gen_tcp:listen/2
```

`:gen_tcp` is an Erlang module that handles TCP networking.

### Recursion (Instead of Loops)

Elixir doesn't have `for` or `while` loops. Instead, we use **recursion**
— a function that calls itself:

```elixir
defp loop_acceptor(socket) do
  {:ok, client} = :gen_tcp.accept(socket)
  spawn(fn -> serve(client) end)
  loop_acceptor(socket)  # <-- calls itself
end
```

This runs forever, waiting for connections. The BEAM VM optimizes this
so it doesn't use extra stack space (tail-call optimization).

### BEAM Processes

`spawn/1` creates a new lightweight process:

```elixir
spawn(fn -> serve(client) end)
```

BEAM processes are NOT operating system threads. They are:
- **Extremely lightweight** (~2KB of memory each)
- **Isolated** — if one crashes, others keep running
- **Concurrent** — thousands can run at the same time

This is why we can handle each request in its own process.

## The Code

The server lives in `lib/ignite/server.ex`. Here's what each part does:

### Opening the Socket

```elixir
{:ok, listen_socket} = :gen_tcp.listen(port, [
  :binary,           # Receive data as binaries (Elixir strings)
  packet: :http,     # Let Erlang parse HTTP requests for us
  active: false,     # We control when to read (synchronous/pull mode)
  reuseaddr: true    # Can restart server immediately without port conflict
])
```

The `packet: :http` option is powerful — Erlang's built-in HTTP parser will
break the request into structured tuples instead of raw text.

### Accepting Connections

```elixir
defp loop_acceptor(listen_socket) do
  {:ok, client_socket} = :gen_tcp.accept(listen_socket)  # Blocks here
  spawn(fn -> serve(client_socket) end)                   # Handle in new process
  loop_acceptor(listen_socket)                            # Wait for next
end
```

`accept/1` blocks until a browser connects. Then we immediately spawn
a process and loop back. The server is always ready for the next request.

### Reading the HTTP Request

```elixir
defp read_request_line(socket) do
  {:ok, {:http_request, method, {:abs_path, path}, _version}} = :gen_tcp.recv(socket, 0)
  {method, path}
end
```

With `packet: :http`, Erlang parses `GET /hello HTTP/1.1` into:
`{:http_request, :GET, {:abs_path, "/hello"}, {1, 1}}`

We pattern match to extract the method (`:GET`) and path (`"/hello"`).

### Building the Response

```elixir
"HTTP/1.1 200 OK\r\n" <>
  "Content-Type: text/plain\r\n" <>
  "Content-Length: #{byte_size(body)}\r\n" <>
  "Connection: close\r\n" <>
  "\r\n" <>
  body
```

This is raw HTTP protocol. The `\r\n` (carriage return + line feed) and
the blank line between headers and body are required by the HTTP spec.

### Complete `lib/ignite/server.ex`

Here's the full module — put this in `lib/ignite/server.ex`:

```elixir
defmodule Ignite.Server do
  require Logger

  def start(port \\ 4000) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [
      :binary,
      packet: :http,
      active: false,
      reuseaddr: true
    ])

    Logger.info("Ignite is heating up on http://localhost:#{port}")

    loop_acceptor(listen_socket)
  end

  defp loop_acceptor(listen_socket) do
    {:ok, client_socket} = :gen_tcp.accept(listen_socket)
    spawn(fn -> serve(client_socket) end)
    loop_acceptor(listen_socket)
  end

  defp serve(client_socket) do
    {method, path} = read_request_line(client_socket)
    Logger.info("Received: #{inspect({method, path})}")

    body = "Hello, Ignite!"
    response = build_response(200, body)
    :gen_tcp.send(client_socket, response)
    :gen_tcp.close(client_socket)
  end

  defp read_request_line(socket) do
    {:ok, {:http_request, method, {:abs_path, path}, _version}} =
      :gen_tcp.recv(socket, 0)
    {method, path}
  end

  defp build_response(status, body) do
    "HTTP/1.1 #{status} OK\r\n" <>
      "Content-Type: text/plain\r\n" <>
      "Content-Length: #{byte_size(body)}\r\n" <>
      "Connection: close\r\n" <>
      "\r\n" <>
      body
  end
end
```

Note: `require Logger` makes the `Logger.info/1` macro available. This
is what produces the `[info] Received: {:GET, "/"}` output you'll see
in the terminal.

## How It Works

```
Browser                          Ignite Server
   |                                   |
   |--- TCP connect to port 4000 ----->|  :gen_tcp.accept/1 returns
   |                                   |
   |--- "GET / HTTP/1.1\r\n..." ------>|  :gen_tcp.recv/2 reads request
   |                                   |
   |<-- "HTTP/1.1 200 OK\r\n..." ------|  :gen_tcp.send/2 writes response
   |                                   |
   |--- Connection closed ------------->|  :gen_tcp.close/1
```

Each connection gets its own BEAM process, so many browsers can connect
at the same time.

## Try It Out

1. Start the Elixir shell with your project loaded:

```bash
iex -S mix
```

2. Start the server:

```elixir
iex> Ignite.Server.start()
```

You should see: `Ignite is heating up on http://localhost:4000`

3. Open your browser to http://localhost:4000

You should see: **Hello, Ignite!**

4. Try different URLs — http://localhost:4000/anything — they all return
   the same response. We'll fix that in Step 3 (Router).

5. Check your IEx terminal — you'll see log lines showing the request:

```
[info] Received: {:GET, "/"}
[info] Received: {:GET, "/favicon.ico"}
```

6. Stop the server with `Ctrl+C` twice.

## What's Next

Right now, every URL returns the same "Hello, Ignite!" response. We can't
tell the difference between `/` and `/about`.

In **Step 2**, we'll create an `%Ignite.Conn{}` struct — a data structure
that holds all the information about a request (method, path, headers) and
its response (status, body). This is the same pattern Phoenix uses with
`%Plug.Conn{}`.

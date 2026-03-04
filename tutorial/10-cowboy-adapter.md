# Step 10: Cowboy Adapter

## What We're Building

Our hand-built `:gen_tcp` server works, but it's missing critical
production features:
- **HTTP/2** support
- **SSL/TLS** (HTTPS)
- **Keep-alive** connections
- Protection against **malformed requests** and slow-loris attacks
- **Connection pooling** (multiple acceptors)

Instead of implementing all that ourselves (thousands of lines), we'll
use **Cowboy** — the same HTTP server Phoenix uses. We'll write an
**adapter** that translates between Cowboy and our `%Ignite.Conn{}`.

## Concepts You'll Learn

### Dependencies in Mix

Dependencies are declared in `mix.exs`:

```elixir
defp deps do
  [
    {:plug_cowboy, "~> 2.7"}
  ]
end
```

Then install them:
```bash
mix deps.get
```

`plug_cowboy` pulls in Cowboy, Ranch (the TCP acceptor pool), and Plug.

### The Adapter Pattern

An adapter translates between two interfaces that don't know about
each other:

```
Cowboy (speaks Cowboy requests) ←→ Adapter ←→ Ignite (speaks %Conn{})
```

Our framework doesn't know Cowboy exists. Cowboy doesn't know our
framework exists. The adapter sits in the middle and translates.

This means we could swap Cowboy for another server (like Bandit) by
writing a different adapter — no framework code changes needed.

### Cowboy Handler Behaviour

Cowboy calls our module's `init/2` for every request:

```elixir
@behaviour :cowboy_handler

@impl true
def init(req, state) do
  # req is a Cowboy request map
  # We must return {:ok, req, state}
end
```

The `req` object contains method, path, headers, and functions to read
the body.

### :cowboy_router.compile

Cowboy has its own routing, but we don't need it — we have our own
router. We tell Cowboy to send ALL requests to our adapter:

```elixir
:cowboy_router.compile([
  {:_, [{"/[...]", Ignite.Adapters.Cowboy, []}]}
])
```

- `:_` matches any hostname
- `"/[...]"` matches any path
- Everything goes to `Ignite.Adapters.Cowboy`

### :cowboy_req Functions

Cowboy provides helper functions to work with requests:

```elixir
:cowboy_req.has_body(req)        # Does this request have a body?
:cowboy_req.read_body(req)       # Read the body bytes
:cowboy_req.header("content-type", req, "")  # Get a header
:cowboy_req.reply(200, headers, body, req)   # Send response
```

## The Code

### `lib/ignite/adapters/cowboy.ex`

The adapter does three things:

1. **Convert** Cowboy request → `%Ignite.Conn{}`
2. **Route** through `MyApp.Router.call/1`
3. **Reply** via `:cowboy_req.reply/4`

```elixir
def init(req, state) do
  conn = cowboy_to_conn(req)
  conn = MyApp.Router.call(conn)

  req = :cowboy_req.reply(
    conn.status,
    conn.resp_headers,
    conn.resp_body,
    req
  )

  {:ok, req, state}
end
```

### Updated `lib/ignite/application.ex`

The supervisor now starts Cowboy instead of our gen_tcp server:

```elixir
dispatch = :cowboy_router.compile([
  {:_, [{"/[...]", Ignite.Adapters.Cowboy, []}]}
])

children = [
  %{
    id: :cowboy_listener,
    start: {:cowboy, :start_clear, [
      :ignite_http,
      [port: port],
      %{env: %{dispatch: dispatch}}
    ]}
  }
]
```

### What We Keep

- `Ignite.Server` still exists as a reference for steps 1-9
- `Ignite.Parser` is no longer used (Cowboy parses for us)
- The Router, Controller, and Conn are **unchanged** — the adapter
  handles the translation

## How It Works

```
Browser                    Cowboy                    Ignite
   |                         |                        |
   |--- HTTP request ------->|                        |
   |                         | Acceptor pool (100+)   |
   |                         | Parse HTTP             |
   |                         |                        |
   |                         |-- init(req, state) --->|
   |                         |                        | cowboy_to_conn(req)
   |                         |                        | Router.call(conn)
   |                         |                        | Controller action
   |                         |<- {:ok, req, state} ---|
   |                         |                        |
   |<-- HTTP response -------|                        |
```

Cowboy handles:
- 100+ acceptors (vs our single accept loop)
- HTTP protocol compliance
- Connection timeouts
- Malformed request rejection

## Try It Out

1. Install the dependency:

```bash
mix deps.get
```

2. Start the server:

```bash
iex -S mix
```

3. All your routes still work:
   - http://localhost:4000/ → "Welcome to Ignite!"
   - http://localhost:4000/users/42 → User profile page
   - http://localhost:4000/hello → "Hello from the Controller!"

4. Test POST:

```bash
curl -X POST http://localhost:4000/users \
     -d "username=jose"
```

5. The behavior is identical, but now you have a production-grade
   HTTP server underneath.

## What's Next

What happens when a controller crashes? Right now, Cowboy returns
a generic error. In **Step 11**, we'll add an **Error Handler** that
catches exceptions and returns a friendly 500 page with a logged
stacktrace.

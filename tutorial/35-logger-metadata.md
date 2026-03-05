# Step 35: Logger Metadata (Request ID + Timing)

## What We're Building

Structured request logging with two production-essential features: a unique **request ID** for correlating all log lines from the same request, and **response timing** to see how long each request takes. Every log line now looks like:

```
14:23:01.456 request_id=F3kQ7x_Nz2mYwA [info] GET /hello
14:23:01.458 request_id=F3kQ7x_Nz2mYwA [info] Sent 200 in 1.2ms
```

The request ID also appears in the `x-request-id` response header, so frontend developers and load balancers can correlate browser requests with server logs.

## The Problem

Before this step, request logging was:

```
[info] [Ignite] GET /hello
```

No request ID. No timing. In production with hundreds of concurrent requests:
- You can't tell which log lines belong to the same request
- You can't measure response times without external tooling
- You can't correlate a user's browser error with server logs

## How Phoenix Does It

Phoenix uses `Plug.Telemetry` — a plug that emits `:telemetry` events at the start and end of each request. The default `Phoenix.Logger` handler subscribes to these events and logs with the request metadata.

Phoenix also uses `Plug.RequestId` to read an incoming `x-request-id` header (from load balancers) or generate one, then attach it to `Logger.metadata`.

## Design Decision: Adapter vs Router Plug

| Approach | Pros | Cons |
|----------|------|------|
| Router plug | Follows existing plug pattern | Can't measure full request lifecycle; doesn't capture routing time |
| **Adapter-level** | Captures everything (parsing, routing, rendering) | Slightly different pattern from plugs |

We log at the **adapter level** because:
1. The adapter sees the complete request lifecycle — from raw Cowboy request to final response
2. Logger metadata set per-process naturally scopes to the request (Cowboy runs each request in its own process)
3. Timing captures the full stack, not just controller execution

This means we **remove** the `log_request` plug from the router — the adapter handles it now.

## Implementation

### 1. Logger Configuration

First, tell Elixir's Logger to include `request_id` metadata in the output format:

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

**`$metadata`** — A placeholder in the Logger format string that expands to all configured metadata keys. With `metadata: [:request_id]`, every log line includes `request_id=...` when that metadata is set.

**`$time`** — Shows the timestamp. Combined with request_id, you can reconstruct the exact sequence of events for any request.

### 2. Request ID Generation

```elixir
# lib/ignite/adapters/cowboy.ex
request_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
```

**`:crypto.strong_rand_bytes/1`** — Generates cryptographically secure random bytes from the OS entropy pool. 16 bytes = 128 bits of randomness, making collisions effectively impossible even at high request volumes.

**`Base.url_encode64/2`** — Encodes bytes as a URL-safe base64 string (uses `-` and `_` instead of `+` and `/`). `padding: false` omits trailing `=` signs. Result: a compact 22-character string like `F3kQ7x_Nz2mYwAbcDeFgHi`.

### 3. Logger Metadata

```elixir
Logger.metadata(request_id: request_id)
```

**`Logger.metadata/1`** — Attaches key-value pairs to the current process's Logger context. Because Cowboy spawns a fresh process per request, the metadata is automatically scoped — it applies to every `Logger.info/1` call in the same process (including calls inside the router, plugs, and controllers) and is automatically cleaned up when the process exits.

This is why Elixir's process model is so powerful for web servers: per-request state comes for free.

### 4. Monotonic Timing

```elixir
start_time = System.monotonic_time()
# ... handle request ...
diff = System.monotonic_time() - start_time
micro = System.convert_time_unit(diff, :native, :microsecond)
```

**`System.monotonic_time/0`** — Returns a monotonically increasing time value. Unlike `System.system_time/0`, it's immune to NTP adjustments and clock skew. If the system clock jumps backward (daylight saving, NTP sync), monotonic time keeps counting forward.

**`:native` time units** — The BEAM stores time in its native resolution (nanoseconds on most systems). `System.convert_time_unit/3` converts to human-readable units.

**Duration formatting** — We show `µs` for sub-millisecond, `ms` for sub-second, and `s` for longer requests:

```elixir
defp log_duration(start_time) do
  diff = System.monotonic_time() - start_time
  micro = System.convert_time_unit(diff, :native, :microsecond)

  cond do
    micro < 1_000 -> "#{micro}µs"
    micro < 1_000_000 -> "#{Float.round(micro / 1_000, 1)}ms"
    true -> "#{Float.round(micro / 1_000_000, 2)}s"
  end
end
```

### 5. Wiring It All Together

```elixir
# lib/ignite/adapters/cowboy.ex
def init(req, state) do
  request_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  Logger.metadata(request_id: request_id)
  start_time = System.monotonic_time()

  conn = cowboy_to_conn(req)
  conn = put_in(conn.private[:request_id], request_id)

  Logger.info("#{conn.method} #{conn.path}")

  req =
    try do
      conn = MyApp.Router.call(conn)
      # ... session cookie ...

      # Add request ID to response headers
      resp_headers = Map.put(conn.resp_headers, "x-request-id", request_id)

      duration = log_duration(start_time)
      Logger.info("Sent #{conn.status} in #{duration}")

      :cowboy_req.reply(conn.status, resp_headers, conn.resp_body, req)
    rescue
      exception ->
        duration = log_duration(start_time)
        Logger.error("[Ignite] Request crashed (#{duration}): ...")
        :cowboy_req.reply(500, %{"x-request-id" => request_id, ...}, ..., req)
    end

  {:ok, req, state}
end
```

**Request ID in `conn.private`** — Stored via `put_in(conn.private[:request_id], request_id)` so controllers can access it if needed (e.g., to include in error responses or pass to external services).

**`x-request-id` response header** — Added to both successful and error responses. Load balancers (nginx, AWS ALB) can use this for request tracing across services.

### 6. Removing the Router Plug

Since the adapter now logs `GET /path` and `Sent 200 in 1.2ms` with metadata, the router's `log_request` plug is redundant. We remove it:

```elixir
# lib/my_app/router.ex
# Before:
plug :log_request
plug :add_server_header

# After:
# Note: request logging is now handled by the Cowboy adapter
plug :add_server_header
```

## The Log Flow

```
Request arrives at Cowboy
    │
    ├── Generate request_id: "F3kQ7x_Nz2mYwA"
    ├── Logger.metadata(request_id: "F3kQ7x_Nz2mYwA")
    ├── start_time = System.monotonic_time()
    │
    ├── LOG: "request_id=F3kQ7x_Nz2mYwA [info] GET /hello"
    │
    ├── Router.call(conn) → runs plugs → runs controller
    │   └── Any Logger calls inside also get request_id automatically
    │
    ├── LOG: "request_id=F3kQ7x_Nz2mYwA [info] Sent 200 in 0.8ms"
    │
    └── Response includes header: x-request-id: F3kQ7x_Nz2mYwA
```

## Testing

```bash
mix compile
iex -S mix

# 1. Visit any route and check terminal output
# curl http://localhost:4000/hello
# Terminal shows:
#   14:23:01.456 request_id=F3kQ7x_Nz2mYwA [info] GET /hello
#   14:23:01.458 request_id=F3kQ7x_Nz2mYwA [info] Sent 200 in 1.2ms

# 2. Check response headers for x-request-id
# curl -v http://localhost:4000/hello 2>&1 | grep x-request-id
# → x-request-id: F3kQ7x_Nz2mYwA

# 3. Verify crash logs also include request_id + timing
# curl http://localhost:4000/crash
# Terminal shows:
#   14:23:02.100 request_id=xYz123AbCdEfGh [info] GET /crash
#   14:23:02.101 request_id=xYz123AbCdEfGh [error] [Ignite] Request crashed (0.4ms): ...

# 4. Multiple concurrent requests have different IDs
# curl http://localhost:4000/hello & curl http://localhost:4000/hello &
# Each pair of log lines has a distinct request_id
```

## Key Concepts

- **`Logger.metadata/1`** — Sets per-process metadata that appears in every subsequent log call. Because BEAM processes are isolated, no locking or thread-local storage is needed — the metadata naturally scopes to the current request.
- **`System.monotonic_time/0`** — A clock that only moves forward, regardless of system clock changes. Essential for accurate timing measurements.
- **`:crypto.strong_rand_bytes/1`** — Cryptographically secure random bytes from the OS. Used for request IDs, CSRF tokens, session signing — any context where predictability would be a security risk.
- **`x-request-id` header** — Industry convention for distributed tracing. Load balancers, API gateways, and microservices use this header to correlate requests across service boundaries.
- **Adapter-level logging** — Logging at the Cowboy adapter captures the full request lifecycle. Plug-level logging only captures the middleware/controller portion.
- **`cond do`** — Evaluates conditions top-to-bottom and runs the first truthy one, like an `if/else if` chain. The final `true ->` acts as a default clause:
  ```elixir
  cond do
    duration < 1_000 -> "#{duration}µs"
    duration < 1_000_000 -> "#{Float.round(duration / 1_000, 1)}ms"
    true -> "#{Float.round(duration / 1_000_000, 2)}s"
  end
  ```
- **`put_in/2`** — Sets a value at a nested path. The path uses Access syntax — `conn.private[:request_id]` navigates into `conn`, then its `private` map, then the `:request_id` key. It's a shorthand for updating nested maps without multiple `Map.put` calls:
  ```elixir
  conn = put_in(conn.private[:request_id], "abc-123")
  ```

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Request ID | Generated in adapter, 16 bytes base64url | `Plug.RequestId` — reads incoming header or generates UUID |
| Metadata | `Logger.metadata(request_id: ...)` | Same — `Logger.metadata/1` |
| Timing | `System.monotonic_time` in adapter | `:telemetry` events + `Phoenix.Logger` |
| Log format | `$time $metadata[$level] $message` | Same default format |
| Response header | `x-request-id` | `x-request-id` |
| Config | `config :logger, :console, metadata: [:request_id]` | Same |

Phoenix uses the `:telemetry` library for a more extensible event system (you can attach multiple handlers to the same events). Our approach is simpler — direct Logger calls — which is sufficient for a single-app framework.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/adapters/cowboy.ex` | Request ID generation, `Logger.metadata`, monotonic timing, `x-request-id` header, `log_duration/1` helper |
| `lib/my_app/router.ex` | Removed `log_request` plug (adapter handles it now) |
| `config/config.exs` | Logger console format with `request_id` metadata |

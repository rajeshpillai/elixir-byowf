# Step 40 — Deployment with `mix release` + Rate Limiting

This step makes Ignite production-deployable. We fix runtime issues that break in releases, add environment variable configuration, create release migration tasks, and build an ETS-based rate limiter — all with zero new dependencies.

## What We Built

| Module / File | Purpose |
|---|---|
| `config/runtime.exs` | Reads env vars (`PORT`, `DATABASE_PATH`, `SECRET_KEY_BASE`, SSL paths) at release boot |
| `Ignite.Release` | Migration tasks callable from a release binary (no Mix needed) |
| `Ignite.RateLimiter` | ETS-based sliding window rate limiter with GenServer cleanup |
| Updated `Ignite.Session` | Configurable secret key (reads from config instead of hardcoded) |
| Updated `Ignite.DebugPage` | Fixed `Mix.env()` → config-based environment check |

## Part A: `mix release` Support

### The Problem: `Mix.env()` at Runtime

`Mix` is a build tool. When you build a release with `mix release`, the Mix module **is not included** in the release binary. Any code that calls `Mix.env()` at runtime will crash:

```
(UndefinedFunctionError) function Mix.env/0 is undefined
```

We had two offending call sites:

| File | Line | Code |
|---|---|---|
| `lib/ignite/application.ex` | 75 | `if Mix.env() == :dev` |
| `lib/ignite/debug_page.ex` | 22 | `if Mix.env() == :prod` |

The `mix.exs` line `start_permanent: Mix.env() == :prod` is fine — it runs at compile time only.

### The Fix: `config_env()` + Application Config

We store the environment at compile time using `config_env()`.

**Update `config/config.exs`** — add `env: config_env()`:

```elixir
# config/config.exs
config :ignite, env: config_env()
```

Then read it at runtime.

**Update `lib/ignite/application.ex`** and **Update `lib/ignite/debug_page.ex`** — replace `Mix.env()` with config lookup:

```elixir
# Instead of Mix.env() == :dev
Application.get_env(:ignite, :env) == :dev
```

This works everywhere — in `iex -S mix`, in `MIX_ENV=prod mix run`, and in releases.

### `config/runtime.exs`

This file runs at boot time in both `iex -S mix` and releases. It reads environment variables.

**Create `config/runtime.exs`:**

```elixir
import Config

# runtime.exs is evaluated at boot time — both in `iex -S mix` and in
# a release. Use System.get_env/1 here to read environment variables.
# These override values set in config.exs / prod.exs / test.exs.

if config_env() == :prod do
  # Port — default to 4443 for HTTPS, override with $PORT
  port =
    case System.get_env("PORT") do
      nil -> 4443
      val -> String.to_integer(val)
    end

  config :ignite, port: port

  # Database path (SQLite).
  # For production, set DATABASE_PATH to an absolute path on the server.
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: export DATABASE_PATH=/var/data/ignite_prod.db
      """

  config :ignite, MyApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Secret key for session cookie signing.
  # Must be at least 64 bytes for security.
  # Generate one with: openssl rand -base64 64
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: openssl rand -base64 64
      """

  config :ignite, secret_key_base: secret_key_base

  # SSL certificate paths (optional).
  # Omit these to run plain HTTP behind a reverse proxy (nginx, Caddy, etc.).
  ssl_certfile = System.get_env("SSL_CERTFILE")
  ssl_keyfile = System.get_env("SSL_KEYFILE")

  if ssl_certfile && ssl_keyfile do
    config :ignite,
      ssl: [
        certfile: ssl_certfile,
        keyfile: ssl_keyfile
      ]
  end

  # HTTP→HTTPS redirect port (optional)
  case System.get_env("HTTP_REDIRECT_PORT") do
    nil -> :ok
    val -> config(:ignite, http_redirect_port: String.to_integer(val))
  end

  # Rate limiting override (optional)
  case System.get_env("RATE_LIMIT_MAX") do
    nil ->
      :ok

    val ->
      window = String.to_integer(System.get_env("RATE_LIMIT_WINDOW_MS") || "60000")
      config :ignite, rate_limit: [max_requests: String.to_integer(val), window_ms: window]
  end
end
```

Required env vars for production:
- `DATABASE_PATH` — absolute path to the SQLite file
- `SECRET_KEY_BASE` — at least 64 bytes, for session cookie signing

Optional:
- `PORT` — defaults to 4443
- `SSL_CERTFILE` / `SSL_KEYFILE` — enables HTTPS
- `HTTP_REDIRECT_PORT` — enables HTTP→HTTPS redirect
- `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW_MS` — override rate limit config

### Configurable Session Secret

The session module previously had a hardcoded `@secret`. Now it reads from config with a dev fallback.

**Update `lib/ignite/session.ex`** — replace hardcoded secret with configurable secret:

```elixir
@default_secret "ignite-secret-key-change-in-prod-min-64-bytes-long-for-security!!"

defp secret do
  Application.get_env(:ignite, :secret_key_base, @default_secret)
end
```

In dev/test, the default is used automatically. In production (via `runtime.exs`), the `SECRET_KEY_BASE` env var is required.

### Release Migration Tasks

In a release, `mix ecto.migrate` doesn't exist. `Ignite.Release` provides the same functionality.

**Create `lib/ignite/release.ex`:**

```elixir
# lib/ignite/release.ex
defmodule Ignite.Release do
  @app :ignite

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:ecto_sql)
    Application.load(@app)
  end
end
```

Run from a release:
```bash
bin/ignite eval "Ignite.Release.migrate()"
bin/ignite eval "Ignite.Release.rollback(MyApp.Repo, 20240301120000)"
```

`Ecto.Migrator.with_repo/2` boots the repo, runs migrations, then shuts it down cleanly.

### Release Configuration

**Update `mix.exs`** — add release configuration:

```elixir
releases: [
  ignite: [
    include_executables_for: [:unix],
    steps: [:assemble, :tar]
  ]
]
```

The `:tar` step packages the release as a `.tar.gz` for easy deployment.

## Part B: Rate Limiting

### The Algorithm: Sliding Window

We use a **sliding window counter** stored in an ETS `:bag` table. Each request inserts `{client_ip, timestamp}`. To check the rate, we count entries within the last N milliseconds.

```
Window: 60 seconds, Max: 100 requests

Timeline:  ──────[────────── 60s window ──────────]──→
Requests:        ●●●●●●●● ... ●●●●  (98 entries)
New request:                         ●  → count=99, ALLOW
Next request:                           ● → count=100, ALLOW
Next request:                             ● → count=101, REJECT (429)
```

Why sliding window over fixed buckets? Fixed windows have a burst problem at boundaries — a client could make 100 requests at 0:59 and 100 more at 1:01, getting 200 requests in 2 seconds. Sliding windows prevent this.

### Client IP Extraction

**Update `lib/ignite/adapters/cowboy.ex`** — extract the peer IP:

```elixir
{peer_ip_tuple, _peer_port} = :cowboy_req.peer(req)
peer_ip = peer_ip_tuple |> :inet.ntoa() |> to_string()
```

The rate limiter checks `x-forwarded-for` first (for clients behind a reverse proxy), then falls back to the peer IP:

```elixir
defp client_ip(conn) do
  case Map.get(conn.headers, "x-forwarded-for") do
    nil -> Map.get(conn.private, :peer_ip, "unknown")
    forwarded ->
      forwarded |> String.split(",") |> List.first() |> String.trim()
  end
end
```

### Rate Limit Headers

Every response includes standard rate limit headers:

```
x-ratelimit-limit: 100
x-ratelimit-remaining: 97
x-ratelimit-reset: 1709568000
```

When exceeded:

```
HTTP/1.1 429 Too Many Requests
retry-after: 60
content-type: application/json

{"error":"Too Many Requests","message":"Rate limit exceeded. Try again in 60 seconds.","retry_after":60}
```

### The RateLimiter GenServer

**Create `lib/ignite/rate_limiter.ex`:**

```elixir
# lib/ignite/rate_limiter.ex
defmodule Ignite.RateLimiter do
  use GenServer
  require Logger

  @table :ignite_rate_limiter
  @default_max 100
  @default_window_ms 60_000

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Rate limit plug entry point.

  Checks the request rate for the client's IP. If within the limit,
  adds rate limit headers and returns the conn (pipeline continues).
  If exceeded, halts the conn with 429.
  """
  def call(conn) do
    config = Application.get_env(:ignite, :rate_limit, [])
    max_requests = Keyword.get(config, :max_requests, @default_max)
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)

    ip = client_ip(conn)
    now = System.monotonic_time(:millisecond)

    # Record this request
    :ets.insert(@table, {ip, now})

    # Count requests in the current window
    cutoff = now - window_ms
    count = count_requests(ip, cutoff)

    remaining = max(max_requests - count, 0)
    retry_after_secs = div(window_ms, 1000)
    reset_unix = System.os_time(:second) + retry_after_secs

    conn = add_rate_limit_headers(conn, max_requests, remaining, reset_unix)

    if count > max_requests do
      Logger.warning(
        "[RateLimiter] Rate limit exceeded for #{ip} " <>
          "(#{count}/#{max_requests} in #{window_ms}ms)"
      )

      conn
      |> add_resp_header("retry-after", Integer.to_string(retry_after_secs))
      |> Ignite.Controller.json(
        %{
          error: "Too Many Requests",
          message: "Rate limit exceeded. Try again in #{retry_after_secs} seconds.",
          retry_after: retry_after_secs
        },
        429
      )
    else
      conn
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # :bag allows multiple {ip, timestamp} entries per key
    :ets.new(@table, [
      :named_table,
      :bag,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    config = Application.get_env(:ignite, :rate_limit, [])
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    cutoff = System.monotonic_time(:millisecond) - window_ms

    # Delete all entries older than the window.
    match_spec = [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}]
    deleted = :ets.select_delete(@table, match_spec)

    if deleted > 0 do
      Logger.debug("[RateLimiter] Cleaned up #{deleted} expired entries")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp count_requests(ip, cutoff) do
    # Count entries for this IP where timestamp >= cutoff (within window)
    match_spec = [{{ip, :"$1"}, [{:>=, :"$1", cutoff}], [true]}]
    :ets.select_count(@table, match_spec)
  end

  defp client_ip(conn) do
    # Check x-forwarded-for first (behind reverse proxy like nginx/CloudFlare)
    case Map.get(conn.headers, "x-forwarded-for") do
      nil ->
        Map.get(conn.private, :peer_ip, "unknown")

      forwarded ->
        # x-forwarded-for can contain multiple IPs: "client, proxy1, proxy2"
        forwarded |> String.split(",") |> List.first() |> String.trim()
    end
  end

  defp add_rate_limit_headers(conn, limit, remaining, reset_unix) do
    new_headers =
      conn.resp_headers
      |> Map.put("x-ratelimit-limit", Integer.to_string(limit))
      |> Map.put("x-ratelimit-remaining", Integer.to_string(remaining))
      |> Map.put("x-ratelimit-reset", Integer.to_string(reset_unix))

    %Ignite.Conn{conn | resp_headers: new_headers}
  end

  defp add_resp_header(conn, key, value) do
    new_headers = Map.put(conn.resp_headers, key, value)
    %Ignite.Conn{conn | resp_headers: new_headers}
  end

  defp schedule_cleanup do
    config = Application.get_env(:ignite, :rate_limit, [])
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    # Clean up at the window interval, capped at 60s
    interval = min(window_ms, 60_000)
    Process.send_after(self(), :cleanup, interval)
  end
end
```

### GenServer Cleanup

The GenServer periodically deletes expired entries using `:ets.select_delete/2` with a match spec:

```elixir
match_spec = [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}]
:ets.select_delete(@table, match_spec)
```

This prevents unbounded memory growth. The cleanup runs every `window_ms` milliseconds (or every 60 seconds, whichever is smaller).

### Configuration

**Update `config/config.exs`** — add rate limit defaults:

```elixir
# config/config.exs (defaults)
config :ignite,
  rate_limit: [
    max_requests: 100,   # per window
    window_ms: 60_000    # 1 minute
  ]
```

Override at runtime with `RATE_LIMIT_MAX` and `RATE_LIMIT_WINDOW_MS` env vars.

## Concepts Learned

### `Application.ensure_all_started/1` and `Application.load/1`

```elixir
Application.ensure_all_started(:ssl)      # Starts the :ssl app and its dependencies
Application.load(:ignite)                  # Loads config without starting the app
```

In a Mix release, your app's full supervision tree isn't running when you call `bin/ignite eval "..."`. These functions manually boot just enough of the runtime to run migrations.

### `System.get_env/1`

```elixir
System.get_env("DATABASE_URL")  #=> "ecto://..." or nil
System.get_env("PORT")          #=> "4000" (always a string, or nil)
```

Reads OS environment variables. Returns `nil` if not set. Values are always strings — use `String.to_integer/1` to convert numbers.

### `config/runtime.exs`

Unlike `config.exs` (which runs at **compile time**), `runtime.exs` runs at **boot time** — every time your app starts. This is the only config file included in Mix releases, making it the right place for environment variables and secrets that differ between deployments.

### ETS Match Specs (Detailed)

```elixir
match_spec = [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}]
:ets.select_delete(@table, match_spec)
```

Match specs are Erlang's way of querying ETS tables efficiently. The format is `[{pattern, guards, result}]`:
- `{:_, :"$1"}` — pattern: match any key, capture the timestamp as variable `$1`
- `[{:<, :"$1", cutoff}]` — guard: only where `$1 < cutoff`
- `[true]` — result: return `true` (for `select_delete`, this means "delete this row")

The `:"$1"` syntax is an atom that acts as a numbered variable in the match spec language.

### `config_env()` vs `Mix.env()`

| | `config_env()` | `Mix.env()` |
|---|---|---|
| **Where** | Config files only | Anywhere |
| **When** | Compile time | Compile time |
| **In releases** | Works (baked into config) | Crashes |
| **Use for** | Config branching | mix.exs only |

### ETS `:bag` Type

ETS has four types: `:set`, `:ordered_set`, `:bag`, and `:duplicate_bag`. We use `:bag` because:
- Multiple entries per key (one IP can have many timestamps)
- `:ets.select_count/2` efficiently counts within a range
- `:ets.select_delete/2` efficiently removes expired entries

### Match Specs

Match specs are Erlang's way of filtering ETS entries without scanning every row:

```elixir
# "For entries matching {ip, timestamp} where timestamp >= cutoff, count them"
[{{ip, :"$1"}, [{:>=, :"$1", cutoff}], [true]}]
```

The `:"$1"` is a match variable. The middle list is guards. The last list is the return value (`true` means "match" for count/delete operations).

### `System.monotonic_time/1`

We use monotonic time for internal tracking because it's not affected by clock adjustments (NTP, DST, manual changes). But we use `System.os_time/1` for the `x-ratelimit-reset` header because clients need wall-clock time.

## Verification

```bash
# 1. Compile
mix compile

# 2. Tests pass
MIX_ENV=test mix test

# 3. Dev mode — rate limit headers present
iex -S mix
# Then:
curl -I http://localhost:4000/api/status
# → x-ratelimit-limit: 100
# → x-ratelimit-remaining: 99

# 4. Build a release
MIX_ENV=prod mix release
# → _build/prod/rel/ignite/

# 5. Run release migration
DATABASE_PATH=./ignite_release.db \
SECRET_KEY_BASE=$(openssl rand -base64 64) \
  _build/prod/rel/ignite/bin/ignite eval "Ignite.Release.migrate()"

# 6. Start the release
DATABASE_PATH=./ignite_release.db \
SECRET_KEY_BASE=$(openssl rand -base64 64) \
PORT=4000 \
  _build/prod/rel/ignite/bin/ignite start
```

## Files Changed

| File | Change |
|---|---|
| `config/config.exs` | Added `env: config_env()` and `rate_limit` config |
| `config/prod.exs` | Updated DB config comment |
| `config/runtime.exs` | **New** — runtime env var config for releases |
| `lib/ignite/session.ex` | Configurable secret key (reads from config) |
| `lib/ignite/debug_page.ex` | Fixed `Mix.env()` → `Application.get_env(:ignite, :env)` |
| `lib/ignite/controller.ex` | Added 429 status text |
| `lib/ignite/rate_limiter.ex` | **New** — ETS sliding window rate limiter |
| `lib/ignite/adapters/cowboy.ex` | Extract peer IP via `:cowboy_req.peer/1` |
| `lib/ignite/application.ex` | Fixed `Mix.env()`, added RateLimiter to supervision tree |
| `lib/my_app/router.ex` | Added `plug :rate_limit` as first middleware |
| `mix.exs` | Added release configuration |
| `lib/ignite/release.ex` | **New** — release migration tasks |

## File Checklist

- **New** `config/runtime.exs` — Runtime env var config for releases
- **New** `lib/ignite/rate_limiter.ex` — ETS sliding window rate limiter with GenServer cleanup
- **New** `lib/ignite/release.ex` — Release migration tasks
- **Modified** `config/config.exs` — Added `env: config_env()` and `rate_limit` config
- **Modified** `config/prod.exs` — Updated DB config comment
- **Modified** `lib/ignite/adapters/cowboy.ex` — Extract peer IP via `:cowboy_req.peer/1`
- **Modified** `lib/ignite/application.ex` — Fixed `Mix.env()`, added RateLimiter to supervision tree
- **Modified** `lib/ignite/controller.ex` — Added 429 status text
- **Modified** `lib/ignite/debug_page.ex` — Fixed `Mix.env()` to use config-based environment check
- **Modified** `lib/ignite/session.ex` — Configurable secret key (reads from config)
- **Modified** `lib/my_app/router.ex` — Added `plug :rate_limit` as first middleware
- **Modified** `mix.exs` — Added release configuration

---

[← Previous: Step 39 - SSL/TLS Support](39-ssl-tls.md) | [Next: Step 41 - Stream Upsert & Limit →](41-stream-upsert-limit.md)

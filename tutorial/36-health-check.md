# Step 36: Health Check Endpoint

## What We're Building

A dedicated `GET /health` endpoint that returns JSON with system metrics — uptime, memory usage, process count, scheduler info, and version numbers. Load balancers, monitoring tools, and deployment scripts can hit this endpoint to verify the application is alive and healthy.

```json
{
  "status": "ok",
  "uptime_seconds": 3612,
  "uptime_human": "1h 0m 12s",
  "memory": {
    "total_mb": 48.2,
    "processes_mb": 12.7
  },
  "processes": 287,
  "atoms": 15423,
  "ports": 12,
  "schedulers": 8,
  "otp_release": "27",
  "elixir_version": "1.18.3",
  "timestamp": "2026-03-04T14:23:01.456789Z"
}
```

## The Problem

Before this step, the only API endpoint was `/api/status`, which returns minimal info (framework name, Elixir version, uptime). Production deployments need a richer health check that tells you:

- Is the app running? (`status: "ok"`)
- How long has it been up? (Uptime — detects crash loops)
- Is it leaking memory? (Memory stats over time)
- Is it overloaded? (Process count, scheduler utilization)
- What version is deployed? (OTP + Elixir versions)

## How Phoenix Does It

Phoenix doesn't include a built-in health check. Most Phoenix apps add one manually in their router, typically returning JSON with application-specific checks (database connectivity, cache availability, etc.).

Libraries like `plug_checkup` provide a structured approach, but the BEAM already exposes everything we need via `:erlang` functions.

## Implementation

### 1. Adding the Route

**Update `lib/my_app/router.ex`** — add the health check route:

```elixir
# lib/my_app/router.ex
get "/health", to: MyApp.ApiController, action: :health
```

The health check is a top-level route, not scoped under `/api`. This is intentional — load balancers typically expect health checks at a well-known path like `/health` or `/healthz`, not behind API prefixes.

### 2. The Health Action

**Update `lib/my_app/controllers/api_controller.ex`** — add the `health/1` action and `format_uptime/1` helper:

```elixir
# lib/my_app/controllers/api_controller.ex
def health(conn) do
  memory = :erlang.memory()
  {uptime_ms, _} = :erlang.statistics(:wall_clock)
  uptime_s = div(uptime_ms, 1000)

  json(conn, %{
    status: "ok",
    uptime_seconds: uptime_s,
    uptime_human: format_uptime(uptime_s),
    memory: %{
      total_mb: Float.round(memory[:total] / 1_048_576, 1),
      processes_mb: Float.round(memory[:processes] / 1_048_576, 1)
    },
    processes: :erlang.system_info(:process_count),
    atoms: :erlang.system_info(:atom_count),
    ports: :erlang.system_info(:port_count),
    schedulers: :erlang.system_info(:schedulers_online),
    otp_release: :erlang.system_info(:otp_release) |> List.to_string(),
    elixir_version: System.version(),
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
  })
end
```

### 3. BEAM Runtime Functions

**`:erlang.memory/0`** — Returns a keyword list of memory usage broken down by category:
- `:total` — total bytes allocated by the VM
- `:processes` — bytes used by all Erlang/Elixir processes (heaps, stacks, mailboxes)
- `:atom` — bytes used by the atom table
- `:binary` — bytes used by reference-counted binaries
- `:ets` — bytes used by ETS tables

We report `total` and `processes` in megabytes. Watching `total_mb` over time reveals memory leaks.

**`:erlang.statistics(:wall_clock)`** — Returns `{total_ms, since_last_call_ms}`. The first element is milliseconds since the VM started. We convert to seconds for readability.

**`:erlang.system_info/1`** — Queries the VM runtime:
- `:process_count` — current number of live processes. A steady increase indicates a process leak.
- `:atom_count` — number of atoms in the atom table. Atoms are never garbage collected, so unbounded growth (e.g., from `String.to_atom/1` on user input) eventually crashes the VM.
- `:port_count` — open ports (file handles, sockets, etc.).
- `:schedulers_online` — number of OS threads available for running Erlang processes. Usually matches CPU cores.
- `:otp_release` — the OTP version string (e.g., `"27"`).

### 4. Human-Readable Uptime

```elixir
defp format_uptime(seconds) do
  days = div(seconds, 86_400)
  hours = div(rem(seconds, 86_400), 3600)
  mins = div(rem(seconds, 3600), 60)
  secs = rem(seconds, 60)

  cond do
    days > 0 -> "#{days}d #{hours}h #{mins}m"
    hours > 0 -> "#{hours}h #{mins}m #{secs}s"
    mins > 0 -> "#{mins}m #{secs}s"
    true -> "#{secs}s"
  end
end
```

Shows the most relevant time units. After a day of uptime, seconds are noise — we show `1d 2h 30m` instead of `95400s`.

## How Load Balancers Use This

### AWS ALB / ELB
```
Target Group → Health Check Settings:
  Path: /health
  Protocol: HTTP
  Port: 4000
  Healthy threshold: 3
  Unhealthy threshold: 2
  Interval: 30s
  Timeout: 5s
```

The load balancer hits `/health` every 30 seconds. If it gets a `200 OK` response, the instance is healthy. If it fails twice in a row, traffic is routed away.

### Docker / Kubernetes
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1
```

```yaml
# Kubernetes liveness probe
livenessProbe:
  httpGet:
    path: /health
    port: 4000
  periodSeconds: 30
  failureThreshold: 3
```

### Monitoring (Datadog, Prometheus, etc.)
Monitoring systems can poll `/health` and graph `memory.total_mb`, `processes`, and `uptime_seconds` over time. Sudden drops in uptime indicate crashes. Steady memory growth indicates leaks.

## Testing

```bash
mix compile
iex -S mix

# 1. Basic health check
curl -s http://localhost:4000/health | jq .
# {
#   "status": "ok",
#   "uptime_seconds": 5,
#   "uptime_human": "5s",
#   "memory": {
#     "total_mb": 48.2,
#     "processes_mb": 12.7
#   },
#   "processes": 287,
#   "atoms": 15423,
#   "ports": 12,
#   "schedulers": 8,
#   "otp_release": "27",
#   "elixir_version": "1.18.3",
#   "timestamp": "2026-03-04T14:23:01.456789Z"
# }

# 2. Verify it appears in route list
mix ignite.routes | grep health
# GET     /health          MyApp.ApiController  :health

# 3. Check response headers include x-request-id (from Step 35)
curl -v http://localhost:4000/health 2>&1 | grep x-request-id
# x-request-id: F3kQ7x_Nz2mYwA

# 4. Load balancer simulation (should always return 200)
for i in $(seq 1 5); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/health; done
# 200
# 200
# 200
# 200
# 200
```

## Key Concepts

- **`:erlang.memory/0`** — Returns VM memory allocation by category. Total memory minus process memory gives you overhead (atoms, ETS, binaries, system).
- **`:erlang.statistics(:wall_clock)`** — Wall-clock time since VM boot. Useful for detecting crash-loop restarts (uptime resets to 0).
- **`:erlang.system_info/1`** — Queries the BEAM runtime for process counts, scheduler info, atom table size, and version numbers. All zero-cost reads from the VM's internal counters.
- **Health check placement** — At a top-level path (`/health`), not behind API prefixes or authentication middleware, so load balancers can always reach it.
- **Human-readable formatting** — `format_uptime/1` shows the most meaningful time units, adapting from seconds to days as uptime grows.
- **`div/2` and `rem/2`** — Integer division and remainder (modulo). Unlike `/` which returns a float (`10 / 3 #=> 3.333...`), `div` returns an integer. We use these for converting bytes to MB or formatting uptime:
  ```elixir
  div(10, 3)  #=> 3  (integer division, no decimal)
  rem(10, 3)  #=> 1  (remainder/modulo)
  ```
- **`List.to_string/1`** — Converts a charlist to an Elixir string. Erlang system functions like `:erlang.system_info(:otp_release)` return charlists, so we need this conversion before using Elixir string functions:
  ```elixir
  List.to_string(~c"24")  #=> "24"
  ```

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Built-in health check | `GET /health` with system metrics | Not included — added manually |
| Metrics source | `:erlang.memory/0`, `:erlang.system_info/1` | Same BEAM functions |
| Response format | JSON | Varies by implementation |
| Memory reporting | Total MB + process MB | N/A (manual) |
| Uptime | `:erlang.statistics(:wall_clock)` | Same |
| Database check | Not included | Common to add `Repo.query!("SELECT 1")` |

A production health check might also verify database connectivity (`Repo.query!("SELECT 1")`), cache availability, and external service reachability. Our version focuses on BEAM runtime health, which is sufficient for most deployments.

## Files Changed

| File | Change |
|------|--------|
| `lib/my_app/router.ex` | Added `get "/health"` route |
| `lib/my_app/controllers/api_controller.ex` | Added `health/1` action with system metrics, `format_uptime/1` helper |

## File Checklist

- **Modified** `lib/my_app/controllers/api_controller.ex` — Added `health/1` action and `format_uptime/1` helper
- **Modified** `lib/my_app/router.ex` — Added `get "/health"` route

---

[← Previous: Step 35 - Logger Metadata (Request ID + Timing)](35-logger-metadata.md) | [Next: Step 37 - Static Asset Pipeline →](37-static-asset-pipeline.md)

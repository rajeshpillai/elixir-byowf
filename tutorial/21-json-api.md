# Step 21: JSON Response Helper

## What We're Building

A `json/3` helper for controllers that encodes Elixir maps/lists into JSON responses, plus automatic JSON body parsing for incoming `application/json` requests. This lets Ignite serve as a JSON API backend.

## The Problem

Our controllers can return plain text (`text/3`) and HTML (`html/3`), but modern apps need JSON APIs. Right now, if you wanted to return JSON, you'd have to manually encode and set headers:

```elixir
def status(conn) do
  body = Jason.encode!(%{status: "ok"})
  %Ignite.Conn{conn | resp_body: body, resp_headers: Map.put(conn.resp_headers, "content-type", "application/json"), halted: true}
end
```

That's verbose and error-prone. We want `json(conn, %{status: "ok"})`.

Similarly, when clients POST JSON bodies, our adapter stores the raw string as `%{"_body" => "..."}` instead of parsing it into a usable map.

## The Solution

### 1. `json/3` Controller Helper

**Update `lib/ignite/controller.ex`** — add the `json/3` function:

```elixir
def json(conn, data, status \\ 200) do
  %Ignite.Conn{
    conn
    | status: status,
      resp_body: Jason.encode!(data),
      resp_headers: Map.put(conn.resp_headers, "content-type", "application/json"),
      halted: true
  }
end
```

**Key concepts:**
- `Jason.encode!/1` converts any Elixir term (maps, lists, strings, numbers) into a JSON string
- The `!` suffix means it raises on failure (bad input) — fail fast
- We set `content-type: application/json` so browsers and API clients know the format

### 2. JSON Body Parsing

**Update `lib/ignite/adapters/cowboy.ex`** — add a new `parse_body/2` clause for JSON content type:

```elixir
defp parse_body(body, "application/json" <> _) when byte_size(body) > 0 do
  case Jason.decode(body) do
    {:ok, parsed} when is_map(parsed) -> parsed
    {:ok, parsed} -> %{"_json" => parsed}
    {:error, _} -> %{"_body" => body}
  end
end
```

**Why three cases?**
- **Map**: Most common — `{"name": "Jose"}` becomes `%{"name" => "Jose"}` and merges naturally into `conn.params`
- **Non-map** (arrays, scalars): Stored under `"_json"` key since params must be a map
- **Parse error**: Falls back to raw body under `"_body"` — graceful degradation

The `<> _` in the pattern match handles content types with extra parameters like `application/json; charset=utf-8`.

## Using It

### API Controller

**Create `lib/my_app/controllers/api_controller.ex`:**

```elixir
defmodule MyApp.ApiController do
  import Ignite.Controller

  def status(conn) do
    json(conn, %{
      status: "ok",
      framework: "Ignite",
      elixir_version: System.version()
    })
  end

  def echo(conn) do
    json(conn, %{echo: conn.params})
  end
end
```

### Router

**Update `lib/my_app/router.ex`** — add the API routes:

```elixir
get "/api/status", to: MyApp.ApiController, action: :status
post "/api/echo", to: MyApp.ApiController, action: :echo
```

### Welcome Controller Link

**Update `lib/my_app/controllers/welcome_controller.ex`** — add an API section to the index page so visitors can discover and test the JSON endpoints:

```elixir
    <h2>API Routes</h2>
    <ul>
      <li><a href="/api/status">/api/status</a> — JSON response</li>
    </ul>
```

This is just a convenience link on the homepage — the real work is in `ApiController` and the router.

## Testing

```bash
# JSON response
curl http://localhost:4000/api/status
# → {"elixir_version":"1.17.0","framework":"Ignite","status":"ok","uptime_seconds":42}

# JSON body parsing
curl -X POST -H "Content-Type: application/json" \
     -d '{"name":"Jose","lang":"Elixir"}' \
     http://localhost:4000/api/echo
# → {"echo":{"lang":"Elixir","name":"Jose"},"received_at":"2024-01-15T10:30:00Z"}
```

## How It Fits Together

```
Client sends:  POST /api/echo  Content-Type: application/json  {"name":"Jose"}
                    ↓
Cowboy adapter:  parse_body detects "application/json", calls Jason.decode
                    ↓
conn.params:     %{"name" => "Jose"}
                    ↓
Controller:      json(conn, %{echo: conn.params})
                    ↓
Jason.encode!:   '{"echo":{"name":"Jose"}}'
                    ↓
Response:        200 OK  Content-Type: application/json
```

## Key Elixir Concepts

- **Pattern matching on strings**: `"application/json" <> _` matches any string starting with `"application/json"`, ignoring trailing characters like `; charset=utf-8`
- **Guard clauses**: `when byte_size(body) > 0` prevents parsing empty bodies
- **`Jason.decode` vs `Jason.decode!`**: The non-bang version returns `{:ok, result}` or `{:error, reason}` — perfect for graceful error handling. The bang version raises on error — good for encoding where we control the input.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/controller.ex` | **Modified** — added `json/3` response helper |
| `lib/ignite/adapters/cowboy.ex` | **Modified** — added JSON body parsing in `parse_body/2` |
| `lib/my_app/controllers/api_controller.ex` | **New** |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — added link to API status page |
| `lib/my_app/router.ex` | **Modified** — added `/api/status` and `/api/echo` routes |

---

[← Previous: Step 20 - JS Hooks — Client-Side JavaScript Interop](20-js-hooks.md) | [Next: Step 22 - PUT/PATCH/DELETE HTTP Methods →](22-http-methods.md)

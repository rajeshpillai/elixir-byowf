# Step 38: Test Helpers (ConnTest)

## What We're Building

A `Ignite.ConnTest` module that lets you test controllers, routes, and middleware without starting the HTTP server:

```elixir
defmodule MyApp.WelcomeControllerTest do
  use ExUnit.Case
  import Ignite.ConnTest

  @router MyApp.Router

  test "GET / returns 200 with home page" do
    conn = get(@router, "/")
    body = html_response(conn, 200)
    assert body =~ "Ignite Framework"
  end
end
```

Tests call `Router.call(conn)` directly, running the full plug pipeline and route dispatch — no Cowboy, no TCP, no network overhead.

## Concepts You'll Use

### ExUnit Basics (`use ExUnit.Case`, `test`, `assert`)

```elixir
defmodule MyTest do
  use ExUnit.Case  # Sets up the test module with test/assert macros

  test "addition works" do
    assert 1 + 1 == 2       # Passes if the expression is truthy
    assert "hello" =~ "ell" # =~ checks if left contains right
  end
end
```

ExUnit is Elixir's built-in test framework. `use ExUnit.Case` injects the `test` macro for defining test cases and the `assert` macro for checking expectations. The `=~` operator returns `true` if the left string contains the right string (or matches a regex).

### `config_env/0`

```elixir
# In config/config.exs
if config_env() == :test do
  config :ignite, :port, 4002
end
```

Returns the current Mix environment as an atom (`:dev`, `:test`, or `:prod`). Set via `MIX_ENV=test mix test`. Used in config files to load environment-specific settings.

### `import_config/1`

```elixir
import_config "#{config_env()}.exs"
```

Loads another config file and merges its settings. Typically used at the end of `config.exs` to import `dev.exs`, `test.exs`, or `prod.exs` based on the environment.

## The Problem

Before this step:
- No test utilities existed — `test/ignite_test.exs` was an empty module
- Testing a controller required starting the server and making real HTTP requests
- No way to set up sessions or CSRF tokens for form submission tests
- No response assertion helpers (status, content-type, JSON decoding)

## How Phoenix Does It

Phoenix provides `Phoenix.ConnTest` with helpers like:
- `get(conn, "/")` — dispatch through the endpoint
- `html_response(conn, 200)` — assert status + content-type, return body
- `json_response(conn, 200)` — assert + decode JSON
- `redirected_to(conn)` — extract redirect location
- `init_test_session(conn, %{})` — set session data for testing

## Design Decisions

### Tests Live in `lib/`, Not `test/`

`Ignite.ConnTest` is in `lib/ignite/conn_test.ex` because it ships with the framework — any application using Ignite gets these helpers automatically. Tests `import Ignite.ConnTest` to use them.

### `raise` Instead of `assert`

Since the module is in `lib/` (not a test file), we can't use `ExUnit.Assertions.assert`. Instead, helpers like `text_response/2` raise on failure with descriptive error messages. ExUnit catches these raises and reports them as test failures.

### Direct Router Dispatch

```
Test → build_conn → Router.call(conn) → plugs → dispatch → controller → conn
```

No Cowboy, no TCP socket, no HTTP parsing. The conn flows through the exact same code path as a real request — middleware, CSRF checks, and all.

### CSRF in Tests

Form submissions need CSRF tokens. Two helpers work together:

1. `init_test_session/2` — generates a CSRF token and stores it in `conn.session`
2. `with_csrf/1` — reads the session token, masks it, and adds to `conn.params`

```elixir
conn =
  build_conn(:post, "/users", %{"username" => "jose"})
  |> init_test_session()    # session["_csrf_token"] = "random_token"
  |> with_csrf()            # params["_csrf_token"] = masked(random_token)
  |> dispatch(MyApp.Router) # CSRF plug validates → passes ✓
```

JSON API tests skip CSRF by setting the content-type header:

```elixir
conn =
  build_conn(:post, "/api/echo", %{"msg" => "hi"})
  |> put_content_type("application/json")  # CSRF exempt
  |> dispatch(MyApp.Router)
```

### Configurable Port for Tests

The application now reads the port from config.

**Update `lib/ignite/application.ex`** — read port from config instead of hardcoding 4000:

```elixir
# lib/ignite/application.ex
port = Application.get_env(:ignite, :port, 4000)
```

```elixir
# config/test.exs
config :ignite, port: 4002
```

This prevents `mix test` from failing when a dev server is running on port 4000.

## Bug Fix: Plug Execution Order

While building tests, we discovered that **plugs were not running**. The `call/1` function was defined inside `__using__/1`, which expands *before* the `plug` macro calls accumulate into `@plugs`. At definition time, `@plugs` was `[]`.

**Before (broken):**
```elixir
defmacro __using__(_opts) do
  quote do
    # @plugs is [] here — no plugs registered yet!
    def call(conn) do
      Enum.reduce(@plugs, conn, fn ...)  # @plugs = [] at compile time
    end
  end
end
```

**After (fixed):**

**Update `lib/ignite/router.ex`** — move `call/1` to `@before_compile` so plugs execute correctly:

```elixir
defmacro __before_compile__(env) do
  plugs = Module.get_attribute(env.module, :plugs) |> Enum.reverse()

  quote do
    # @plugs is fully accumulated — all plugs registered
    def call(conn) do
      Enum.reduce(unquote(plugs), conn, fn ...)
    end
  end
end
```

The fix moves `call/1` to `@before_compile`, which runs after all module-level code has been processed. This is the same pattern Phoenix uses — `Phoenix.Router` defines its pipeline dispatch in `@before_compile`.

This means the `x-powered-by` header, CSP headers, and CSRF validation are now properly enforced on every request.

## Implementation

### 1. The ConnTest Module

**Create `lib/ignite/conn_test.ex`:**

```elixir
# lib/ignite/conn_test.ex
defmodule Ignite.ConnTest do
  def build_conn(method, path, params \\ %{}) do
    %Ignite.Conn{
      method: method |> to_string() |> String.upcase(),
      path: path,
      params: params
    }
  end

  def dispatch(conn, router), do: router.call(conn)

  def get(router, path, params \\ %{}) do
    build_conn(:get, path, params) |> dispatch(router)
  end

  # post/3, put/3, patch/3, delete/3 follow the same pattern
end
```

### 2. Response Assertions

```elixir
def text_response(conn, status) do
  assert_status!(conn, status)
  assert_content_type!(conn, "text/plain")
  conn.resp_body
end

def html_response(conn, status) do
  assert_status!(conn, status)
  assert_content_type!(conn, "text/html")
  conn.resp_body
end

def json_response(conn, status) do
  assert_status!(conn, status)
  assert_content_type!(conn, "application/json")
  Jason.decode!(conn.resp_body)
end

def redirected_to(conn) do
  Map.get(conn.resp_headers, "location") ||
    raise "No location header"
end
```

### 3. Session and CSRF Helpers

```elixir
def init_test_session(conn, extra \\ %{}) do
  csrf_token = Ignite.CSRF.generate_token()
  session = Map.merge(%{"_csrf_token" => csrf_token}, extra)
  %Ignite.Conn{conn | session: session}
end

def with_csrf(conn) do
  token = conn.session["_csrf_token"]
  masked = Ignite.CSRF.mask_token(token)
  %Ignite.Conn{conn | params: Map.put(conn.params, "_csrf_token", masked)}
end

def put_content_type(conn, content_type) do
  %Ignite.Conn{conn | headers: Map.put(conn.headers, "content-type", content_type)}
end
```

### 4. Test Configuration

**Update `config/config.exs`** — add `:port` config and env-specific config import:

```elixir
# config/config.exs — now imports env-specific config
config :ignite, port: 4000

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
```

**Create `config/test.exs`:**

```elixir
# config/test.exs
config :ignite, port: 4002
config :ignite, MyApp.Repo, database: "ignite_test.db"
config :logger, level: :warning
```

**Update `test/test_helper.exs`** — run migrations automatically before tests:

```elixir
# test/test_helper.exs
ExUnit.start()
Ecto.Migrator.run(MyApp.Repo, :up, all: true, log: false)
```

## Testing

```bash
# Run all tests
MIX_ENV=test mix test

# Expected output:
# Running ExUnit with seed: 422702, max_cases: 8
# .....................
# Finished in 0.2 seconds
# 21 tests, 0 failures

# Run a specific test file
MIX_ENV=test mix test test/controllers/welcome_controller_test.exs

# Run with verbose output
MIX_ENV=test mix test --trace
```

## Test Coverage

| Test File | Tests | What's Covered |
|-----------|-------|----------------|
| `test/ignite_test.exs` | 7 | `build_conn`, `init_test_session`, `with_csrf`, `put_content_type`, `put_req_header` |
| `test/controllers/welcome_controller_test.exs` | 5 | GET /, GET /hello, 404 handling, response headers (x-powered-by, CSP) |
| `test/controllers/api_controller_test.exs` | 3 | GET /api/status, POST /api/echo (JSON), GET /health |
| `test/controllers/user_controller_test.exs` | 4 | GET /users (JSON), POST with CSRF, POST without CSRF (403), validation errors |
| **Total** | **21** | |

## Key Concepts

- **Direct dispatch testing** — Call `Router.call(conn)` without HTTP, exercising the exact same code path as production. No mocking, no stubs — real middleware, real CSRF checks.
- **`@before_compile`** — Elixir's mechanism for running code after all module-level definitions are processed. Module attributes read here see their final accumulated values.
- **Module attribute timing** — `@attr` in a function body captures the value at compile time when that `def` is processed. If the `def` is expanded by `use` at the top of the module, the attribute may be empty.
- **Test isolation via config** — Separate port and database for tests prevents conflicts with a running dev server. `config/test.exs` overrides defaults from `config/config.exs`.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Test helper | `Ignite.ConnTest` | `Phoenix.ConnTest` |
| Dispatch | `Router.call(conn)` | `Endpoint.call(conn)` |
| Session setup | `init_test_session/2` | `init_test_session/2` |
| CSRF in tests | `with_csrf/1` | `get_csrf_token/0` + form helper |
| Response helpers | `text_response/2`, `html_response/2`, `json_response/2` | Same names |
| Redirect | `redirected_to/1` | `redirected_to/2` |
| Test database | SQLite file per env | Postgres with Sandbox |

Phoenix uses `Ecto.Adapters.SQL.Sandbox` for test isolation (each test runs in a rolled-back transaction). Ignite uses a separate SQLite file and unique test data. For medium-scale apps, this is sufficient.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/conn_test.ex` | **New** — Test helper module with all dispatch/assertion functions |
| `lib/ignite/router.ex` | **Fixed** — Moved `call/1` to `@before_compile` so plugs actually execute |
| `lib/ignite/application.ex` | Read port from config instead of hardcoding 4000 |
| `config/config.exs` | Added `:port` config, env-specific config import |
| `config/test.exs` | **New** — Test env config (port 4002, test DB, reduced logging) |
| `test/test_helper.exs` | Run migrations automatically before tests |
| `test/ignite_test.exs` | Replaced empty module with ConnTest helper tests |
| `test/controllers/welcome_controller_test.exs` | **New** — Welcome controller tests |
| `test/controllers/api_controller_test.exs` | **New** — API controller tests |
| `test/controllers/user_controller_test.exs` | **New** — User controller tests with CSRF |

## File Checklist

- **New** `lib/ignite/conn_test.ex` — Test helper module with dispatch and assertion functions
- **New** `config/test.exs` — Test environment config (port 4002, test DB, reduced logging)
- **New** `test/controllers/welcome_controller_test.exs` — Welcome controller tests
- **New** `test/controllers/api_controller_test.exs` — API controller tests
- **New** `test/controllers/user_controller_test.exs` — User controller tests with CSRF
- **Modified** `lib/ignite/router.ex` — Moved `call/1` to `@before_compile` so plugs execute
- **Modified** `lib/ignite/application.ex` — Read port from config instead of hardcoding 4000
- **Modified** `config/config.exs` — Added `:port` config and env-specific config import
- **Modified** `test/test_helper.exs` — Run migrations automatically before tests
- **Modified** `test/ignite_test.exs` — Replaced empty module with ConnTest helper tests

---

[← Previous: Step 37 - Static Asset Pipeline](37-static-asset-pipeline.md) | [Next: Step 39 - SSL/TLS Support →](39-ssl-tls.md)

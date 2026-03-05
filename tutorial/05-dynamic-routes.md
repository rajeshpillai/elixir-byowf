# Step 5: Dynamic Route Matching

## What We're Building

Real apps need URLs like `/users/42` or `/posts/my-first-blog`. The `42`
and `my-first-blog` parts are **dynamic** — they change per request.

We're upgrading the router so you can write:

```elixir
get "/users/:id", to: UserController, action: :show
```

And access the captured value in the controller:

```elixir
def show(conn) do
  conn.params[:id]  #=> "42"
end
```

## Concepts You'll Learn

### List Pattern Matching

Elixir can pattern match on lists:

```elixir
["users", id] = String.split("/users/42", "/", trim: true)
id  #=> "42"
```

This is how we match dynamic segments. The route `/users/:id` becomes
the pattern `["users", id]` where `id` is a variable that captures
whatever the user typed.

### Binary Pattern Matching with `<>`

The `<>` operator can pattern match on the start of a string:

```elixir
":" <> name = ":id"
name  #=> "id"

":" <> name = "users"
# ** (MatchError) — doesn't start with ":"
```

This is how the router detects dynamic segments: if a path segment
starts with `":"`, it's dynamic; otherwise it's a literal match.

### Macro.var/2

Inside macros, you can't just write a variable name — you need to create
a variable AST node:

```elixir
Macro.var(:id, nil)   # Creates the variable `id` in the macro's AST
```

This tells the compiler "create a variable called `:id` that will capture
a value during pattern matching."

### Enum.unzip/1

Splits a list of two-element tuples into two separate lists:

```elixir
Enum.unzip([{"users", nil}, {id_var, :id}])
#=> {["users", id_var], [nil, :id]}
```

We use this to separate the match patterns from the param names after
processing each segment.

### Map.merge/2

Combines two maps. If both have the same key, the second map wins:

```elixir
Map.merge(%{a: 1}, %{b: 2})       #=> %{a: 1, b: 2}
Map.merge(%{a: 1}, %{a: 99})      #=> %{a: 99}
```

We use this to merge captured URL params into `conn.params`.

### How the Macro Generates Code

When you write:
```elixir
get "/users/:id", to: UserController, action: :show
```

The macro generates this function clause:

```elixir
defp dispatch(%Ignite.Conn{method: "GET"} = conn, ["users", id]) do
  params = %{id: id}
  conn = %Ignite.Conn{conn | params: Map.merge(conn.params, params)}
  apply(UserController, :show, [conn])
end
```

The `["users", id]` pattern matches any two-segment path starting with
"users". The second segment is captured into `id`.

## The Code

### Updated Router (`lib/ignite/router.ex`)

**Update `lib/ignite/router.ex`** — add the `build_route/4`, `build_match_pattern/1`, and `build_params_map/1` private functions, update `__using__/1` so `call/1` splits the path into segments, change `dispatch` to accept two arguments, and update `finalize_routes/0` accordingly. Key changes:

1. **`call/1` splits the path** into segments before dispatching:
   ```elixir
   segments = String.split(conn.path, "/", trim: true)
   dispatch(conn, segments)
   ```

2. **`dispatch` now takes two args**: the conn and the segments list

3. **`build_route/4`** is shared by `get` and `post` macros:
   - Splits the route path into segments
   - Identifies dynamic segments (starting with `:`)
   - Generates a pattern that captures dynamic parts as variables
   - Builds a params map from the captured variables

4. **`build_match_pattern/1`** converts path segments using `":" <> name`
   pattern matching to detect dynamic parts:
   - `"users"` → literal string `"users"` (must match exactly)
   - `":id"` → `Macro.var(:id, nil)` (matches anything, captures value)
   - Returns both the pattern list and the param names via `Enum.unzip/1`

5. **`build_params_map/1`** generates `%{id: id}` code at compile time
   using a raw AST tuple `{:%{}, [], pairs}` — this is how macros build
   map literals programmatically

6. **`finalize_routes/0`** also changes — the catch-all is now
   `dispatch(conn, _segments)` (two args) instead of `dispatch(conn)`

### New UserController

**Create `lib/my_app/controllers/user_controller.ex`:**

```elixir
def show(conn) do
  user_id = conn.params[:id]
  text(conn, "Showing profile for User ##{user_id}")
end
```

### Updated Router (`lib/my_app/router.ex`)

**Update `lib/my_app/router.ex`** — add the following route:

```elixir
get "/users/:id", to: MyApp.UserController, action: :show
```

## How It Works

```
Request: GET /users/42

1. call(conn)
   segments = ["users", "42"]

2. dispatch(conn, ["users", "42"])
   Tries each clause:
   - dispatch(conn, [])             → no match (/ has 0 segments)
   - dispatch(conn, ["hello"])      → no match (1 segment, wrong)
   - dispatch(conn, ["users", id])  → MATCH! id = "42"

3. params = %{id: "42"}
   conn = %{conn | params: %{id: "42"}}

4. UserController.show(conn)
   → text(conn, "Showing profile for User #42")
```

## Try It Out

1. Start the server:

```bash
iex -S mix
iex> Ignite.Server.start()
```

2. Visit http://localhost:4000/users/42 → "Showing profile for User #42"

3. Visit http://localhost:4000/users/elixir-fan → "Showing profile for User #elixir-fan"

4. Visit http://localhost:4000/users → "404 — Not Found" (no `:id` segment)

5. The static routes still work:
   - http://localhost:4000/ → "Welcome to Ignite!"
   - http://localhost:4000/hello → "Hello from the Controller!"

## File Checklist

After this step, your project should have these files:

| File | Status | Purpose |
|------|--------|---------|
| `lib/ignite/router.ex` | **Modified** | Now supports dynamic segments (`:id`) with `build_route/4` |
| `lib/my_app/controllers/user_controller.ex` | **New** | Handles `/users/:id` with params |
| `lib/my_app/router.ex` | **Modified** | Added `/users/:id` route |
| `lib/ignite/conn.ex` | Unchanged | Conn struct (from Step 2) |
| `lib/ignite/parser.ex` | Unchanged | HTTP parser (from Step 2) |
| `lib/ignite/server.ex` | Unchanged | TCP server (from Step 4) |
| `lib/ignite/controller.ex` | Unchanged | Response helpers (from Step 4) |
| `lib/my_app/controllers/welcome_controller.ex` | Unchanged | Welcome controller (from Step 4) |

## What's Next

Our server works, but it has a fatal flaw: if **anything** crashes (a bad
request, a controller error), the entire server dies.

In **Step 6**, we'll wrap the server in an **OTP Supervisor**. This gives
us "self-healing" — when a request handler crashes, the supervisor restarts
the server automatically. This is the secret sauce behind Erlang's famous
"nine nines" (99.9999999%) uptime.

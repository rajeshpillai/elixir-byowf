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

### String.split with `trim: true`

`String.split/3` breaks a string into a list. The `trim: true` option
removes empty strings caused by leading/trailing delimiters:

```elixir
String.split("/users/42", "/")                #=> ["", "users", "42"]
String.split("/users/42", "/", trim: true)    #=> ["users", "42"]
```

Without `trim`, the leading `/` produces an empty string `""` at the
start — we don't want that.

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

**Update `lib/ignite/router.ex`** — we need to add three private functions and update the existing macros.

**1. Update `__using__/1`** — `call/1` now splits the path into segments before dispatching:

```elixir
def call(conn) do
  segments = String.split(conn.path, "/", trim: true)
  dispatch(conn, segments)
end
```

**2. Update the `get` macro** to use a shared `build_route/4` function:

```elixir
defmacro get(path, to: controller, action: action) do
  build_route("GET", path, controller, action)
end
```

**3. Add `build_route/4`** — the shared logic that all route macros use:

```elixir
defp build_route(method, path, controller, action) do
  segments = String.split(path, "/", trim: true)
  {match_pattern, param_names} = build_match_pattern(segments)

  quote do
    defp dispatch(
           %Ignite.Conn{method: unquote(method)} = conn,
           unquote(match_pattern)
         ) do
      params = unquote(build_params_map(param_names))
      conn = %Ignite.Conn{conn | params: Map.merge(conn.params, params)}
      apply(unquote(controller), unquote(action), [conn])
    end
  end
end
```

**4. Add `build_match_pattern/1`** — converts path segments into a pattern list:

```elixir
defp build_match_pattern(segments) do
  {patterns, names} =
    Enum.map(segments, fn
      ":" <> name ->
        # Dynamic segment: create a variable that captures the value
        var_name = String.to_atom(name)
        {Macro.var(var_name, nil), var_name}

      static ->
        # Static segment: must match this exact string
        {static, nil}
    end)
    |> Enum.unzip()

  {patterns, Enum.reject(names, &is_nil/1)}
end
```

For `"/users/:id"`, this produces:
- `patterns` = `["users", {:id, [], nil}]` — a list with a literal and a variable
- `param_names` = `[:id]` — which segments to capture into params

**5. Add `build_params_map/1`** — generates a map expression in the AST:

```elixir
defp build_params_map(param_names) do
  pairs =
    Enum.map(param_names, fn name ->
      {name, Macro.var(name, nil)}
    end)

  {:%{}, [], pairs}
end
```

The `{:%{}, [], pairs}` is how you build a map literal (`%{id: id}`)
programmatically inside a macro. It's the AST representation — the same
3-element tuple format we explored in Step 3's IEx session.

**6. Update `finalize_routes/0`** — the catch-all now takes two args:

```elixir
defmacro finalize_routes do
  quote do
    defp dispatch(conn, _segments) do
      Ignite.Controller.text(conn, "404 - Not Found", 404)
    end
  end
end
```

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

---

[← Previous: Step 4 - Response Helpers](04-response-helpers.md) | [Next: Step 6 - OTP Supervision →](06-otp-supervision.md)

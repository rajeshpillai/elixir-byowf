# Step 27: Path Helpers & Resource Routes

## What We're Building

Two features that eliminate boilerplate and prevent broken links:
- **Path helpers**: Functions that generate URL strings from route names — `user_path(:show, 42)` instead of hardcoding `"/users/42"`
- **Resource routes**: `resources "/users", UserController` expands into all standard CRUD routes in one line

## The Problem

### Hardcoded Paths Break Silently

Every controller and template in Ignite hardcodes path strings:

```elixir
# In a controller
html(conn, "<a href=\"/users/#{id}\">View User</a>")

# In a template
<a href="/users/<%= @id %>">View User</a>
```

If you rename the route from `/users/:id` to `/people/:id`, the router compiles fine but every link in the app is now broken. There's no compile-time or runtime check that these strings match actual routes.

### CRUD Boilerplate

Defining a standard RESTful resource requires 6 route lines:

```elixir
get "/users", to: UserController, action: :index
get "/users/:id", to: UserController, action: :show
post "/users", to: UserController, action: :create
put "/users/:id", to: UserController, action: :update
patch "/users/:id", to: UserController, action: :update
delete "/users/:id", to: UserController, action: :delete
```

Every resource in the app repeats this pattern. Phoenix solves both problems, and now Ignite does too.

## How Path Helpers Work

### Step 1: Accumulate Route Metadata

Every route macro (`get`, `post`, etc.) already generates a `dispatch/2` function clause. We add one line to also record the route's metadata.

**Update `lib/ignite/router.ex`** — add `@route_info` accumulation to `build_route/4`:

```elixir
# In build_route/4 (inside the quote block)
@route_info {method, path, controller, action}
```

The `@route_info` module attribute uses `accumulate: true`, so each route definition appends to a list. By the time all routes are defined, we have a complete manifest:

```elixir
[
  {"GET", "/", MyApp.WelcomeController, :index},
  {"GET", "/hello", MyApp.WelcomeController, :hello},
  {"GET", "/users", MyApp.UserController, :index},
  {"GET", "/users/:id", MyApp.UserController, :show},
  {"POST", "/users", MyApp.UserController, :create},
  # ...
]
```

### Step 2: `@before_compile` Hook

**Update `lib/ignite/router.ex`** — register a `@before_compile` callback in `__using__/1`:

```elixir
@before_compile Ignite.Router
```

Elixir calls `__before_compile__/1` *after* all module body code has been evaluated (all routes defined) but *before* the module is finalized. This is the perfect moment to read `@route_info` and generate helper functions.

**Update `lib/ignite/router.ex`** — add the `__before_compile__` macro:

```elixir
defmacro __before_compile__(env) do
  route_info = Module.get_attribute(env.module, :route_info) |> Enum.reverse()
  helpers_module = Module.concat(env.module, Helpers)
  helper_functions = Ignite.Router.Helpers.build_helper_functions(route_info)

  quote do
    defmodule unquote(helpers_module) do
      unquote_splicing(helper_functions)
    end
  end
end
```

This generates `MyApp.Router.Helpers` as a nested submodule with all the path functions.

### Step 3: Derive Helper Names

**Create `lib/ignite/router/helpers.ex`** — this module contains pure functions for deriving names from paths and building helper function AST:

```elixir
derive_name("/")           #=> :root_path
derive_name("/users")      #=> :user_path
derive_name("/users/:id")  #=> :user_path
derive_name("/api/status") #=> :api_status_path
```

**Algorithm:**
1. Split path into segments, filter out dynamic (`:param`) segments
2. Singularize the last segment (naive: strip trailing "s")
3. Join all segments with `_`, append `_path`

### Step 4: Build Function Clauses

Each route becomes a function clause. Routes with the same helper name but different actions become multiple clauses of the same function:

```elixir
# Generated at compile time:
def user_path(:index), do: "/users"
def user_path(:show, id), do: "/users/" <> to_string(id)
def user_path(:create), do: "/users"
def user_path(:update, id), do: "/users/" <> to_string(id)
def user_path(:delete, id), do: "/users/" <> to_string(id)
```

PUT and PATCH both map to `:update` with the same path — the helper is deduplicated so only one clause is generated.

## Concepts: Key Functions and Patterns

**`unquote_splicing/1`** — Inserts a list of AST nodes as individual expressions:
```elixir
functions = [quote(do: def foo, do: 1), quote(do: def bar, do: 2)]
quote do
  unquote_splicing(functions)  # Inserts each function as a separate definition
end
```
`unquote` inserts a single AST node. `unquote_splicing` takes a **list** of AST nodes and inserts them individually — like spreading an array.

**`Enum.flat_map/2`** — Maps and flattens in one step:
```elixir
Enum.flat_map([1, 2], fn x -> [x, x * 10] end)  #=> [1, 10, 2, 20]
```
Like `Enum.map`, but each element can return multiple items. The results are flattened into a single list. Used here because some routes (like `:update`) generate two clauses (PUT + PATCH).

**`cond do`** — An `if/else if` chain:
```elixir
cond do
  x > 10 -> "big"
  x > 0  -> "small"
  true   -> "zero or negative"
end
```
Evaluates conditions top-to-bottom and runs the first truthy one. The final `true ->` acts as the default/else clause.

**`{:__block__, [], exprs}`** — This is the raw AST for a block of multiple expressions. When building macro output with multiple definitions programmatically, wrap them in `{:__block__, [], list_of_expressions}`.

## Naive Singularization

Helper names use the singular form: `user_path` not `users_path`. We use a simple heuristic:

```elixir
def naive_singularize(word) do
  cond do
    # "statuses" → "status", "watches" → "watch"
    Regex.match?(~r/(ss|sh|ch|x|z)es$/, word) ->
      String.replace_trailing(word, "es", "")

    # "categories" → "category"
    String.ends_with?(word, "ies") ->
      String.replace_trailing(word, "ies", "y")

    # Don't touch "status", "class", "analysis"
    Regex.match?(~r/(ss|us|is|os)$/, word) -> word

    # "users" → "user", "posts" → "post"
    String.ends_with?(word, "s") ->
      String.replace_trailing(word, "s", "")

    true -> word
  end
end
```

This handles 90%+ of English nouns used in web APIs. Phoenix uses the `Inflex` library for production-grade inflection, but for a framework tutorial, the naive approach is more educational.

## Resource Routes

### The `resources/3` Macro

**Update `lib/ignite/router.ex`** — add the `resources/3` macro:

```elixir
resources "/users", MyApp.UserController
```

Expands at compile time into:

```elixir
get "/users", to: MyApp.UserController, action: :index
get "/users/:id", to: MyApp.UserController, action: :show
post "/users", to: MyApp.UserController, action: :create
put "/users/:id", to: MyApp.UserController, action: :update
patch "/users/:id", to: MyApp.UserController, action: :update
delete "/users/:id", to: MyApp.UserController, action: :delete
```

### Options: `:only` and `:except`

```elixir
resources "/posts", PostController, only: [:index, :show]
resources "/comments", CommentController, except: [:delete]
```

### Implementation

The macro emits the individual route macro calls as a `{:__block__, [], [calls]}` AST node. Because it emits `get`, `post`, etc. macro calls (not raw `dispatch` clauses), it automatically:
- Works inside `scope` blocks (the scope AST transformer handles route macros)
- Accumulates `@route_info` (each route macro does this)
- Generates path helpers (via the accumulated metadata)

```elixir
defmacro resources(path, controller, opts \\ []) do
  only = Keyword.get(opts, :only, nil)
  except = Keyword.get(opts, :except, [])
  all_actions = [:index, :show, :create, :update, :delete]

  actions =
    if only do
      Enum.filter(all_actions, &(&1 in only))
    else
      Enum.reject(all_actions, &(&1 in except))
    end

  routes = Enum.flat_map(actions, fn
    :index  -> [quote(do: get(unquote(path), to: unquote(controller), action: :index))]
    :show   -> [quote(do: get(unquote(path <> "/:id"), to: unquote(controller), action: :show))]
    :create -> [quote(do: post(unquote(path), to: unquote(controller), action: :create))]
    :update -> [
      quote(do: put(unquote(path <> "/:id"), to: unquote(controller), action: :update)),
      quote(do: patch(unquote(path <> "/:id"), to: unquote(controller), action: :update))
    ]
    :delete -> [quote(do: delete(unquote(path <> "/:id"), to: unquote(controller), action: :delete))]
  end)

  {:__block__, [], routes}
end
```

### Scoped Resources

Resources work inside `scope` because we added a `prepend_prefix/2` clause.

**Update `lib/ignite/router.ex`** — add a `prepend_prefix` clause for `:resources`:

```elixir
defp prepend_prefix({:resources, meta, [path | rest]}, prefix)
     when is_binary(path) do
  {:resources, meta, [prefix <> path | rest]}
end
```

So `scope "/api" do resources "/users", ApiUserController end` generates routes at `/api/users`, `/api/users/:id`, etc.

## How Phoenix Does It

Phoenix's path helpers are more sophisticated:

- **Verified routes** (Phoenix 1.7+): `~p"/users/#{user}"` — compile-time checked sigil
- **Inflex**: Production-grade inflection library for singularization
- **Nested resources**: `resources "/users" do resources "/posts" end`
- **Helper names from controller**: Phoenix derives names from the controller module, not just the path
- **Conn-aware**: `user_path(conn, :show, 42)` includes host/scheme for absolute URLs

Our implementation covers the core concept — compile-time code generation from route metadata.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/router/helpers.ex` | **New** — name derivation, AST generation, singularization |
| `lib/ignite/router.ex` | **Modified** — `@route_info` accumulation, `resources/3` macro, `@before_compile` hook |
| `lib/my_app/router.ex` | **Modified** — user CRUD replaced with `resources "/users", MyApp.UserController` |
| `lib/my_app/controllers/user_controller.ex` | **Modified** — added `index/1` action |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — path helper examples on index page |

## Try It

```bash
# Path helpers in IEx
iex -S mix
iex> MyApp.Router.Helpers.user_path(:index)
"/users"
iex> MyApp.Router.Helpers.user_path(:show, 42)
"/users/42"
iex> MyApp.Router.Helpers.api_status_path(:status)
"/api/status"
iex> MyApp.Router.Helpers.root_path(:index)
"/"

# Resource routes work
curl http://localhost:4000/users              # GET index → JSON
curl http://localhost:4000/users/42           # GET show → template
curl -X DELETE http://localhost:4000/users/42 # DELETE → JSON
```

---

[← Previous: Step 26 - File Uploads](26-file-uploads.md) | [Next: Step 28 - Flash Messages →](28-flash-messages.md)

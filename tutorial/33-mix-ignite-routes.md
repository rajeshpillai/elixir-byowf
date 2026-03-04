# Step 33: `mix ignite.routes`

## What We're Building

A custom Mix task that prints every registered route in a formatted table — the same idea as Phoenix's `mix phx.routes`. Run `mix ignite.routes` and see every HTTP method, path, controller, and action at a glance.

```
$ mix ignite.routes
GET     /                MyApp.WelcomeController  :index
GET     /hello           MyApp.WelcomeController  :hello
POST    /users           MyApp.UserController     :create
GET     /users/:id       MyApp.UserController     :show
GET     /api/status      MyApp.ApiController      :status
POST    /api/echo        MyApp.ApiController       :echo
```

## The Problem

Ignite now has 22 routes across multiple controllers, scopes, and resource groups. As the app grows, developers need a quick way to answer:

- "What URL do I hit for the echo API?"
- "Did my new route get registered?"
- "Which controller handles `/dashboard`?"

Without a route listing tool, the only option is reading `router.ex` and mentally expanding `resources` and `scope` macros.

## How Mix Tasks Work

A Mix task is an Elixir module that:

1. Lives in `lib/mix/tasks/`
2. Has a module name starting with `Mix.Tasks.`
3. Uses `Mix.Task` and implements `run/1`

The naming convention maps the module name to the CLI command:

```
Mix.Tasks.Ignite.Routes  →  mix ignite.routes
Mix.Tasks.Ecto.Migrate   →  mix ecto.migrate
Mix.Tasks.Phx.Routes     →  mix phx.routes
```

## Design Decision: Runtime Introspection vs File Parsing

| Approach | Pros | Cons |
|----------|------|------|
| Parse `router.ex` source | No framework changes needed | Fragile — must handle macros, scopes, resources |
| **Runtime introspection** | Accurate — sees the actual compiled routes | Requires the router to expose route data |

We use **runtime introspection**. The router already accumulates `{method, path, controller, action}` tuples in `@route_info` at compile time (for path helper generation). We just need to expose that data via a `__routes__/0` function.

## Implementation

### 1. Exposing Routes at Runtime

The router's `@before_compile` hook already iterates over `@route_info` to generate path helpers. We add a `__routes__/0` function in the same hook.

```elixir
# lib/ignite/router.ex — inside __before_compile__/1
defmacro __before_compile__(env) do
  route_info = Module.get_attribute(env.module, :route_info) |> Enum.reverse()
  helpers_module = Module.concat(env.module, Helpers)
  helper_functions = Ignite.Router.Helpers.build_helper_functions(route_info)

  # Convert tuples to maps for cleaner access
  routes_list =
    Enum.map(route_info, fn {method, path, controller, action} ->
      %{method: method, path: path, controller: controller, action: action}
    end)

  # Macro.escape/1 converts runtime data into quoted AST that can be embedded
  escaped_routes = Macro.escape(routes_list)

  quote do
    defmodule unquote(helpers_module) do
      @moduledoc "..."
      unquote_splicing(helper_functions)
    end

    def __routes__, do: unquote(escaped_routes)
  end
end
```

**`Macro.escape/1`** is the key. Route info includes module atoms like `MyApp.UserController` — you can't just `unquote` a list of maps containing module references directly. `Macro.escape/1` converts the entire data structure into its AST representation, which can be safely embedded in the `quote` block.

After compilation, you can call:

```elixir
MyApp.Router.__routes__()
#=> [
#=>   %{method: "GET", path: "/", controller: MyApp.WelcomeController, action: :index},
#=>   %{method: "GET", path: "/hello", controller: MyApp.WelcomeController, action: :hello},
#=>   ...
#=> ]
```

### 2. The Mix Task

```elixir
# lib/mix/tasks/ignite.routes.ex
defmodule Mix.Tasks.Ignite.Routes do
  @shortdoc "Prints all routes for the router"

  @moduledoc """
  Prints all routes for the given router.

      $ mix ignite.routes
      $ mix ignite.routes MyApp.Router

  If no router module is given, defaults to `MyApp.Router`.
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile", [])

    router =
      case args do
        [module_str | _] -> Module.concat([module_str])
        [] -> MyApp.Router
      end

    Code.ensure_loaded!(router)

    unless function_exported?(router, :__routes__, 0) do
      Mix.raise("""
      Module #{inspect(router)} does not define __routes__/0.

      Make sure the module uses `Ignite.Router` and defines at least one route.
      """)
    end

    routes = router.__routes__()

    if routes == [] do
      Mix.shell().info("No routes found in #{inspect(router)}")
    else
      print_routes(routes)
    end
  end

  defp print_routes(routes) do
    method_width = routes |> Enum.map(&String.length(&1.method)) |> Enum.max() |> max(6)
    path_width = routes |> Enum.map(&String.length(&1.path)) |> Enum.max()
    ctrl_width = routes |> Enum.map(&(inspect(&1.controller) |> String.length())) |> Enum.max()

    Enum.each(routes, fn %{method: method, path: path, controller: ctrl, action: action} ->
      line =
        String.pad_trailing(method, method_width + 2) <>
          String.pad_trailing(path, path_width + 2) <>
          String.pad_trailing(inspect(ctrl), ctrl_width + 2) <>
          inspect(action)

      Mix.shell().info(line)
    end)
  end
end
```

### How the Mix Task Works

**`Mix.Task.run("compile", [])`** — Ensures the project is compiled before we try to call `__routes__/0`. If you just edited a route, the task recompiles first.

**`Module.concat/1`** — Converts `"MyApp.Router"` (a string from CLI args) into the atom `MyApp.Router`.

**`Code.ensure_loaded!/1`** — Forces the BEAM to load the module into memory. After `mix compile`, modules exist as `.beam` files on disk but aren't loaded until first use. `function_exported?/3` checks the loaded module table, so we must load the module first.

**`function_exported?/3`** — Checks if the router defines `__routes__/0`. This catches cases where someone passes a non-router module by mistake.

**`String.pad_trailing/2`** — Pads strings with spaces to align columns. We calculate the maximum width for each column dynamically, so the output looks clean regardless of how long your paths or controller names are.

**`Mix.shell().info/1`** — Prints to stdout. Using `Mix.shell()` instead of `IO.puts/1` is the Mix convention — it allows tests to capture output by swapping in a test shell.

## The Column Alignment Algorithm

```
routes = [
  %{method: "GET",    path: "/users/:id",  controller: MyApp.UserController, action: :show},
  %{method: "DELETE", path: "/users/:id",  controller: MyApp.UserController, action: :delete},
]

method_width = max(length("DELETE"), 6)  = 6
path_width   = length("/users/:id")      = 10
ctrl_width   = length("MyApp.UserController") = 22

Output:
GET     /users/:id  MyApp.UserController  :show
DELETE  /users/:id  MyApp.UserController  :delete
```

Each column is padded to `max_width + 2` (for spacing between columns).

## Testing

```bash
mix compile
mix ignite.routes

# With explicit router:
mix ignite.routes MyApp.Router

# Verify all 22 routes are listed:
mix ignite.routes | wc -l
# → 22

# Check help text appears in mix help:
mix help ignite.routes
```

Expected output:

```
GET     /                MyApp.WelcomeController  :index
GET     /hello           MyApp.WelcomeController  :hello
GET     /crash           MyApp.WelcomeController  :crash
GET     /counter         MyApp.WelcomeController  :counter
GET     /register        MyApp.WelcomeController  :register
GET     /dashboard       MyApp.WelcomeController  :dashboard
GET     /shared-counter  MyApp.WelcomeController  :shared_counter
GET     /components      MyApp.WelcomeController  :components
GET     /hooks           MyApp.WelcomeController  :hooks
GET     /streams         MyApp.WelcomeController  :streams
GET     /upload          MyApp.UploadController   :upload_form
POST    /upload          MyApp.UploadController   :upload
GET     /upload-demo     MyApp.WelcomeController  :upload_demo
GET     /presence        MyApp.WelcomeController  :presence
GET     /users           MyApp.UserController     :index
GET     /users/:id       MyApp.UserController     :show
POST    /users           MyApp.UserController     :create
PUT     /users/:id       MyApp.UserController     :update
PATCH   /users/:id       MyApp.UserController     :update
DELETE  /users/:id       MyApp.UserController     :delete
GET     /api/status      MyApp.ApiController      :status
POST    /api/echo        MyApp.ApiController      :echo
```

Notice how `resources "/users"` expanded into 6 routes (index, show, create, update×2, delete) and the `scope "/api"` prefix appears on the API routes.

## Key Concepts

- **Mix tasks** are Elixir modules in `lib/mix/tasks/` with `use Mix.Task` and a `run/1` callback. The module name maps to the CLI command.
- **`@before_compile`** hooks run after all module code is defined but before final compilation. They can inject functions based on accumulated metadata.
- **`Macro.escape/1`** converts runtime Elixir terms into AST form suitable for `quote` blocks. Essential when embedding complex data (lists of maps with atom values) into generated code.
- **`Code.ensure_loaded!/1`** bridges the gap between compiled `.beam` files on disk and loaded modules in the VM's memory.
- **`Mix.shell()`** is the proper way to do I/O in Mix tasks — it supports test isolation via shell swapping.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Task name | `mix ignite.routes` | `mix phx.routes` |
| Route storage | `__routes__/0` returning maps | `__routes__/0` returning structs |
| Default router | `MyApp.Router` | Reads from endpoint config |
| Output format | Aligned columns | Aligned columns |
| Verb coloring | Plain text | ANSI colors |
| Helper names | Not shown | Shows path helper name |

Phoenix's `mix phx.routes` also displays the generated path helper name (e.g., `user_path`) in the output. Our version focuses on the essentials: method, path, controller, and action.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/router.ex` | Added `__routes__/0` generation in `@before_compile` hook |
| `lib/mix/tasks/ignite.routes.ex` | **New** — Mix task for printing route table |

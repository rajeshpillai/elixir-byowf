# Step 3: Router DSL (Macros)

## What We're Building

Instead of a big `case` statement, we want to write routes like this:

```elixir
get "/", to: WelcomeController, action: :index
get "/hello", to: WelcomeController, action: :hello
```

This is a **DSL** (Domain-Specific Language) — code that reads like a
configuration file but is actually executable Elixir. Phoenix uses the
same approach.

To build this, we need **macros** — Elixir's most powerful feature.

```
  What you write (DSL)              What the compiler generates
  ─────────────────────             ──────────────────────────────────
  get "/", to: Ctrl,    ──macro──▶  defp dispatch(%Conn{method: "GET",
      action: :index                              path: "/"} = conn) do
                                      apply(Ctrl, :index, [conn])
                                    end

  get "/hello", to: Ctrl,──macro──▶ defp dispatch(%Conn{method: "GET",
      action: :hello                              path: "/hello"} = conn) do
                                      apply(Ctrl, :hello, [conn])
                                    end

  finalize_routes()     ──macro──▶  defp dispatch(conn) do
                                      # 404 Not Found
                                    end
```

## Concepts You'll Learn

### What Are Macros?

Macros are **code that writes code**. They run at **compile time** (when
you run `mix compile`), not at runtime.

Here's the idea: when you write this in your router:

```elixir
get "/hello", to: MyController, action: :hello
```

Elixir's compiler sees `get` is a macro and transforms it into:

```elixir
defp dispatch(%Ignite.Conn{method: "GET", path: "/hello"} = conn) do
  apply(MyController, :hello, [conn])
end
```

The router module ends up with multiple `dispatch/1` function clauses,
one per route. The BEAM VM's pattern matching picks the right one instantly.

### defmacro

`defmacro` defines a macro. It looks like a function, but its arguments
are code (AST nodes), and its return value is also code.

```elixir
defmacro get(path, to: controller, action: action) do
  quote do
    defp dispatch(%Ignite.Conn{method: "GET", path: unquote(path)} = conn) do
      apply(unquote(controller), unquote(action), [conn])
    end
  end
end
```

### quote and unquote

`quote` converts Elixir code into its **AST** (Abstract Syntax Tree) — the
internal representation the compiler uses:

```elixir
quote do
  1 + 2
end
#=> {:+, [], [1, 2]}
```

`unquote` injects a value from the macro's scope into the quoted code:

```elixir
defmacro greet(name) do
  quote do
    "Hello, " <> unquote(name)
  end
end
```

Think of `quote` as a template and `unquote` as the placeholder slots.

```
  quote do                              AST (Abstract Syntax Tree)
  ┌─────────────────────────┐          ┌─────────────────────────────┐
  │  "Hello, " <> unquote(  │   ──▶    │  {:<>, [], ["Hello, ",      │
  │    name                 │          │             "world"]}       │
  │  )                      │          │                             │
  └─────────────────────────┘          └─────────────────────────────┘
        template                          code as data (tuples)
```

> **Try it in IEx!** Open a terminal and run `iex` to explore the AST yourself:
>
> ```elixir
> iex> quote do: 1 + 2
> {:+, [context: Elixir, imports: [{2, Kernel}]], [1, 2]}
>
> iex> quote do: "hello"
> "hello"                    # Simple values are their own AST
>
> iex> name = "world"
> iex> quote do: "hello, " <> unquote(name)
> {:<>, [context: Elixir, imports: [{2, Kernel}]], ["hello, ", "world"]}
> ```
>
> Notice the pattern: every expression becomes a 3-element tuple `{operation, metadata, arguments}`. That's all the AST is — nested tuples that describe your code. Macros receive these tuples and return new ones.

### import vs alias

You've seen `alias` in Step 2 — it creates a shortcut for a module name.
`import` is different: it brings a module's functions (or macros) into scope
so you can call them **without the module prefix**:

```elixir
# With alias — still need the module prefix for macros:
alias Ignite.Router
Router.get "/hello", ...     # Works, but verbose in a router file

# With import — macros are available directly:
import Ignite.Router
get "/hello", ...            # Clean! This is what we want in a DSL
```

Rule of thumb:

```
  Directive    Effect                          Example
  ──────────   ─────────────────────────────   ──────────────────────
  alias        Shorter name for a module       Ignite.Conn → Conn
  import       Use functions without prefix    text(conn, "Hi")
  use          Run __using__ macro to setup    use Ignite.Router
```

### use and __using__

When you write `use Ignite.Router`, Elixir calls `Ignite.Router.__using__/1`.
This is a macro that injects code into the calling module:

```elixir
defmacro __using__(_opts) do
  quote do
    import Ignite.Router         # Makes get/finalize_routes available
    def call(conn) do            # Defines the entry point
      dispatch(conn)
    end
  end
end
```

After `use Ignite.Router`, your module has:
- The `call/1` function
- Access to `get`, `finalize_routes` macros

```
  use Ignite.Router
       │
       ▼ calls __using__/1
  ┌────────────────────────────┐
  │ Injects into your module:  │
  │  ├── import Ignite.Router  │──▶ get/2, finalize_routes/0 available
  │  └── def call(conn)        │──▶ entry point defined
  └────────────────────────────┘
```

### apply/3

In many languages you can call a method dynamically with `object.method()`.
Elixir modules aren't objects — you can't write `controller.action(conn)`.
Instead, Elixir provides `apply/3`, a built-in function that calls any
function when you have the module and function name as variables:

```elixir
apply(MyApp.WelcomeController, :index, [conn])
# Same as calling directly:
MyApp.WelcomeController.index(conn)
```

The three arguments are:
1. **Module** — the module that defines the function (e.g. `MyApp.WelcomeController`)
2. **Function name** — an atom (e.g. `:index`)
3. **Arguments** — a list of arguments to pass (e.g. `[conn]`)

We need `apply` in the router because the module and function come from
macro arguments — they're variables, not hardcoded names. You can't write
`unquote(controller).unquote(action)(conn)` in Elixir; `apply/3` is the
way to make dynamic function calls.

## The Code

### `lib/ignite/router.ex`

**Create `lib/ignite/router.ex`.** One built-in callback and two custom macros work together:

1. **`__using__/1`** — a special Elixir callback macro, automatically invoked when someone writes `use Ignite.Router`. Every module that wants to support `use` must define this.
2. **`get/2`** — a custom macro we define. Generates a `dispatch` clause for each GET route.
3. **`finalize_routes/0`** — a custom macro we define. Generates a catch-all 404 clause.

The key insight: each `get` call **defines a function clause**. Elixir
functions can have multiple clauses, and the VM tries them in order:

```elixir
# Generated by: get "/", to: WelcomeController, action: :index
defp dispatch(%Conn{method: "GET", path: "/"} = conn), do: ...

# Generated by: get "/hello", to: WelcomeController, action: :hello
defp dispatch(%Conn{method: "GET", path: "/hello"} = conn), do: ...

# Generated by: finalize_routes()
defp dispatch(conn), do: %Conn{conn | status: 404, ...}
```

### `lib/my_app/router.ex`

**Create `lib/my_app/router.ex`.** This is what a **user** of the framework writes:

```elixir
defmodule MyApp.Router do
  use Ignite.Router

  get "/", to: MyApp.WelcomeController, action: :index
  get "/hello", to: MyApp.WelcomeController, action: :hello

  finalize_routes()
end
```

Clean, declarative, and readable. The macros do all the heavy lifting.

### `lib/my_app/controllers/welcome_controller.ex`

**Create `lib/my_app/controllers/welcome_controller.ex`.** Controllers receive a conn and return a modified conn:

```elixir
def index(conn) do
  %Ignite.Conn{conn | resp_body: "Welcome to Ignite!"}
end
```

The `%Conn{conn | resp_body: "..."}` syntax creates a **new** conn with
the `resp_body` field updated. The original conn is never modified
(immutability!).

### Updated `lib/ignite/server.ex`

**Update `lib/ignite/server.ex`** — replace the `serve/1` function with the version below. The server now follows: **Parse → Route → Respond**:

```elixir
conn = Ignite.Parser.parse(client_socket)    # 1. Parse
conn = MyApp.Router.call(conn)               # 2. Route
response = build_response(conn.status, conn.resp_body)  # 3. Respond
```

## How It Works

At compile time:

```
get "/hello", to: Ctrl, action: :hello
        ↓ (macro expansion)
defp dispatch(%Conn{method: "GET", path: "/hello"} = conn) do
  apply(Ctrl, :hello, [conn])
end
```

At runtime:

```
Browser: GET /hello
        ↓
MyApp.Router.call(conn)
        ↓
dispatch(%Conn{method: "GET", path: "/hello"})
        ↓ (pattern match succeeds!)
MyApp.WelcomeController.hello(conn)
        ↓
%Conn{resp_body: "Hello from the Controller!"}
```

## Try It Out

1. Start the server:

```bash
iex -S mix
iex> Ignite.Server.start()
```

2. Visit http://localhost:4000/ → "Welcome to Ignite!"

3. Visit http://localhost:4000/hello → "Hello from the Controller!"

4. Visit http://localhost:4000/anything → "404 — Not Found"

The router pattern-matches each request to the right controller automatically.

## File Checklist

After this step, your project should have these files:

| File | Status | Purpose |
|------|--------|---------|
| `lib/ignite/router.ex` | **New** | Router DSL with `get` macro and `finalize_routes` |
| `lib/my_app/router.ex` | **New** | App-level route definitions |
| `lib/my_app/controllers/welcome_controller.ex` | **New** | Welcome page controller |
| `lib/ignite/server.ex` | **Modified** | Now delegates to the router |
| `lib/ignite/conn.ex` | Unchanged | Conn struct (from Step 2) |
| `lib/ignite/parser.ex` | Unchanged | HTTP parser (from Step 2) |

## What's Next

Our controllers are building response strings manually with `%{conn | resp_body: ...}`.
In **Step 4**, we'll create **Response Helpers** like `text(conn, "Hello!")` that
handle status codes and content types automatically — just like Phoenix's
`text/2` and `html/2`.

---

[← Previous: Step 2 - The Conn Struct & Parser](02-conn-struct.md) | [Next: Step 4 - Response Helpers →](04-response-helpers.md)

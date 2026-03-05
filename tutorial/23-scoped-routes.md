# Step 23: Scoped Routes

## What We're Building

A `scope` macro that groups routes under a common path prefix, reducing repetition and organizing routes logically. Scopes can also be nested.

## The Problem

Without scoping, API routes look like this:

```elixir
get "/api/status", to: ApiController, action: :status
post "/api/echo", to: ApiController, action: :echo
get "/api/v1/users", to: ApiController, action: :users_v1
get "/api/v1/posts", to: ApiController, action: :posts_v1
```

The `/api` and `/api/v1` prefixes are duplicated everywhere. In Phoenix, you'd use `scope` to group them:

```elixir
scope "/api" do
  get "/status", to: ApiController, action: :status

  scope "/v1" do
    get "/users", to: ApiController, action: :users_v1
  end
end
```

## The Solution

### The Challenge: Macro Expansion Order

The tricky part is that route macros like `get` run at compile time — they generate function clauses. A naive approach would be to use a module attribute (`@scope_prefix`) as compile-time state:

```elixir
# ❌ This doesn't work!
defmacro scope(prefix, do: block) do
  quote do
    @scope_prefix @scope_prefix <> unquote(prefix)
    unquote(block)  # macros here expand BEFORE @scope_prefix is set!
    @scope_prefix ""
  end
end
```

The problem: Elixir expands macros inside `unquote(block)` before evaluating the `@scope_prefix` assignment. So when `get "/status"` expands, the prefix is still `""`.

### The Real Solution: AST Transformation

Instead of relying on mutable state, we **directly transform the AST**. The `scope` macro walks the block's syntax tree and rewrites every route macro call to include the prefix:

```elixir
defmacro scope(prefix, do: block) do
  prepend_prefix(block, prefix)
end
```

Before expansion, `scope "/api" do get "/status", ... end` becomes `get "/api/status", ...`. The route macro never even knows it was inside a scope — it just sees the full path.

### Implementation

#### The `scope` Macro

**Update `lib/ignite/router.ex`** — add the `scope` macro and the private `prepend_prefix` helper functions below to the module:

```elixir
defmacro scope(prefix, do: block) do
  prepend_prefix(block, prefix)
end
```

```elixir
# A block with multiple expressions: transform each one
defp prepend_prefix({:__block__, meta, exprs}, prefix) do
  {:__block__, meta, Enum.map(exprs, &prepend_prefix(&1, prefix))}
end

# Route macros: prepend prefix to the path argument
defp prepend_prefix({method, meta, [path | rest]}, prefix)
     when method in [:get, :post, :put, :patch, :delete] and is_binary(path) do
  {method, meta, [prefix <> path | rest]}
end

# Nested scope: prepend prefix to the inner scope's prefix
defp prepend_prefix({:scope, meta, [inner_prefix | rest]}, prefix)
     when is_binary(inner_prefix) do
  {:scope, meta, [prefix <> inner_prefix | rest]}
end

# Anything else: pass through unchanged
defp prepend_prefix(expr, _prefix), do: expr
```

**How it works:**

1. The compiler sees `scope "/api" do ... end` and calls our macro
2. We receive the `do` block as raw AST (a tree of tuples)
3. We walk the tree and find any `get`, `post`, etc. calls
4. We prepend `"/api"` to their path argument: `"/status"` → `"/api/status"`
5. For nested `scope` calls, we prepend to their prefix: `"/v1"` → `"/api/v1"`
6. We return the transformed AST — no `quote` needed

### Nesting

Nesting works naturally because of how AST transformation composes:

```elixir
scope "/api" do              # transforms children with "/api"
  scope "/v1" do             # "/v1" becomes "/api/v1", transforms its children
    get "/users", ...        # "/users" becomes "/api/v1/users"
  end
  get "/status", ...         # "/status" becomes "/api/status"
end
```

The outer `scope` sees the inner `scope` call and prepends `/api` to its prefix argument. When the inner `scope` macro is then expanded, it sees `/api/v1` as its prefix and prepends that to its routes.

## Using It

### Router

**Replace `lib/my_app/router.ex` with:**

```elixir
defmodule MyApp.Router do
  use Ignite.Router

  # Top-level routes (no scope)
  get "/", to: WelcomeController, action: :index
  get "/hello", to: WelcomeController, action: :hello

  # API routes grouped under /api
  scope "/api" do
    get "/status", to: ApiController, action: :status
    post "/echo", to: ApiController, action: :echo
  end

  finalize_routes()
end
```

## Testing

```bash
# Scoped route works
curl http://localhost:4000/api/status
# → {"elixir_version":"1.18.4","framework":"Ignite","status":"ok",...}

# Non-scoped routes still work
curl http://localhost:4000/hello
# → Hello from the Controller!

# Unscoped path correctly returns 404
curl http://localhost:4000/status
# → 404 — Not Found
```

## Key Elixir Concepts

- **AST as data**: In Elixir, code is represented as tuples. `get "/status", to: Ctrl, action: :show` becomes `{:get, meta, ["/status", [to: Ctrl, action: :show]]}`. Since AST is just data, we can walk and transform it like any other data structure.

- **Pattern matching on AST**: We use guards like `when method in [:get, :post, ...]` to match only the route macro calls we care about. Everything else passes through unchanged.

- **No runtime overhead**: This transformation happens entirely at compile time. The final compiled module has no trace of scopes — just direct dispatch function clauses with full paths.

- **Why not module attributes?** Module attributes (`@scope_prefix`) seem like the right tool, but Elixir's macro expansion runs in a separate phase from module attribute evaluation. By the time `@scope_prefix` is set, the route macros inside the block have already been expanded with the old value. AST transformation avoids this by rewriting the code *before* any macros are expanded.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/router.ex` | **Modified** — added `scope` macro and `prepend_prefix` helpers |
| `lib/my_app/router.ex` | **Modified** — uses `scope` for API routes |

## How Phoenix Does It

Phoenix's `scope` is more powerful — it also supports:
- `pipe_through :api` to apply different plug pipelines per scope
- `alias: MyApp.Web` to set default controller namespaces
- `as: :admin` to prefix path helper names

Phoenix uses a combination of module attributes and careful macro expansion ordering to achieve this. Our AST transformation approach is simpler and covers the most common use case (path prefixing with nesting).

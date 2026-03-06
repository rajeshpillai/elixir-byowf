# Step 42: FEEx Templates (Flame EEx)

## What We're Building

A new template sigil `~F` (Flame EEx) that improves on `~L` with three features:

1. **`@` shorthand** — write `@count` instead of `assigns.count`
2. **Block expressions** — `if`, `for`, `case`, `cond` work inside `<% %>` tags
3. **Auto HTML escaping** — dynamic values are escaped by default, preventing XSS

This is our equivalent of Phoenix's progression from LEEx (`~L`) to HEEx (`~H`). Phoenix called theirs **H**TML **E**Ex. We call ours **F**lame **E**Ex — FEEx, because Ignite.

## The Problem

With the `~L` sigil from Step 24, you write templates like this:

```elixir
def render(assigns) do
  ~L"""
  <h1>Hello, <%= assigns.name %></h1>
  <%= if assigns.show, do: "<p>Count: " <> to_string(assigns.count) <> "</p>", else: "" %>
  """
end
```

Three pain points:

1. **Verbose** — `assigns.name` everywhere instead of `@name`
2. **No blocks** — `<% if ... do %>` doesn't work, forcing ugly inline ternaries
3. **No escaping** — if `assigns.name` is `<script>alert('xss')</script>`, it renders as HTML

With plain string interpolation (no sigil), it's even worse — you must manually call `esc()` on every dynamic value.

## The Solution

### The `~F` Sigil

```elixir
def render(assigns) do
  ~F"""
  <h1>Hello, <%= @name %></h1>
  <%= if @show do %>
    <p>Count: <%= @count %></p>
  <% end %>
  <ul>
    <%= for item <- @items do %>
      <li><%= item.name %></li>
    <% end %>
  </ul>
  """
end
```

Clean, readable, safe. Let's build it.

### Architecture: Three Layers

```
Template String
      │
      ▼
┌─────────────┐
│ Pre-process  │  @name → assigns.name (regex replace)
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ EEx.compile  │  Parse <% %> and <%= %> tags
└─────┬───────┘
      │
      ▼
┌─────────────┐
│ FEExEngine   │  Split into statics/dynamics, escape, handle blocks
└─────┬───────┘
      │
      ▼
  %Rendered{}    Same struct as ~L — diffing engine works unchanged
```

### Step 1: The FEEx Engine

The engine implements the `EEx.Engine` behaviour, just like our existing `EExEngine` from Step 24. The key additions are block support and auto-escaping.

**Create `lib/ignite/live_view/feex_engine.ex`:**

```elixir
defmodule Ignite.LiveView.FEExEngine do
  @behaviour EEx.Engine

  @impl true
  def init(_opts) do
    # State: {reversed_statics, reversed_dynamics, pending_text_buffer}
    {[], [], ""}
  end

  @impl true
  def handle_begin(_state) do
    # Fresh sub-buffer for block body (if/for/case/cond)
    {[], [], ""}
  end

  @impl true
  def handle_end(state) do
    # Convert sub-buffer into AST that produces a string
    {statics_rev, dynamics_rev, trailing} = state
    statics = Enum.reverse([trailing | statics_rev])
    dynamics_ast = Enum.reverse(dynamics_rev)
    build_body_ast(statics, dynamics_ast)
  end

  @impl true
  def handle_text(state, _meta, text) do
    {statics, dynamics, pending} = state
    {statics, dynamics, pending <> text}
  end

  @impl true
  def handle_expr(state, "=", expr) do
    {statics, dynamics, pending} = state

    wrapped =
      if block_expr?(expr) do
        # Block expression (if/for/case/cond) written as <%= if ... do %>.
        # The body was compiled by handle_begin/handle_end and contains
        # already-escaped inner expressions. Don't escape again.
        quote do
          case unquote(expr) do
            nil -> ""
            list when is_list(list) -> Enum.join(list)
            val -> to_string(val)
          end
        end
      else
        # Simple value expression: auto-escape HTML
        quote do: Ignite.LiveView.FEExEngine.escape(unquote(expr))
      end

    {[pending | statics], [wrapped | dynamics], ""}
  end

  def handle_expr(state, "", expr) do
    # Non-output block expression (<% if ... do %> without =)
    {statics, dynamics, pending} = state

    wrapped =
      quote do
        case unquote(expr) do
          nil -> ""
          list when is_list(list) -> Enum.join(list)
          val -> to_string(val)
        end
      end

    {[pending | statics], [wrapped | dynamics], ""}
  end

  def handle_expr(state, _marker, _expr), do: state

  @impl true
  def handle_body(state) do
    {statics_rev, dynamics_rev, trailing} = state
    statics = Enum.reverse([trailing | statics_rev])
    dynamics_ast = Enum.reverse(dynamics_rev)

    quote do
      %Ignite.LiveView.Rendered{
        statics: unquote(statics),
        dynamics: unquote(dynamics_ast)
      }
    end
  end

  # --- AST analysis ---

  defp block_expr?({atom, _, args}) when atom in [:if, :unless, :case, :cond, :for] do
    is_list(args) and Enum.any?(args, fn
      [{:do, _} | _] -> true
      _ -> false
    end)
  end

  defp block_expr?(_), do: false

  # --- Runtime helpers ---

  def escape({:safe, val}), do: to_string(val)
  def escape(nil), do: ""

  def escape(val) when is_binary(val) do
    val
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def escape(val), do: escape(to_string(val))

  # --- Private: AST builders ---

  defp build_body_ast([""], []), do: ""
  defp build_body_ast([s], []), do: s

  defp build_body_ast(statics, dynamics) do
    iodata = interleave(statics, dynamics)
    quote do: IO.iodata_to_binary(unquote(iodata))
  end

  defp interleave([s | rest_s], [d | rest_d]) do
    [s, d | interleave(rest_s, rest_d)]
  end

  defp interleave([s], []) do
    [s]
  end
end
```

### How Block Compilation Works

When EEx encounters `<% if @show do %>...<% end %>`, it orchestrates these callbacks:

1. **`handle_begin/1`** — EEx calls this to start a sub-buffer for the block body. We return a fresh `{[], [], ""}` state, independent of the parent.

2. **Inner content** — Text and `<%= %>` expressions inside the block go through `handle_text` and `handle_expr("=", ...)` on the sub-buffer. The inner `<%= @count %>` gets auto-escaped just like a top-level expression.

3. **`handle_end/1`** — EEx calls this to finalize the block body. We compile the sub-buffer's statics and dynamics into an AST that produces a concatenated string using `IO.iodata_to_binary/1`.

4. **Substitution** — EEx plugs the body AST into the block: `if assigns.show do body_ast end`

5. **`handle_expr("=", full_block_ast)`** — The complete block expression (with body) arrives as an output expression (because users write `<%= if ... do %>`). We detect it's a block via `block_expr?/1` and skip escaping — the inner expressions were already escaped in step 2. We wrap it in a `case` that handles:
   - `nil` → `""` (for `if` without `else`)
   - `list` → `Enum.join(list)` (for `for` comprehensions)
   - anything else → `to_string(val)`

The entire block becomes **one dynamic** in the `%Rendered{}` struct. When the condition changes, that dynamic's value changes, and the diffing engine sends the update.

### The Double-Escaping Trap

There's a subtle bug to avoid. When users write `<%= if @show do %>...<% end %>`, EEx sends the entire `if` block through `handle_expr("=", ...)` — the same callback as simple values like `<%= @name %>`. If we blindly escape everything in the `"="` handler, block output gets double-escaped:

```
<p>Count: 42</p>  →  &lt;p&gt;Count: 42&lt;/p&gt;   ← WRONG
```

The fix: inspect the AST to detect block expressions and skip escaping for them:

```elixir
defp block_expr?({atom, _, args}) when atom in [:if, :unless, :case, :cond, :for] do
  is_list(args) and Enum.any?(args, fn
    [{:do, _} | _] -> true
    _ -> false
  end)
end

defp block_expr?(_), do: false
```

This checks two things: (1) the expression is one of the known block-forming keywords, and (2) its arguments include a `do:` keyword — the telltale sign of a block. Simple expressions like `<%= if(x, do: y) %>` also match, which is correct since they behave the same way.

### Step 2: Auto HTML Escaping

The `escape/1` function wraps every `<%= %>` output:

```elixir
# In handle_expr for "=" marker:
wrapped = quote do: Ignite.LiveView.FEExEngine.escape(unquote(expr))
```

It handles three cases:

| Input | Output | Why |
|-------|--------|-----|
| `"<script>alert('xss')</script>"` | `"&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"` | Dangerous HTML escaped |
| `{:safe, "<b>bold</b>"}` | `"<b>bold</b>"` | Trusted HTML passed through |
| `nil` | `""` | Nil-safe |

### Step 3: The `raw/1` Helper

When you have trusted HTML (like output from a render helper), wrap it in `raw/1`:

```elixir
def raw(val), do: {:safe, val}
```

The `escape/1` function recognizes `{:safe, _}` tuples and passes them through unchanged. This is the same convention Phoenix uses.

```elixir
# Auto-escaped (safe default):
<%= @user_input %>

# Raw HTML (you trust this):
<%= raw(@pre_rendered_html) %>
```

### Step 4: The `@` Shorthand

The sigil pre-processes the template string before passing it to EEx:

```elixir
defmacro sigil_F({:<<>>, _meta, [template]}, _modifiers) do
  processed = Regex.replace(~r/(?<![.\w:\/])@(\w+)/, template, "assigns.\\1")
  EEx.compile_string(processed, engine: Ignite.LiveView.FEExEngine)
end
```

**The regex `(?<![.\w:\/])@(\w+)`:**

| Pattern | Match? | Why |
|---------|--------|-----|
| `@name` | Yes | Standalone assign reference |
| `@count` in `<%= @count %>` | Yes | Inside EEx tag |
| `user@example.com` | No | `@` preceded by word char `r` |
| `http://x@y.com` | No | `@` preceded by `/` |

The lookbehind `(?<![.\w:\/])` prevents matching `@` that's part of an email address, URL, or dotted path. Only freestanding `@word` gets transformed.

**This happens at compile time.** By the time EEx sees the template, `@name` has already become `assigns.name`. The compiled module contains direct `assigns.name` references — zero runtime overhead for the shorthand.

### Step 5: Wire It Up

**Update `lib/ignite/live_view.ex`** — add the sigil and helper to the module, and import them in `__using__`:

```elixir
# Add sigil_F macro (after existing sigil_L):
defmacro sigil_F({:<<>>, _meta, [template]}, _modifiers) do
  processed = Regex.replace(~r/(?<![.\w:\/])@(\w+)/, template, "assigns.\\1")
  EEx.compile_string(processed, engine: Ignite.LiveView.FEExEngine)
end

# Add raw/1 helper:
def raw(val), do: {:safe, val}

# Update __using__ imports:
import Ignite.LiveView, only: [
  push_redirect: 2,
  push_redirect: 3,
  live_component: 3,
  collect_components: 1,
  sigil_L: 2,
  sigil_F: 2,     # new
  raw: 1           # new
]
```

No changes needed to the diffing engine, handler, or frontend JavaScript — `~F` produces the same `%Rendered{}` struct that `~L` does.

## Using It

### Convert CounterLive to `~F`

**Before (`~L`):**
```elixir
def render(assigns) do
  ~L"""
  <div id="counter">
    <h1>Live Counter</h1>
    <p><%= assigns.count %></p>
    <button ignite-click="increment">+1</button>
  </div>
  """
end
```

**After (`~F`):**
```elixir
def render(assigns) do
  ~F"""
  <div id="counter">
    <h1>Live Counter</h1>
    <p><%= @count %></p>
    <button ignite-click="increment">+1</button>
  </div>
  """
end
```

### Blocks: Conditional Rendering

```elixir
def render(assigns) do
  ~F"""
  <div>
    <h1>Welcome, <%= @username %></h1>
    <%= if @is_admin do %>
      <div class="admin-panel">
        <h2>Admin Controls</h2>
        <button ignite-click="reset_all">Reset All</button>
      </div>
    <% end %>
  </div>
  """
end
```

Without `~F`, this requires an inline ternary or a separate helper function.

### Blocks: List Rendering with `for`

```elixir
def render(assigns) do
  ~F"""
  <ul class="todo-list">
    <%= for todo <- @todos do %>
      <li class="todo-item">
        <span><%= todo.title %></span>
        <button ignite-click="delete" ignite-value="<%= todo.id %>">Delete</button>
      </li>
    <% end %>
  </ul>
  """
end
```

The `for` block produces a list of strings (one per iteration). The engine joins them into a single dynamic.

### Auto-Escaping in Action

```elixir
# If @name is: <script>alert('xss')</script>

# ~L (no escaping — XSS vulnerability!):
~L"""<p><%= assigns.name %></p>"""
# Renders: <p><script>alert('xss')</script></p>  ← DANGER

# ~F (auto-escaped — safe):
~F"""<p><%= @name %></p>"""
# Renders: <p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>  ← SAFE
```

### Embedding Raw HTML

For render helpers that return pre-built HTML:

```elixir
def render(assigns) do
  header = render_header(assigns)

  ~F"""
  <div class="app">
    <%= raw(header) %>
    <main><%= @content %></main>
  </div>
  """
end

defp render_header(assigns) do
  "<header><h1>#{assigns.title}</h1></header>"
end
```

## Comparing `~L` vs `~F`

| Feature | `~L` (Step 24) | `~F` (Step 42) |
|---------|---------------|----------------|
| Syntax | `<%= assigns.count %>` | `<%= @count %>` |
| Blocks | Not supported | `if`, `for`, `case`, `cond` |
| Escaping | None (raw output) | Auto-escaped |
| Raw HTML | Default behavior | `raw(html)` |
| Output | `%Rendered{}` | `%Rendered{}` |
| Diffing | Sparse diffs | Sparse diffs (blocks = 1 dynamic) |
| Wire format | Same | Same |

Both produce `%Rendered{}` structs. The diffing engine, handler, and frontend JS work identically. The improvement is purely in developer experience and security.

## Key Elixir Concepts

- **Regex lookbehinds** — `(?<![.\w:\/])` is a negative lookbehind assertion. It matches a position NOT preceded by the listed characters. Elixir's `Regex` module uses Erlang's `:re` which supports PCRE lookbehinds.

- **EEx engine callbacks** — The `handle_begin`/`handle_end` pair enables nested compilation. EEx calls `handle_begin` to start a sub-context, processes the block body using regular callbacks, then calls `handle_end` to finalize. The result is plugged into the parent expression. This is how EEx supports arbitrary nesting depth.

- **Tagged tuples for type dispatch** — `{:safe, val}` is a tagged tuple pattern. Instead of a boolean flag (`escape: false`), we use the tuple's first element as a type tag. The `escape/1` function pattern-matches on it. This is idiomatic Erlang/Elixir — see also `{:ok, val}`, `{:error, reason}`.

- **`IO.iodata_to_binary/1`** — Converts nested lists of strings and charlists into a single binary. More efficient than repeated `<>` concatenation for building strings from many parts, because it avoids creating intermediate binaries.

## How Phoenix Does It

Phoenix's HEEx (`~H`) goes further than our `~F`:

- **HTML-aware parsing** — validates tag matching, catches `<div><span></div>` errors at compile time
- **Component syntax** — `<.header title="Hello" />` calls function components
- **Assign tracking** — if you don't use `@count` in a render, changing `count` skips that template entirely
- **Nested `%Rendered{}`** — components produce their own `%Rendered{}` structs, enabling independent diffing
- **Comprehension tracking** — `for` loops diff individual items, not the whole list

Our `~F` covers the three most impactful features (shorthand, blocks, escaping) while keeping the implementation simple enough to understand in one sitting.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/live_view/feex_engine.ex` | **New** — FEEx engine with blocks, escaping |
| `lib/ignite/live_view.ex` | **Modified** — added `sigil_F`, `raw/1`, updated imports |

---

[← Previous: Step 41 - Stream Upsert & Limit](41-stream-upsert-limit.md)

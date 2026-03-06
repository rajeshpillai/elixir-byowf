# Step 24: Fine-Grained Diffing

## What We're Building

An upgrade to the LiveView diffing engine that sends only the values that actually changed, instead of the entire rendered HTML. The Dashboard (which auto-refreshes 8 stats every second) goes from ~2000 bytes/tick to ~50 bytes/tick.

## The Problem

In Step 14, we built a diffing engine that splits templates into "statics" and "dynamics." But our implementation was a shortcut:

```elixir
defp split_template(html) do
  {["", ""], [html]}  # Everything is one big dynamic!
end
```

The entire rendered HTML is treated as a single dynamic chunk. Every update sends the full HTML, even if only one number changed. For the DashboardLive with 8 stat cards refreshing every second, that's ~2KB sent per tick — mostly static HTML that never changes.

## The Solution

### Three Key Ideas

1. **Split templates at compile time** — A custom EEx engine separates `<%= expr %>` expressions from the surrounding HTML during compilation. Static HTML is known at compile time; only dynamic values are evaluated at runtime.

2. **Track individual dynamics** — Each `<%= %>` expression gets its own index. The engine compares old dynamics to new dynamics per-index.

3. **Sparse updates** — On each update, send only the indices that changed as a JSON object: `{"0": "42", "3": "5.2 MB"}` instead of a full array.

### The `~L` Sigil

LiveViews use a new `~L` sigil (Live template) instead of string interpolation:

**Before:**
```elixir
def render(assigns) do
  """
  <h1>Count: #{assigns.count}</h1>
  <button ignite-click="inc">+1</button>
  """
end
```

**After:**
```elixir
def render(assigns) do
  ~L"""
  <h1>Count: <%= assigns.count %></h1>
  <button ignite-click="inc">+1</button>
  """
end
```

The `~L` sigil uses EEx syntax (`<%= %>`). At compile time, it produces a `%Rendered{}` struct:

```elixir
%Rendered{
  statics: ["<h1>Count: ", "</h1>\n<button ignite-click=\"inc\">+1</button>\n"],
  dynamics: ["0"]  # evaluated at runtime
}
```

### Concepts: Key Functions Used

**`Enum.zip/2`** — Pairs up elements from two lists into tuples:
```elixir
Enum.zip(["a", "b"], [1, 2])  #=> [{"a", 1}, {"b", 2}]
```
Used here to compare old and new dynamic values side by side.

**`Enum.with_index/1`** — Attaches a zero-based index to each element:
```elixir
Enum.with_index(["a", "b", "c"])  #=> [{"a", 0}, {"b", 1}, {"c", 2}]
```
We use it to track which position changed.

### Custom EEx Engine

Elixir's EEx module supports custom "engines" that control how templates are compiled. The default engine produces a concatenated string. Our engine produces a `%Rendered{}` struct.

First, define the struct that holds the split template.

**Create `lib/ignite/live_view/rendered.ex`:**

```elixir
defmodule Ignite.LiveView.Rendered do
  defstruct statics: [], dynamics: []
end
```

Then the engine.

**Create `lib/ignite/live_view/eex_engine.ex`:**

```elixir
defmodule Ignite.LiveView.EExEngine do
  @behaviour EEx.Engine

  # Start with empty accumulators
  def init(_opts), do: {[], [], ""}

  # Required callbacks — EEx.Engine requires these even if unused
  def handle_begin(state), do: state
  def handle_end(state), do: state

  # Literal text → append to pending buffer
  def handle_text(state, _meta, text) do
    {statics, dynamics, pending} = state
    {statics, dynamics, pending <> text}
  end

  # <%= expr %> → flush pending text as a static, record the expression
  def handle_expr(state, "=", expr) do
    {statics, dynamics, pending} = state
    wrapped = quote do: to_string(unquote(expr))
    {[pending | statics], [wrapped | dynamics], ""}
  end

  # <% expr %> (non-output) — not supported in ~L, silently ignored
  def handle_expr(state, _marker, _expr), do: state

  # Final step → build the %Rendered{} struct
  def handle_body(state) do
    {statics_rev, dynamics_rev, trailing_text} = state
    statics = Enum.reverse([trailing_text | statics_rev])
    dynamics_ast = Enum.reverse(dynamics_rev)

    quote do
      %Ignite.LiveView.Rendered{
        statics: unquote(statics),
        dynamics: unquote(dynamics_ast)
      }
    end
  end
end
```

**How the callbacks fire** for `<h1>Count: <%= assigns.count %></h1>`:

1. `handle_text` → `"<h1>Count: "` (accumulates in pending buffer)
2. `handle_expr("=", ...)` → flushes `"<h1>Count: "` as statics[0], records `assigns.count` as dynamics[0]
3. `handle_text` → `"</h1>"` (new pending buffer)
4. `handle_body` → appends `"</h1>"` as statics[1], returns AST

Result: `statics = ["<h1>Count: ", "</h1>"]`, `dynamics = [to_string(assigns.count)]`

### The `sigil_L` Macro

**Update `lib/ignite/live_view.ex`** — add the `sigil_L` macro to the module:

```elixir
defmacro sigil_L({:<<>>, _meta, [template]}, _modifiers) do
  EEx.compile_string(template, engine: Ignite.LiveView.EExEngine)
end
```

**Custom sigil AST**: When you define `defmacro sigil_L({:<<>>, _meta, [template]}, _modifiers)`, the first argument is the AST representation of the string inside `~L"..."`. Elixir passes string literals to sigil macros as `{:<<>>, metadata, [string_content]}` — a 3-tuple where the string content is in a list. You destructure it to get the raw template string.

This calls `EEx.compile_string/2` at compile time with our custom engine. The result is AST that, when evaluated at runtime, constructs a `%Rendered{}` struct.

**Variable hygiene**: `EEx.compile_string` produces unhygienic variable references. This is exactly what we want — `assigns` in the template refers to the function parameter `assigns`.

### Sparse Diffing

**Update `lib/ignite/live_view/engine.ex`** — replace the `diff` function with index-by-index comparison:

```elixir
def diff(old_dynamics, new_dynamics) do
  changes =
    old_dynamics
    |> Enum.zip(new_dynamics)
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{old, new}, idx}, acc ->
      if old == new, do: acc, else: Map.put(acc, Integer.to_string(idx), new)
    end)

  if map_size(changes) == length(new_dynamics) do
    new_dynamics  # All changed → send as array
  else
    changes       # Some changed → send as sparse object
  end
end
```

### Wire Protocol

**Mount** (full payload — statics + dynamics):
```json
{"s": ["<h1>Count: ", "</h1>..."], "d": ["0"]}
```

**Update** (sparse — only changed indices):
```json
{"d": {"0": "1"}}
```

**Full update** (when all dynamics changed):
```json
{"d": ["1", "online"]}
```

### Frontend Changes

**Update `assets/ignite.js`** — update the WebSocket message handler to support sparse dynamic updates:

```javascript
if (Array.isArray(data.d)) {
  dynamics = data.d;           // Full replacement
} else {
  for (var key in data.d) {    // Sparse patch
    dynamics[parseInt(key, 10)] = data.d[key];
  }
}
var newHtml = buildHtml(statics, dynamics);
applyUpdate(el, newHtml);      // morphdom patches the DOM
```

### Backward Compatibility

If a LiveView's `render/1` returns a plain string (not `%Rendered{}`), the engine wraps it as a single dynamic — exactly like before.

**Update `lib/ignite/live_view/handler.ex`** — add a `normalize` clause for plain strings:

```elixir
defp normalize(html) when is_binary(html) do
  {["", ""], [html]}
end
```

This means existing LiveViews (like RegistrationLive with conditional branches) keep working without changes.

## Using It

### Convert a LiveView to `~L`

Replace `#{}` interpolation with `<%= %>` and add `~L` prefix.

**Update `lib/my_app/live/counter_live.ex`** — switch `render/1` to use the `~L` sigil:

```elixir
defmodule MyApp.CounterLive do
  use Ignite.LiveView

  def mount(_params, _session), do: {:ok, %{count: 0}}

  def handle_event("increment", _params, assigns) do
    {:noreply, %{assigns | count: assigns.count + 1}}
  end

  def render(assigns) do
    ~L"""
    <div id="counter">
      <h1>Live Counter</h1>
      <p><%= assigns.count %></p>
      <button ignite-click="increment">+1</button>
    </div>
    """
  end
end
```

### Local variables work too

Compute values before the sigil, then use them as `<%= %>` expressions:

```elixir
def render(assigns) do
  status = if assigns.online, do: "Online", else: "Offline"

  ~L"""
  <p>Status: <%= status %></p>
  """
end
```

## Testing

Open the browser's DevTools → Network → WS tab to watch the wire protocol.

### Counter (`/counter`)

Mount:
```json
{"s": ["...<p style=\"...\">", "</p>..."], "d": ["0"]}
```
Click increment:
```json
{"d": ["1"]}
```

### Dashboard (`/dashboard`) — best showcase

Mount: 9 statics, 8 dynamics (one per stat card)
```json
{"s": [...9 elements...], "d": ["2m 54s", "159", "60.2", "14.1", "24533", "4", "4", "28"]}
```

Tick updates — only changed stats:
```json
{"d": {"0": "2m 55s", "2": "60.3", "3": "14.2"}}
```

Schedulers (index 6) and OTP release (index 7) never change → never sent.

### Bandwidth savings

| View | Before | After | Savings |
|------|--------|-------|---------|
| Counter click | ~600 bytes | ~15 bytes | 97% |
| Dashboard tick | ~2000 bytes | ~50 bytes | 97% |
| SharedCounter PubSub | ~800 bytes | ~15 bytes | 98% |

## Key Elixir Concepts

- **Custom EEx engines**: EEx is not just a template renderer — it's a framework for building template compilers. By implementing the `EEx.Engine` behaviour, you control what code the template compiles into. The default engine builds strings; ours builds `%Rendered{}` structs.

- **Compile-time vs runtime separation**: Statics are literal strings embedded in the compiled module (zero runtime cost). Dynamics are expressions that run on each `render/1` call. This separation happens during compilation — `render/1` never sees the original template.

- **Sigils as macros**: A sigil like `~L"""..."""` is just syntactic sugar for calling `sigil_L/2`. Since it's a macro, we can do arbitrary compile-time work — in our case, compiling an EEx template with a custom engine.

- **Sparse data structures**: Instead of always sending a list, we send a map with only the changed keys. This is a common pattern in real-time systems — send the diff, not the snapshot.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/live_view/rendered.ex` | **New** — `%Rendered{}` struct for statics/dynamics |
| `lib/ignite/live_view/eex_engine.ex` | **New** — custom EEx engine producing `%Rendered{}` |
| `lib/ignite/live_view.ex` | **Modified** — added `sigil_L` macro |
| `lib/ignite/live_view/engine.ex` | **Modified** — sparse index-by-index diffing |
| `lib/ignite/live_view/handler.ex` | **Modified** — handle `%Rendered{}` and plain string normalization |
| `assets/ignite.js` | **Modified** — sparse dynamic updates on the client |
| `lib/my_app/live/counter_live.ex` | **Modified** — converted to `~L` sigil |
| `lib/my_app/live/dashboard_live.ex` | **Modified** — converted to `~L` sigil |
| `lib/my_app/live/hooks_demo_live.ex` | **Modified** — converted to `~L` sigil |
| `lib/my_app/live/shared_counter_live.ex` | **Modified** — converted to `~L` sigil |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — updated links/references |

## How Phoenix Does It

Phoenix's HEEx engine (`Phoenix.LiveView.Engine`) takes this much further:

- **`~H` sigil** with HTML-aware parsing and validation
- **Nested `%Rendered{}` structs** for components (each component diffs independently)
- **Comprehension tracking** for `for` loops — can append/prepend without re-rendering the whole list
- **Fingerprinting** — statics include a hash so the client can detect template changes
- **Change tracking** on assigns — if you don't touch `@count`, it skips even evaluating that expression

Our `~L` engine covers the core concept: compile-time statics/dynamics separation with sparse wire updates.

---

[← Previous: Step 23 - Scoped Routes](23-scoped-routes.md) | [Next: Step 25 - LiveView Streams →](25-streams.md)

# Step 14: Diffing Engine

## What We're Building

Currently, the server sends the **entire HTML** on every update. If
you have a page with 100 table rows and one number changes, you'd
send all 100 rows again.

The diffing engine splits HTML into:
- **Statics**: Parts that never change (HTML tags, labels, etc.)
- **Dynamics**: Values that change (counters, names, timestamps, etc.)

On mount, the server sends both. On updates, it sends **only dynamics**.
The browser zips them together to reconstruct the full HTML.

## Concepts You'll Learn

### Statics and Dynamics

Consider this template:
```
"<h1>Count: #{count}</h1><p>Hello</p>"
```

Split into:
- Statics: `["<h1>Count: ", "</h1><p>Hello</p>"]`
- Dynamics: `["42"]`

The statics **never change** between renders. Only the `42` changes.
So on updates, we only send `["43"]` instead of the full HTML.

### The Wire Protocol

**Mount message** (first connection):
```json
{"s": ["<h1>Count: ", "</h1><p>Hello</p>"], "d": ["0"]}
```

**Update message** (after event):
```json
{"d": ["1"]}
```

The frontend saves the statics from the first message and reuses them:
```
statics[0] + dynamics[0] + statics[1]
"<h1>Count: " + "1" + "</h1><p>Hello</p>"
```

### Bandwidth Savings

Without diffing: `<h1>Count: 42</h1><p>Hello</p>` = 36 bytes per update
With diffing: `{"d":["42"]}` = 12 bytes per update

For large pages, the savings are dramatic — potentially 90%+ reduction.

### Array Zipping

The JS reconstruction logic zips two arrays:

```javascript
function buildHtml(statics, dynamics) {
  var html = "";
  for (var i = 0; i < statics.length; i++) {
    html += statics[i];
    if (i < dynamics.length) {
      html += dynamics[i];
    }
  }
  return html;
}
```

Statics always has one more element than dynamics (the parts between
and around the dynamic values).

## The Code

### `lib/ignite/live_view/engine.ex` (New)

**Create `lib/ignite/live_view/engine.ex`:**

The engine provides two functions:
- `render/2` — returns `{statics, dynamics}` (used on mount)
- `render_dynamics/2` — returns only dynamics (used on updates)

Our simplified version treats the entire rendered HTML as one dynamic
chunk. A production engine would parse the EEx template at compile time
to track each interpolation point separately.

### Updated Handler

**Replace `lib/ignite/live_view/handler.ex` with:**

```elixir
# Mount: send statics + dynamics
{statics, dynamics} = Engine.render(view_module, assigns)
payload = Jason.encode!(%{s: statics, d: dynamics})

# Update: send only dynamics
dynamics = Engine.render_dynamics(state.view, new_assigns)
payload = Jason.encode!(%{d: dynamics})
```

### Updated `assets/ignite.js`

**Replace `assets/ignite.js` with:**

The JS now:
1. Saves statics from the first message
2. Uses `buildHtml()` to reconstruct HTML from statics + dynamics
3. Works with both mount messages (`{s, d}`) and update messages (`{d}`)

## How It Works

```
Mount:
  Server: {s: ["", ""], d: ["<h1>Count: 0</h1>..."]}
  JS:     statics = ["", ""]
          innerHTML = "" + "<h1>Count: 0</h1>..." + ""

Click +1:
  Server: {d: ["<h1>Count: 1</h1>..."]}
  JS:     innerHTML = "" + "<h1>Count: 1</h1>..." + ""
          (reuses saved statics)
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/counter

3. Open DevTools → Network → WS (WebSocket) tab

4. Look at the messages:
   - First message has both `s` and `d` keys
   - Subsequent messages (after clicks) only have `d`

5. The counter still works exactly the same — the optimization is
   transparent to the user.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/live_view/engine.ex` | **New** |
| `lib/ignite/live_view/handler.ex` | **Modified** |
| `assets/ignite.js` | **Modified** |

## What's Next

Changing a controller file requires restarting the entire server.
In **Step 15**, we'll build a **Hot Code Reloader** — a GenServer
that watches for file changes and recompiles modules on the fly,
without dropping any connections.

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

```
┌───────────────────────────────────────────────────────────────┐
│                    Diffing Architecture                        │
│                                                               │
│  Server                            Browser                    │
│  ┌────────────────────┐            ┌────────────────────┐     │
│  │ Engine.render/2    │            │ ignite.js          │     │
│  │                    │──mount────▶│                    │     │
│  │ {statics, dynamics}│  {s, d}    │ save statics       │     │
│  │                    │            │ zip s+d ──▶ HTML    │     │
│  │                    │            │                    │     │
│  │ Engine             │──update──▶│                    │     │
│  │ .render_dynamics/2 │  {d}       │ reuse statics      │     │
│  │                    │            │ zip s+d ──▶ HTML    │     │
│  └────────────────────┘            └────────────────────┘     │
│                                                               │
│  Mount:   ───── {s: ["<h1>Count: ","</h1>"], d: ["0"]} ────▶ │
│  Update:  ───── {d: ["1"]}  ────────────────────────────────▶ │
│  Update:  ───── {d: ["2"]}  ────────────────────────────────▶ │
│                   ▲                                           │
│                   └── Only the changed values cross the wire  │
└───────────────────────────────────────────────────────────────┘
```

## Concepts You'll Learn

### Statics and Dynamics

Consider this template:
```
"<h1>Count: #{count}</h1><p>Hello</p>"
```

Split into:
- Statics: `["<h1>Count: ", "</h1><p>Hello</p>"]`
- Dynamics: `["42"]`

```
  Template: "<h1>Count: #{count}</h1><p>Hello</p>"
                        ─────────
            ┌───────┐   │dynamic│   ┌──────────────┐
            │static │   └───┬───┘   │   static     │
            │  [0]  │       │       │    [1]       │
            ▼       ▼       ▼       ▼              ▼
           "<h1>Count: "   "42"   "</h1><p>Hello</p>"

  Statics:  [ "<h1>Count: ",        "</h1><p>Hello</p>" ]
  Dynamics: [                 "42"                       ]

  Zip:      statics[0] + dynamics[0] + statics[1]
          = "<h1>Count: "  +  "42"  +  "</h1><p>Hello</p>"
```

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

> **Note:** Our first implementation below is simplified — it wraps the
> entire HTML as a single dynamic value. This means the bandwidth savings
> described above won't kick in yet. What we're building now is the
> **architecture** (statics/dynamics split, separate mount/update messages)
> so that in Step 24 we can drop in a real EEx engine that tracks each
> `<%= expr %>` individually and delivers the full optimization.

### Array Zipping

The JS reconstruction logic zips two arrays:

```javascript
function buildHtml(statics, dynamics) {
  let html = "";
  for (let i = 0; i < statics.length; i++) {
    html += statics[i];
    if (i < dynamics.length) {
      html += dynamics[i];
    }
  }
  return html;
}
```

Statics always has one more element than dynamics. Think of dynamics
as separators — if you have N dynamic values, they divide the template
into N+1 static chunks (before, between, and after the dynamic values).

## The Code

### `lib/ignite/live_view/engine.ex` (New)

**Create `lib/ignite/live_view/engine.ex`:**

```elixir
defmodule Ignite.LiveView.Engine do
  @moduledoc """
  Splits rendered HTML into statics and dynamics for efficient updates.

  Our simplified version treats the entire rendered HTML as one dynamic
  chunk. A production engine would parse EEx templates at compile time
  to track each interpolation separately (we'll do that in Step 24).
  """

  @doc "Renders a view and returns {statics, dynamics} for mount."
  def render(view_module, assigns) do
    # apply/3 calls a function dynamically — we need it because
    # the view module is a variable, not known at compile time.
    html = apply(view_module, :render, [assigns])
    # Wrap entire HTML as a single dynamic value
    {["", ""], [html]}
  end

  @doc "Renders and returns only the dynamics list for updates."
  def render_dynamics(view_module, assigns) do
    html = apply(view_module, :render, [assigns])
    [html]
  end
end
```

The engine provides two functions:
- `render/2` — returns `{statics, dynamics}` (used on mount)
- `render_dynamics/2` — returns only dynamics (used on updates)

The statics `["", ""]` are empty strings that surround the single dynamic value. This is a simplified first version — in Step 24, we'll build a real EEx engine that tracks each `<%= expr %>` separately for fine-grained diffing.

### Updated Handler

**Replace `lib/ignite/live_view/handler.ex` with:**

```elixir
defmodule Ignite.LiveView.Handler do
  @behaviour :cowboy_websocket

  alias Ignite.LiveView.Engine

  require Logger

  @impl true
  def init(req, state) do
    {:cowboy_websocket, req, state}
  end

  # On mount: send statics + dynamics
  @impl true
  def websocket_init(state) do
    view_module = state.view

    # mount/2 receives params (from the URL) and session data.
    # We pass empty maps for now — sessions come in a later step.
    case apply(view_module, :mount, [%{}, %{}]) do
      {:ok, assigns} ->
        {statics, dynamics} = Engine.render(view_module, assigns)
        Logger.info("[LiveView] Mounted #{inspect(view_module)}")
        payload = Jason.encode!(%{s: statics, d: dynamics})
        {:reply, {:text, payload}, %{view: view_module, assigns: assigns}}
    end
  end

  # On event: send only dynamics
  @impl true
  def websocket_handle({:text, json}, state) do
    case Jason.decode!(json) do
      %{"event" => event, "params" => params} ->
        case apply(state.view, :handle_event, [event, params, state.assigns]) do
          {:noreply, new_assigns} ->
            dynamics = Engine.render_dynamics(state.view, new_assigns)
            payload = Jason.encode!(%{d: dynamics})
            {:reply, {:text, payload}, %{state | assigns: new_assigns}}
        end
    end
  end

  @impl true
  def websocket_handle(_frame, state), do: {:ok, state}

  @impl true
  def websocket_info(_msg, state), do: {:ok, state}
end
```

### Updated `assets/ignite.js`

**Replace `assets/ignite.js` with:**

```javascript
(function () {
  "use strict";

  const APP_CONTAINER_ID = "ignite-app";
  let statics = null;   // Saved from first message, reused for every update
  let socket = null;

  // --- Reconstruct HTML from statics + dynamics ---
  function buildHtml(statics, dynamics) {
    let html = "";
    for (let i = 0; i < statics.length; i++) {
      html += statics[i];
      if (i < dynamics.length) {
        html += dynamics[i];
      }
    }
    return html;
  }

  function connect() {
    const container = document.getElementById(APP_CONTAINER_ID);
    if (!container) return;

    const livePath = container.dataset.livePath || "/live";
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";

    socket = new WebSocket(protocol + "//" + location.host + livePath);

    socket.onopen = function () {
      console.log("[Ignite] LiveView connected");
    };

    socket.onmessage = function (event) {
      const data = JSON.parse(event.data);

      // Mount message: save statics
      if (data.s) {
        statics = data.s;
      }

      // Update: use saved statics + new dynamics
      if (data.d && statics) {
        const html = buildHtml(statics, data.d);
        container.innerHTML = html;
      }
    };

    socket.onclose = function () {
      console.log("[Ignite] LiveView disconnected");
    };
  }

  // --- Event delegation ---
  document.addEventListener("click", function (e) {
    let target = e.target;
    while (target && target !== document) {
      const eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();
        const params = {};
        const value = target.getAttribute("ignite-value");
        if (value) params.value = value;
        if (socket && socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify({ event: eventName, params: params }));
        }
        return;
      }
      target = target.parentElement;
    }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", connect);
  } else {
    connect();
  }
})();
```

The JS now:
1. Saves statics from the first message (`data.s`)
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

> With our simplified engine, the entire HTML is still sent as one dynamic
> value. The real per-expression savings arrive in Step 24 when we build
> a custom EEx engine. For now, the important thing is that the
> **statics/dynamics architecture** is in place.

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

---

[← Previous: Step 13 - Frontend JS Glue](13-frontend-glue.md) | [Next: Step 15 - Hot Code Reloader →](15-hot-reloader.md)

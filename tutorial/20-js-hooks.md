# Step 20: JS Hooks — Client-Side JavaScript Interop

LiveView renders everything on the server — but some things **must** happen on the client: copying to clipboard, rendering charts, manipulating canvas, interacting with third-party JS libraries. JS Hooks bridge this gap.

In Phoenix LiveView, these are called `phx-hook`. In Ignite, we use `ignite-hook`.

## The Problem

LiveView controls the DOM from the server. But what if you need to:
- Initialize a chart library (Chart.js, D3) when an element appears
- Clean up intervals/listeners when an element is removed
- Copy text to the clipboard (requires browser Clipboard API)
- Send client-only data (geolocation, local time) to the server

You can't do these from Elixir. You need a way to run JavaScript when DOM elements are created, updated, or removed by the server.

## The Architecture

JS Hooks are plain JavaScript objects with lifecycle callbacks:

```javascript
window.IgniteHooks = {
  MyChart: {
    mounted()   { /* element just appeared in the DOM */ },
    updated()   { /* element was re-rendered by server */ },
    destroyed() { /* element was removed from the DOM */ }
  }
};
```

Inside each callback:
- `this.el` — the DOM element with the `ignite-hook` attribute
- `this.pushEvent(event, params)` — send an event to the server's `handle_event/3`

## Step 1: Attaching a Hook to an Element

In your LiveView's `render/1`, add `id` and `ignite-hook` to an element:

```elixir
def render(assigns) do
  """
  <div id="my-chart" ignite-hook="Chart" data-values="[1,2,3]">
    Loading chart...
  </div>
  """
end
```

Requirements:
- The element **must** have a unique `id` (hooks are tracked by ID)
- The `ignite-hook` value must match a key in `window.IgniteHooks`

## Step 2: The Hook Registry (ignite.js)

**Update `assets/ignite.js`** — add the hook lifecycle system (`createHookInstance`, `mountHooks`, `updateHooks`, `cleanupHooks`, `destroyAllHooks`) and integrate it with `applyUpdate` and `connect`. The key pieces are shown below:

The hook system lives entirely in `assets/ignite.js`. Here's how it works:

### Global Registry

Users register hooks before `ignite.js` loads:

```javascript
window.IgniteHooks = window.IgniteHooks || {};

window.IgniteHooks.Chart = {
  mounted: function() {
    // this.el is the DOM element
    var data = JSON.parse(this.el.dataset.values);
    this._chart = new Chart(this.el, { data: data });
  },
  updated: function() {
    // Server re-rendered — update the chart
    var data = JSON.parse(this.el.dataset.values);
    this._chart.update(data);
  },
  destroyed: function() {
    // Clean up to prevent memory leaks
    this._chart.destroy();
  }
};
```

### Hook Instance Creation

When a hooked element is found in the DOM, Ignite creates an instance:

```javascript
function createHookInstance(hookDef, el) {
  var instance = Object.create(hookDef);
  instance.el = el;
  instance.pushEvent = function(event, params) {
    sendEvent(event, params || {});
  };
  return instance;
}
```

`Object.create(hookDef)` creates a new object that inherits from the hook definition. This way each instance has its own `el` and `pushEvent` but shares the callback implementations.

### Lifecycle Integration with morphdom

After every DOM update (mount or event response), Ignite runs three phases:

1. **Cleanup** — Find hooks whose elements no longer exist → call `destroyed()`
2. **Mount** — Find new `[ignite-hook]` elements → call `mounted()`
3. **Update** — Find existing hooks whose elements were re-rendered → call `updated()`

```javascript
function applyUpdate(container, newHtml) {
  // ... morphdom patches the DOM ...

  cleanupHooks(container);  // destroyed() on removed elements
  mountHooks(container);    // mounted() on new elements
  updateHooks(container);   // updated() on existing elements
}
```

### Navigation Cleanup

When navigating between LiveViews, all hooks are destroyed:

```javascript
function connect(livePath) {
  destroyAllHooks();  // Call destroyed() on everything
  // ... close old WS, open new one ...
}
```

## Step 3: `pushEvent` — Sending Data from JS to Elixir

The most powerful feature of hooks is `pushEvent`. It sends an event over the existing WebSocket to the server's `handle_event/3`:

```javascript
// In a hook
this.pushEvent("clipboard_result", { success: "true" });
```

On the server:
```elixir
def handle_event("clipboard_result", %{"success" => "true"}, assigns) do
  {:noreply, %{assigns | copied: true}}
end
```

This lets you send client-only data (clipboard results, geolocation, screen size, local time) to the server.

## Step 4: Example Hooks

**Create `assets/hooks.js`** with the following hook definitions:

### CopyToClipboard

Uses the browser's Clipboard API and reports success/failure to the server:

```javascript
window.IgniteHooks.CopyToClipboard = {
  mounted: function() {
    var self = this;
    var btn = this.el.querySelector("#copy-btn");

    this._handler = function() {
      var text = self.el.getAttribute("data-text");
      navigator.clipboard.writeText(text)
        .then(function() {
          self.pushEvent("clipboard_result", { success: "true" });
        })
        .catch(function() {
          self.pushEvent("clipboard_result", { success: "false" });
        });
    };

    btn.addEventListener("click", this._handler);
  },
  destroyed: function() {
    // Cleanup handled by DOM removal
  }
};
```

### LocalTime

Shows the client's local time (which the server doesn't know) and lets the user push it to the server:

```javascript
window.IgniteHooks.LocalTime = {
  mounted: function() {
    var self = this;
    var display = this.el.querySelector("#local-time-display");

    // Update every second — this runs purely on the client
    this._interval = setInterval(function() {
      display.textContent = new Date().toLocaleTimeString();
    }, 1000);

    // Button sends client time to server
    var btn = this.el.querySelector("#send-time-btn");
    btn.addEventListener("click", function() {
      self.pushEvent("local_time", { time: new Date().toLocaleTimeString() });
    });
  },
  destroyed: function() {
    // CRITICAL: clean up interval to prevent memory leaks
    clearInterval(this._interval);
  }
};
```

## Step 5: The Server Side

**Create `lib/my_app/live/hooks_demo_live.ex`:**

The server doesn't need any special code for hooks. Events pushed via `pushEvent` arrive at `handle_event/3` like any other event:

```elixir
defmodule MyApp.HooksDemoLive do
  use Ignite.LiveView

  def mount(_params, _session) do
    {:ok, %{hook_events: []}}
  end

  def handle_event("clipboard_result", params, assigns) do
    status = if params["success"] == "true", do: "copied", else: "failed"
    event = "Clipboard: #{status}"
    {:noreply, %{assigns | hook_events: [event | assigns.hook_events]}}
  end

  def handle_event("local_time", params, assigns) do
    event = "Client time: #{params["time"]}"
    {:noreply, %{assigns | hook_events: [event | assigns.hook_events]}}
  end
end
```

## How It All Fits Together

```
1. Server renders HTML with ignite-hook="CopyToClipboard"
   ↓
2. morphdom patches DOM → new [ignite-hook] element detected
   ↓
3. ignite.js creates hook instance, calls mounted()
   ↓
4. User clicks "Copy" → clipboard JS runs (client-only)
   ↓
5. Hook calls this.pushEvent("clipboard_result", {success: "true"})
   ↓
6. WebSocket sends event to server
   ↓
7. handle_event("clipboard_result", ...) updates assigns
   ↓
8. Server re-renders → morphdom patches DOM
   ↓
9. ignite.js calls updated() on the hook (element reference refreshed)
```

## Key Design Decisions

### Why hooks need unique IDs
Hooks are tracked in a `mountedHooks` map keyed by element ID. This lets us:
- Detect when an element was removed (its ID is no longer in the DOM)
- Avoid double-mounting the same element
- Update the `this.el` reference after morphdom replaces the element

### Why `destroyed()` matters
Without cleanup, you'd leak memory on every navigation. If a hook starts a `setInterval`, a `MutationObserver`, or attaches event listeners, `destroyed()` is where you clean them up.

### Why hooks don't have component namespacing
Unlike component events, hook events are **not** auto-prefixed. Hooks are a direct channel from client JS to the server — the hook author controls the event names explicitly via `pushEvent`.

## Try It

```bash
mix compile
iex -S mix
# Visit http://localhost:4000/hooks
```

- Click "Copy" — text is copied to clipboard, server receives confirmation
- Watch the local time update every second (pure client-side)
- Click "Send to Server" — client's local time is pushed to the server
- Check the Hook Events Log for pushEvent messages
- Open browser console to see `[Hook] mounted/updated/destroyed` logs
- Navigate to another LiveView — hooks are destroyed and cleaned up

## File Checklist

| File | Status |
|------|--------|
| `assets/hooks.js` | **New** — CopyToClipboard and LocalTime hook definitions |
| `assets/ignite.js` | **Modified** — added hook lifecycle system (mount, update, cleanup, destroy) |
| `lib/my_app/live/hooks_demo_live.ex` | **New** |
| `templates/live.html.eex` | **Modified** — added `<script>` tag to load `hooks.js` |

## What's Next?

Congratulations! You've built a complete web framework with:
- TCP sockets → Cowboy adapter
- Macro-based routing → EEx templates → Middleware
- LiveView → WebSocket → Diffing → Morphdom
- PubSub → LiveView Navigation → LiveComponents → JS Hooks

The framework is now feature-comparable to a simplified Phoenix LiveView. See the README roadmap for ideas on what to add next (CSRF, Ecto, clustering, etc.).

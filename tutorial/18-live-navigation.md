# Step 18: LiveView Navigation — SPA-like Page Transitions

Currently, clicking a link between LiveViews (e.g. from `/counter` to `/dashboard`) causes a full page reload — the browser fetches new HTML, re-loads JavaScript, and opens a brand new WebSocket. This is slow and breaks the illusion of a single-page app.

In this step, we add **client-side LiveView navigation** — the browser swaps WebSocket connections without reloading the page.

## What You'll Learn

- `history.pushState` and `popstate` for client-side routing
- Managing WebSocket connection lifecycle
- Server-to-client redirect protocol
- The `ignite-navigate` attribute for link clicks

## What We're Building

```
┌─────────────────────────────────────────────────────────┐
│  Browser                                                │
│                                                         │
│  /counter ──click──▶ /dashboard ──click──▶ /shared-ctr  │
│     │          no          │          no          │      │
│     │        reload        │        reload        │      │
│     ▼                      ▼                      ▼      │
│  ┌────────┐          ┌──────────┐          ┌─────────┐  │
│  │ WS to  │  close   │  WS to   │  close   │ WS to   │  │
│  │ /live  │──────▶   │/live/    │──────▶   │/live/   │  │
│  │        │  open    │dashboard │  open    │shared-  │  │
│  └────────┘          └──────────┘          │counter  │  │
│                                            └─────────┘  │
│  history: [/counter] ──▶ [/counter, /dashboard] ──▶ ... │
│           pushState       pushState                     │
└─────────────────────────────────────────────────────────┘
```

## How It Works

### Client-Side Navigation (`ignite-navigate`)

```html
<a href="/dashboard" ignite-navigate="/dashboard">Dashboard</a>
```

When a user clicks this link:
1. `ignite.js` intercepts the click (sees `ignite-navigate` attribute)
2. Looks up `/dashboard` in the route map → finds live_path `/live/dashboard`
3. Closes the current WebSocket
4. Resets statics (new view has different HTML structure)
5. Opens a new WebSocket to `/live/dashboard`
6. Calls `history.pushState` to update the browser URL
7. Server mounts the new LiveView, sends statics + dynamics
8. morphdom patches the DOM — page transitions instantly

```
  User clicks <a ignite-navigate="/dashboard">
         │
         ▼
  ┌──────────────┐     ┌─────────────────┐
  │  ignite.js   │────▶│  Route Map      │
  │  intercepts  │     │  /dashboard     │
  │  click       │     │   → /live/      │
  └──────┬───────┘     │     dashboard   │
         │             └─────────────────┘
         ▼
  ┌──────────────┐
  │ Close old WS │
  │ Reset statics│
  └──────┬───────┘
         │
    ┌────┴────┐
    ▼         ▼
 pushState  Open new WS
 (/dashboard)  (/live/dashboard)
    │         │
    │         ▼
    │    ┌──────────────┐
    │    │ Server mounts│
    │    │ DashboardLive│
    │    │ sends statics│
    │    │ + dynamics   │
    │    └──────┬───────┘
    │           ▼
    │    ┌──────────────┐
    └───▶│ morphdom     │
         │ patches DOM  │
         └──────────────┘
```

The `href` attribute is a fallback for when JavaScript is disabled.

### Server-Initiated Navigation (`push_redirect`)

```
  Server (Elixir)                    Client (JS)
  ┌──────────────────┐               ┌──────────────┐
  │ handle_event     │               │              │
  │  push_redirect   │               │              │
  │  sets __redirect_│               │              │
  └────────┬─────────┘               │              │
           │                         │              │
           │  {redirect:             │              │
           │   {url: "/dashboard"}}  │              │
           ├────────────────────────▶│  navigate()  │
           │                         │  same as     │
           │                         │  link click  │
           │                         └──────────────┘
```

A LiveView can also trigger navigation from the server:

```elixir
def handle_event("go_dashboard", _params, assigns) do
  {:noreply, push_redirect(assigns, "/dashboard")}
end
```

This sets a `__redirect__` key on assigns. The handler detects it and sends:
```json
{"redirect": {"url": "/dashboard"}}
```

The client receives this message and navigates the same way.

### The Browser History API

`history.pushState(state, title, url)` changes the browser's URL bar and adds an entry to the back/forward history — **without reloading the page**. `history.replaceState` does the same but *replaces* the current entry instead of adding a new one.

We use `replaceState` on initial load (so the first page has state attached) and `pushState` on navigation (so each page gets its own history entry):

```javascript
// Initial load — attach state to the current URL
history.replaceState({ url: "/counter", livePath: "/live" }, "", "/counter");

// Navigation — add new entry
history.pushState({ url: "/dashboard", livePath: "/live/dashboard" }, "", "/dashboard");
```

### Browser Back/Forward (`popstate`)

The browser fires a `popstate` event when the user clicks Back or Forward. The `event.state` object contains whatever we stored with `pushState` — in our case, the `livePath`. We use it to reconnect to the correct LiveView:

```javascript
window.addEventListener("popstate", function (e) {
  if (e.state && e.state.livePath) {
    connect(e.state.livePath);  // Reconnect to the previous LiveView
  }
});
```

## The Route Map

The route map tells the client which WebSocket path corresponds to each HTTP path:

```json
{
  "/counter": "/live",
  "/register": "/live/register",
  "/dashboard": "/live/dashboard",
  "/shared-counter": "/live/shared-counter"
}
```

This is injected as a `data-live-routes` attribute on the `#ignite-app` div by the controller. The JS parses it on startup to know where each page's WebSocket lives.

## Elixir Concepts

### `Map.pop/3` — Remove and Return

```elixir
{value, remaining_map} = Map.pop(map, :key, default)
```

Removes a key from a map and returns **both** the removed value and the map without that key, as a two-element tuple. The third argument is the default if the key doesn't exist. We use this to extract `__redirect__` from assigns after `handle_event`:

```elixir
{nil, assigns}           = Map.pop(%{count: 1}, :__redirect__)
{%{url: "/"}, assigns}   = Map.pop(%{count: 1, __redirect__: %{url: "/"}}, :__redirect__)
```

## Key Code Changes

### `assets/ignite.js`

**Replace `assets/ignite.js`** with the full updated file. This refactors the inline WebSocket setup into a `connect(livePath)` function, adds `navigate(url, livePath)`, intercepts `ignite-navigate` link clicks, and handles browser back/forward via `popstate`:

```javascript
/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * Uses morphdom for efficient DOM patching:
 * - Instead of replacing innerHTML (which destroys focus, animations, etc.),
 *   morphdom compares the old and new HTML and only updates what changed.
 *
 * Protocol:
 * - On mount: server sends {s: [...statics], d: [...dynamics]}
 * - On update: server sends {d: [...dynamics]}
 * - On redirect: server sends {redirect: {live_path: "/live/x", url: "/x"}}
 * - JS zips statics + dynamics, then morphdom patches the DOM
 *
 * Supported attributes:
 * - ignite-click="event"    — sends event on click
 * - ignite-change="event"   — sends event on input change (with field name + value)
 * - ignite-submit="event"   — sends event on form submit (with all form fields)
 * - ignite-value="val"      — optional static value sent with click events
 * - ignite-navigate="/path" — client-side LiveView navigation (no full page reload)
 */

(function () {
  "use strict";

  // --- Configuration ---
  const APP_CONTAINER_ID = "ignite-app";

  // Statics are saved from the first message and reused for every update
  let statics = null;

  // Current WebSocket connection
  let socket = null;

  // Route mapping: HTTP path → WebSocket live_path (injected by server)
  let liveRoutes = {};

  // --- Initialize ---
  const appContainer = document.getElementById(APP_CONTAINER_ID);
  if (!appContainer) return;

  // Read route mapping from data attribute
  try {
    const routesJson = appContainer.dataset.liveRoutes;
    if (routesJson) {
      liveRoutes = JSON.parse(routesJson);
    }
  } catch (e) {
    // ignore parse errors
  }

  // --- Helper: send event over WebSocket ---
  function sendEvent(event, params) {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ event: event, params: params }));
    }
  }

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

  // --- Apply update to DOM ---
  // Uses morphdom if available, falls back to innerHTML
  function applyUpdate(container, newHtml) {
    if (typeof morphdom === "function") {
      // Create a temporary wrapper to morph into
      const wrapper = document.createElement("div");
      wrapper.id = APP_CONTAINER_ID;
      // Preserve data attributes
      if (container.dataset.livePath) {
        wrapper.dataset.livePath = container.dataset.livePath;
      }
      if (container.dataset.liveRoutes) {
        wrapper.dataset.liveRoutes = container.dataset.liveRoutes;
      }
      wrapper.innerHTML = newHtml;

      morphdom(container, wrapper, {
        // Preserve focused input elements
        onBeforeElUpdated: function (fromEl, toEl) {
          // Skip file inputs — browsers don't allow setting their value
          if (fromEl.type === "file") return false;
          // Don't overwrite value if user is actively typing
          if (fromEl === document.activeElement) {
            if (fromEl.tagName === "INPUT" || fromEl.tagName === "TEXTAREA") {
              toEl.value = fromEl.value;
            }
          }
          return true;
        },
      });
    } else {
      // Fallback: replace entire content
      container.innerHTML = newHtml;
    }
  }

  // --- WebSocket connection management ---
  function connect(livePath) {
    // Close existing connection.
    // We null out onclose before calling close() so the intentional
    // disconnect (during navigation) doesn't trigger the
    // "LiveView disconnected" console log.
    if (socket) {
      socket.onclose = null;
      socket.close();
    }

    // Reset statics for new view
    statics = null;

    // Show a brief loading state while the new WebSocket connects.
    // In a production framework, you'd add a loading indicator or keep
    // the old view visible until the new one is ready.
    const container = document.getElementById(APP_CONTAINER_ID);
    if (container) {
      container.innerHTML = "Connecting...";
      container.dataset.livePath = livePath;
    }

    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    socket = new WebSocket(protocol + "//" + window.location.host + livePath);

    socket.onmessage = function (event) {
      const data = JSON.parse(event.data);
      const el = document.getElementById(APP_CONTAINER_ID);
      if (!el) return;

      // Handle server-initiated navigation
      if (data.redirect) {
        navigate(data.redirect.url, data.redirect.live_path);
        return;
      }

      // First message includes statics — save them
      if (data.s) {
        statics = data.s;
      }

      // Apply dynamics update
      if (statics && data.d) {
        const newHtml = buildHtml(statics, data.d);
        applyUpdate(el, newHtml);
      }
    };

    socket.onopen = function () {
      console.log(
        "[Ignite] LiveView connected to " +
          livePath +
          " (morphdom: " +
          (typeof morphdom === "function") +
          ")"
      );
    };

    socket.onclose = function () {
      console.log("[Ignite] LiveView disconnected");
    };

    socket.onerror = function (err) {
      console.error("[Ignite] WebSocket error:", err);
    };
  }

  // --- LiveView Navigation ---
  // Navigate to a new LiveView without full page reload
  function navigate(url, livePath) {
    // Resolve live_path from route mapping if not provided
    if (!livePath && liveRoutes[url]) {
      livePath = liveRoutes[url];
    }

    if (!livePath) {
      // Fallback: full page navigation for non-LiveView routes
      window.location.href = url;
      return;
    }

    // Update browser URL without reload
    history.pushState({ url: url, livePath: livePath }, "", url);

    // Connect to the new LiveView
    connect(livePath);
  }

  // --- Browser back/forward navigation ---
  window.addEventListener("popstate", function (e) {
    if (e.state && e.state.livePath) {
      connect(e.state.livePath);
    } else {
      // No state — full page reload
      window.location.reload();
    }
  });

  // --- Set initial history state ---
  const initialLivePath =
    (appContainer && appContainer.dataset.livePath) || "/live";
  history.replaceState(
    { url: window.location.pathname, livePath: initialLivePath },
    "",
    window.location.pathname
  );

  // --- Send click events to server ---
  document.addEventListener("click", function (e) {
    let target = e.target;

    while (target && target !== document) {
      // Check for navigation links first
      const navPath = target.getAttribute("ignite-navigate");
      if (navPath) {
        e.preventDefault();
        navigate(navPath);
        return;
      }

      // Check for click events
      const eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();

        const params = {};
        const value = target.getAttribute("ignite-value");
        if (value) {
          params.value = value;
        }

        sendEvent(eventName, params);
        return;
      }
      target = target.parentElement;
    }
  });

  // --- Send input change events to server ---
  document.addEventListener("input", function (e) {
    const target = e.target;

    // Walk up to find ignite-change (could be on the input or a parent)
    let el = target;
    while (el && el !== document) {
      const eventName = el.getAttribute("ignite-change");
      if (eventName) {
        const params = {
          field: target.getAttribute("name") || "",
          value: target.value,
        };
        sendEvent(eventName, params);
        return;
      }
      el = el.parentElement;
    }
  });

  // --- Send form submit events to server ---
  document.addEventListener("submit", function (e) {
    const form = e.target;
    if (!form || !form.getAttribute) return;

    const eventName = form.getAttribute("ignite-submit");
    if (eventName) {
      e.preventDefault();

      // Collect all form fields
      const params = {};
      const formData = new FormData(form);
      formData.forEach(function (value, key) {
        params[key] = value;
      });

      sendEvent(eventName, params);
    }
  });

  // --- Initial connection ---
  connect(initialLivePath);
})();
```

### `lib/ignite/live_view.ex`

**Update `lib/ignite/live_view.ex`** — add the `push_redirect/2` function and import it in `__using__/1`:

```elixir
def push_redirect(assigns, url) do
  Map.put(assigns, :__redirect__, %{url: url})
end
```

Update the `__using__/1` macro to import `push_redirect`:

```elixir
defmacro __using__(_opts) do
  quote do
    @behaviour Ignite.LiveView
    import Ignite.LiveView, only: [push_redirect: 2]
  end
end
```

### `lib/ignite/live_view/handler.ex`

**Update `lib/ignite/live_view/handler.ex`** — after `handle_event`, check for `__redirect__` in assigns and send a redirect message instead of a render update:

```elixir
case apply(state.view, :handle_event, [event, params, state.assigns]) do
  {:noreply, new_assigns} ->
    case Map.pop(new_assigns, :__redirect__) do
      {nil, assigns} ->
        # Normal render update
        dynamics = Engine.render_dynamics(state.view, assigns)
        payload = Jason.encode!(%{d: dynamics})
        {:reply, {:text, payload}, %{state | assigns: assigns}}

      {redirect_info, assigns} ->
        # Send redirect to client
        payload = Jason.encode!(%{redirect: redirect_info})
        {:reply, {:text, payload}, %{state | assigns: assigns}}
    end
end
```

### `templates/live.html.eex`

**Update `templates/live.html.eex`** — add `data-live-routes` to the container div:

```html
<div id="ignite-app"
     data-live-path="<%= @live_path || "/live" %>"
     data-live-routes='<%= @live_routes || "{}" %>'>
  Connecting...
</div>
```

### `lib/my_app/controllers/welcome_controller.ex`

**Update all LiveView controller actions** — pass the `live_routes` map so the JS knows which paths map to which WebSocket endpoints:

```elixir
# Module attribute — computed once at compile time.
# Jason.encode! converts the map to a JSON string that gets
# embedded in every LiveView HTML response.
@live_routes Jason.encode!(%{
  "/counter" => "/live",
  "/dashboard" => "/live/dashboard",
  "/shared-counter" => "/live/shared-counter"
})

def counter(conn) do
  render(conn, "live", title: "Live Counter — Ignite", live_routes: @live_routes)
end

def dashboard(conn) do
  render(conn, "live", title: "Dashboard — Ignite", live_path: "/live/dashboard", live_routes: @live_routes)
end
```

### `lib/my_app/live/counter_live.ex`

**Update `lib/my_app/live/counter_live.ex`** — add navigation links to the render function. The `ignite-navigate` attribute tells the JS to handle the click client-side, while the `href` is a fallback for when JS is disabled:

```elixir
def render(assigns) do
  """
  <div id="counter">
    <h1>Live Counter</h1>
    <p style="font-size: 3em; margin: 20px 0;">#{assigns.count}</p>
    <button ignite-click="decrement" style="font-size: 1.5em; padding: 10px 20px;">-</button>
    <button ignite-click="increment" style="font-size: 1.5em; padding: 10px 20px;">+</button>

    <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee;">
      <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
      <a href="/" style="margin: 0 8px;">Home</a>
      <a href="/dashboard" ignite-navigate="/dashboard" style="margin: 0 8px;">Dashboard</a>
      <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin: 0 8px;">Shared Counter</a>
    </div>
  </div>
  """
end
```

### `lib/my_app/live/dashboard_live.ex`

**Update `lib/my_app/live/dashboard_live.ex`** — add the same navigation links at the bottom of the render function:

```elixir
def render(assigns) do
  """
  <div id="dashboard" style="max-width: 600px; margin: 0 auto; text-align: left;">
    <h1>BEAM Dashboard</h1>
    <p style="color: #888; font-size: 14px;">Auto-refreshes every second</p>

    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 20px 0;">
      <!-- ... stat cards ... -->
    </div>

    <button ignite-click="gc" style="padding: 8px 16px; background: #e74c3c; color: white; border: none; border-radius: 4px; cursor: pointer;">
      Run GC
    </button>

    <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #eee; text-align: center;">
      <p style="color: #888; font-size: 14px;">Navigate without page reload:</p>
      <a href="/" style="margin: 0 8px;">Home</a>
      <a href="/counter" ignite-navigate="/counter" style="margin: 0 8px;">Counter</a>
      <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin: 0 8px;">Shared Counter</a>
    </div>
  </div>
  """
end
```

The Home link (`<a href="/">`) has no `ignite-navigate` attribute — it's a regular link that triggers a full page load, since the home page isn't a LiveView.

## File Checklist

| File | Status |
|------|--------|
| `assets/ignite.js` | **Modified** — added `connect()`, `navigate()`, route-map parsing, `popstate` handler |
| `lib/ignite/live_view.ex` | **Modified** — added `push_redirect/2`, updated `__using__/1` imports |
| `lib/ignite/live_view/handler.ex` | **Modified** — added redirect detection after `handle_event` |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — inject `data-live-routes` route map into LiveView HTML |
| `lib/my_app/live/counter_live.ex` | **Modified** — added navigation links to render |
| `lib/my_app/live/dashboard_live.ex` | **Modified** — added navigation links to render |
| `templates/live.html.eex` | **Modified** — added `data-live-routes` attribute to `#ignite-app` div |

## Try It

1. Start the server: `iex -S mix`
2. Visit http://localhost:4000/counter
3. Click "Dashboard" link at the bottom
4. URL changes to `/dashboard` — **no page reload!**
5. Dashboard auto-refreshes every second
6. Click browser Back button → returns to counter instantly
7. Counter still works

## What's Next

Our LiveViews are now full single-page apps with instant navigation. But
each LiveView is a monolith — the entire page is one module. What if you
want a reusable widget (like a toggle button or a tab bar) that manages
its own state?

In **Step 19**, we'll build **LiveComponents** — reusable stateful
widgets that live inside a parent LiveView, with their own `mount`,
`handle_event`, and `render` callbacks.

---

[← Previous: Step 17 - PubSub — Real-Time Broadcasting Between LiveViews](17-pubsub.md) | [Next: Step 19 - LiveComponents — Reusable Stateful Widgets →](19-live-components.md)

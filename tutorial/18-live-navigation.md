# Step 18: LiveView Navigation — SPA-like Page Transitions

Currently, clicking a link between LiveViews (e.g. from `/counter` to `/dashboard`) causes a full page reload — the browser fetches new HTML, re-loads JavaScript, and opens a brand new WebSocket. This is slow and breaks the illusion of a single-page app.

In this step, we add **client-side LiveView navigation** — the browser swaps WebSocket connections without reloading the page.

## What You'll Learn

- `history.pushState` and `popstate` for client-side routing
- Managing WebSocket connection lifecycle
- Server-to-client redirect protocol
- The `ignite-navigate` attribute for link clicks

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

The `href` attribute is a fallback for when JavaScript is disabled.

### Server-Initiated Navigation (`push_redirect`)

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

### Browser Back/Forward

We use `history.replaceState` on initial load and `history.pushState` on navigation to store the `livePath` in the history state. The `popstate` listener reconnects to the correct LiveView when the user hits Back or Forward.

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

This is injected as a `data-live-routes` attribute on the `#ignite-app` div by the controller.

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

**Update `assets/ignite.js`** — refactor the WebSocket logic into a `connect(livePath)` function, add `navigate(url, livePath)`, and intercept `ignite-navigate` link clicks:

```javascript
// Route mapping: HTTP path → WebSocket live_path (injected by server)
var liveRoutes = {};

function connect(livePath) {
  // Close existing connection
  if (socket) {
    socket.onclose = null;  // prevent disconnect log
    socket.close();
  }
  statics = null;  // New view has different statics

  var protocol = location.protocol === "https:" ? "wss:" : "ws:";
  socket = new WebSocket(protocol + "//" + location.host + livePath);

  socket.onopen = function () {
    console.log("[Ignite] LiveView connected to " + livePath);
  };

  socket.onmessage = function (event) {
    var el = document.getElementById(APP_CONTAINER_ID);
    var data = JSON.parse(event.data);

    // Handle server-initiated redirect
    if (data.redirect) {
      var url = data.redirect.url;
      var targetPath = data.redirect.live_path || liveRoutes[url];
      if (targetPath) {
        navigate(url, targetPath);
      }
      return;
    }

    if (data.s) statics = data.s;
    if (data.d && statics) {
      var html = buildHtml(statics, data.d);
      applyUpdate(el, html);
    }
  };

  socket.onclose = function () {
    console.log("[Ignite] LiveView disconnected");
  };
}

function navigate(url, livePath) {
  if (!livePath) livePath = liveRoutes[url];
  if (!livePath) return;
  history.pushState({ url: url, livePath: livePath }, "", url);
  connect(livePath);
}
```

Add `ignite-navigate` click interception to the event delegation handler:

```javascript
document.addEventListener("click", function (e) {
  var target = e.target;
  while (target && target !== document) {
    // Check for ignite-navigate first (link navigation)
    var navPath = target.getAttribute("ignite-navigate");
    if (navPath) {
      e.preventDefault();
      navigate(navPath, liveRoutes[navPath]);
      return;
    }
    // ... existing ignite-click handling ...
    target = target.parentElement;
  }
});
```

Add `popstate` handler for browser back/forward:

```javascript
window.addEventListener("popstate", function (e) {
  if (e.state && e.state.livePath) {
    connect(e.state.livePath);
  }
});
```

On initial load, parse the route map from `data-live-routes` and store the initial history state:

```javascript
function init() {
  var container = document.getElementById(APP_CONTAINER_ID);
  if (!container) return;

  // Parse route map from data attribute
  var routeData = container.dataset.liveRoutes;
  if (routeData) {
    try { liveRoutes = JSON.parse(routeData); } catch (e) {}
  }

  var livePath = container.dataset.livePath || "/live";
  // Save initial state for popstate
  history.replaceState({ url: location.pathname, livePath: livePath }, "");
  connect(livePath);
}
```

### `lib/ignite/live_view.ex`

**Update `lib/ignite/live_view.ex`** — add the `push_redirect/2` function:

```elixir
def push_redirect(assigns, url) do
  Map.put(assigns, :__redirect__, %{url: url})
end
```

Also add `push_redirect: 2` to the `import` list in `__using__/1`.

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

## File Checklist

| File | Status |
|------|--------|
| `assets/ignite.js` | **Modified** — added `connect()`, `navigate()`, route-map parsing, `popstate` handler |
| `lib/ignite/live_view.ex` | **Modified** — added `push_redirect/2` |
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

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

**Update `assets/ignite.js`** — refactor the WebSocket logic into a `connect(livePath)` function and add a `navigate(url, livePath)` function. Add click interception for `ignite-navigate` links, `popstate` handling, and route-map parsing from `data-live-routes`:

```javascript
function connect(livePath) {
  if (socket) { socket.close(); }
  statics = null;
  socket = new WebSocket(protocol + "//" + host + livePath);
  socket.onmessage = function(event) { /* handle messages */ };
}
```

The `navigate(url, livePath)` function orchestrates the transition:

```javascript
function navigate(url, livePath) {
  if (!livePath) livePath = liveRoutes[url];
  history.pushState({url: url, livePath: livePath}, "", url);
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

### `lib/ignite/live_view/handler.ex`

**Update `lib/ignite/live_view/handler.ex`** — after `handle_event`, check for `__redirect__` in assigns and send a redirect message to the client:

```elixir
case Map.pop(new_assigns, :__redirect__) do
  {nil, assigns} -> # normal render
  {redirect_info, assigns} -> # send {redirect: ...} to client
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

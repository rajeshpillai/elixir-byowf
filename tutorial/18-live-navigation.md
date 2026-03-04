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

## Key Code Changes

### `assets/ignite.js`

The WebSocket logic is refactored into a `connect(livePath)` function:

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

Added `push_redirect/2`:

```elixir
def push_redirect(assigns, url) do
  Map.put(assigns, :__redirect__, %{url: url})
end
```

### `lib/ignite/live_view/handler.ex`

After `handle_event`, checks for `__redirect__` in assigns:

```elixir
case Map.pop(new_assigns, :__redirect__) do
  {nil, assigns} -> # normal render
  {redirect_info, assigns} -> # send {redirect: ...} to client
end
```

## Try It

1. Start the server: `iex -S mix`
2. Visit http://localhost:4000/counter
3. Click "Dashboard" link at the bottom
4. URL changes to `/dashboard` — **no page reload!**
5. Dashboard auto-refreshes every second
6. Click browser Back button → returns to counter instantly
7. Counter still works

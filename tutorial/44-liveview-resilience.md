# Step 44: LiveView Resilience — Reconnection, Scoped Events & Status UI

## What We're Building

Our `ignite.js` has grown from a simple WebSocket glue (Step 13) into a
full-featured LiveView client. But it has some rough edges compared to
production frameworks:

1. **No reconnection** — if the server restarts, users stare at a dead page
2. **Document-level listeners** — click/input/submit events fire even outside
   the LiveView container
3. **Non-standard change params** — sends `{field, value}` instead of `{[name]: value}`
4. **No status indicator** — users have no idea if they're connected or not

In this step we fix all four, plus add `ignite-keydown` for keyboard events
and composite upload refs that don't collide.

## Concepts You'll Learn

### Exponential Backoff

When a WebSocket disconnects, reconnecting immediately can overwhelm the
server (especially if many clients reconnect at once after a restart).
Exponential backoff spaces out retries:

```
Attempt 1: wait  200ms
Attempt 2: wait  400ms
Attempt 3: wait  800ms
Attempt 4: wait 1600ms
Attempt 5: wait 3200ms  (capped at MAX_DELAY)
```

On success, the delay resets to the minimum. This is the same strategy
used by Phoenix LiveView, AWS SDKs, and gRPC.

### Container-Scoped Event Delegation

In Step 13 we attached listeners to `document`:

```javascript
document.addEventListener("click", function (e) { ... });
```

This works, but processes clicks on *every* element in the page. If you
embed a LiveView inside a larger page, it intercepts clicks outside the
container. The fix: attach to `appContainer` instead and use
`e.target.closest()` to find the relevant attribute.

### `closest()` vs Manual DOM Walking

The current click handler manually walks up the DOM tree:

```javascript
var target = e.target;
while (target && target !== document) {
  var eventName = target.getAttribute("ignite-click");
  if (eventName) { ... }
  target = target.parentElement;
}
```

`Element.closest(selector)` does the same thing in one call:

```javascript
var target = e.target.closest("[ignite-click]");
if (target) { ... }
```

It's cleaner and supported in all modern browsers.

## The Code

### Part 1: Connection Status UI

We start here because the reconnection logic (Part 2) needs `setStatus`.

**Update `assets/ignite.js`** — add the status element lookup and helper
right after the `APP_CONTAINER_ID` declaration (line 31):

```javascript
// --- Configuration ---
var APP_CONTAINER_ID = "ignite-app";
var statusEl = document.getElementById("ignite-status");

function setStatus(text, className) {
  if (statusEl) {
    statusEl.textContent = text;
    statusEl.className = "status " + (className || "");
  }
}
```

**Update `templates/live.html.eex`** — add a status element before the
app container:

```html
<p class="status" id="ignite-status"></p>
<div id="ignite-app" data-live-path="<%= @live_path || "/live" %>" ...>Connecting...</div>
```

Add basic status styles in the `<style>` block:

```css
.status { font-size: 12px; color: #888; min-height: 18px; }
.status.connected { color: #27ae60; }
.status.disconnected { color: #e74c3c; }
```

### Part 2: Automatic Reconnection

**Update `assets/ignite.js`** — add reconnection state near the top
variables:

```javascript
var reconnectDelay = 200;
var MAX_DELAY = 5000;
var reconnectTimer = null;
var navigating = false;
```

Add the `scheduleReconnect` function:

```javascript
function scheduleReconnect() {
  if (reconnectTimer) return;
  var container = document.getElementById(APP_CONTAINER_ID);
  var currentPath = (container && container.dataset.livePath) || initialLivePath;
  reconnectTimer = setTimeout(function () {
    reconnectTimer = null;
    connect(currentPath);
    reconnectDelay = Math.min(reconnectDelay * 2, MAX_DELAY);
  }, reconnectDelay);
}
```

Why `container.dataset.livePath` instead of `initialLivePath`? After a live
navigation (e.g., from `/counter` to `/dashboard`), the container's
`data-live-path` reflects the *current* view. Using `initialLivePath` would
reconnect to the landing page, dropping the user out of their current view.

**Update `socket.onopen` (line 557):**

```javascript
socket.onopen = function () {
  reconnectDelay = 200;
  setStatus("Connected", "connected");
  console.log("[Ignite] LiveView connected to " + livePath);
};
```

**Update `socket.onclose` (line 569):**

```javascript
socket.onclose = function () {
  if (navigating) return;
  setStatus("Disconnected — reconnecting...", "disconnected");
  scheduleReconnect();
};
```

**Update `navigate()`** — set the `navigating` flag so intentional
disconnects don't trigger reconnection:

```javascript
function navigate(url, livePath) {
  if (!livePath && liveRoutes[url]) {
    livePath = liveRoutes[url];
  }
  if (!livePath) {
    window.location.href = url;
    return;
  }
  navigating = true;
  history.pushState({ url: url, livePath: livePath }, "", url);
  connect(livePath);
  navigating = false;
}
```

### Part 3: Container-Scoped Event Delegation

**Replace the three `document.addEventListener` blocks** (lines 633–706)
with container-scoped versions using `closest()`:

```javascript
// --- Click events (scoped to container) ---
appContainer.addEventListener("click", function (e) {
  var navTarget = e.target.closest("[ignite-navigate]");
  if (navTarget) {
    e.preventDefault();
    navigate(navTarget.getAttribute("ignite-navigate"));
    return;
  }

  var target = e.target.closest("[ignite-click]");
  if (target) {
    e.preventDefault();
    var params = {};
    var value = target.getAttribute("ignite-value");
    if (value) params.value = value;
    sendEvent(resolveEvent(target.getAttribute("ignite-click"), target), params);
  }
});

// --- Input change events (scoped to container) ---
appContainer.addEventListener("input", function (e) {
  var target = e.target.closest("[ignite-change]");
  if (target) {
    var name = e.target.getAttribute("name") || "value";
    var params = {};
    params[name] = e.target.value;
    sendEvent(resolveEvent(target.getAttribute("ignite-change"), e.target), params);
  }
});

// --- Form submit events (scoped to container) ---
appContainer.addEventListener("submit", function (e) {
  var form = e.target.closest("[ignite-submit]");
  if (form) {
    e.preventDefault();
    var params = {};
    var formData = new FormData(form);
    formData.forEach(function (value, key) {
      if (!(value instanceof File)) params[key] = value;
    });
    sendEvent(resolveEvent(form.getAttribute("ignite-submit"), form), params);
  }
});
```

Note how the input handler now sends `{ [name]: value }` instead of
`{ field: name, value: value }`. This is Part 4 rolled in — see below for
the required server-side fix.

Keep the drag-and-drop listeners on `document` since drop targets may exist
outside the container.

### Part 4: Fix Server-Side Change Handlers

The new input handler sends `%{"name" => "Alice"}` instead of
`%{"field" => "name", "value" => "Alice"}`. Update any `handle_event`
that pattern-matches the old format.

**Update `lib/my_app/live/registration_live.ex`** — this is the only
handler that uses the old format:

```elixir
# Before:
def handle_event("validate", %{"field" => field, "value" => value}, assigns) do
  assigns = Map.put(assigns, String.to_existing_atom(field), value)
  error = validate_field(field, value)
  # ...
end

# After:
def handle_event("validate", params, assigns) do
  # params is now %{"name" => "Alice"} or %{"email" => "a@b.com"} etc.
  # Extract the single key-value pair
  {field, value} = params |> Map.to_list() |> hd()
  assigns = Map.put(assigns, String.to_existing_atom(field), value)
  error = validate_field(field, value)
  # ...rest unchanged
end
```

### Part 5: Add `ignite-keydown` Binding

Add after the submit listener:

```javascript
// --- Keydown events (scoped to container) ---
appContainer.addEventListener("keydown", function (e) {
  var target = e.target.closest("[ignite-keydown]");
  if (target) {
    var event = resolveEvent(target.getAttribute("ignite-keydown"), e.target);
    var name = e.target.getAttribute("name") || "value";
    var params = { key: e.key };
    params[name] = e.target.value;
    sendEvent(event, params);
  }
});
```

Usage in templates:

```html
<input name="query" ignite-keydown="search" placeholder="Search..." />
```

The server receives `%{"key" => "a", "query" => "Sea"}` — the key that was
pressed plus the current input value.

### Part 6: Composite Upload Refs

Simple index refs (`"0"`, `"1"`) collide when a user selects files in one
upload input, then selects files in another. Fix by including the upload
name and a timestamp.

**Update `initUploadInput`** (line 172) and the drag-and-drop handler
(line 299) — change `var ref = String(i)` to:

```javascript
var ref = uploadName + "-" + i + "-" + Date.now();
```

## How It Works

```
1. Page loads → ignite.js connects to WebSocket
   → Status shows "Connected" (green)

2. Server restarts or network drops
   → socket.onclose fires
   → Status shows "Disconnected — reconnecting..." (red)
   → scheduleReconnect() starts exponential backoff

3. Reconnect succeeds
   → socket.onopen fires
   → reconnectDelay resets to 200ms
   → Status shows "Connected" (green)

4. User navigates (ignite-navigate)
   → navigating = true (suppresses reconnect)
   → Old socket closed, new socket opened
   → navigating = false
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/counter

3. **Test reconnection:** In the IEx shell, press Ctrl+C twice to kill the
   server. Watch the status turn red. Restart with `iex -S mix` — the page
   reconnects automatically.

4. **Test scoped events:** Open DevTools console. Click outside the
   `#ignite-app` container — no events fire. Click inside — events work
   as before.

5. **Test registration form:** Visit http://localhost:4000/register. Type
   in the name field — validation should still work with the new
   `{[name]: value}` format.

## File Checklist

| File | Status | Purpose |
|------|--------|---------|
| `assets/ignite.js` | **Modified** | Reconnection, scoped events, keydown, composite refs |
| `templates/live.html.eex` | **Modified** | Added `#ignite-status` element and styles |
| `lib/my_app/live/registration_live.ex` | **Modified** | Updated `validate` handler for new change params |

---

[← Previous: Step 43 - Todo App](43-todo-app.md)

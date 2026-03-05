# Step 13: Frontend JS Glue

## What We're Building

In Step 12, the JavaScript was inline in the controller — messy and
not reusable. Now we're extracting it into a proper `assets/ignite.js`
file that:

1. Connects to the LiveView WebSocket
2. Listens for `ignite-click` events using **event delegation**
3. Sends events as JSON to the server
4. Updates the DOM with HTML from the server

We'll also serve static files via Cowboy and use a reusable EEx template
for LiveView pages.

## Concepts You'll Learn

### Event Delegation

Instead of attaching a click listener to every button, we attach **one**
listener to the entire document:

```javascript
document.addEventListener("click", function(e) {
  var target = e.target;
  while (target && target !== document) {
    var eventName = target.getAttribute("ignite-click");
    if (eventName) {
      socket.send(JSON.stringify({event: eventName, params: {}}));
      return;
    }
    target = target.parentElement;
  }
});
```

Why delegation?
- Works on elements that don't exist yet (dynamically added by LiveView)
- One listener instead of hundreds
- Walking up the DOM tree catches clicks on child elements (e.g., icon
  inside a button)

### Custom HTML Attributes

We use `ignite-click` as a custom attribute convention:

```html
<button ignite-click="increment">+1</button>
<button ignite-click="decrement" ignite-value="5">-5</button>
```

When clicked, the JS reads the attribute and sends it as the event name.
The optional `ignite-value` passes additional data.

### Static File Serving with Cowboy

Cowboy has a built-in static file handler:

```elixir
{"/assets/[...]", :cowboy_static, {:dir, "assets"}}
```

This serves any file under the `assets/` directory at `/assets/...`.
A request for `/assets/ignite.js` reads `assets/ignite.js` from disk.

### IIFE (Immediately Invoked Function Expression)

The JS is wrapped in an IIFE to avoid polluting the global scope:

```javascript
(function() {
  "use strict";
  // All code here is private
})();
```

## The Code

### `assets/ignite.js`

**Create `assets/ignite.js`:**

```javascript
/**
 * Ignite.js — Frontend glue for Ignite LiveView.
 *
 * Protocol:
 * - On mount: server sends {html: "<div>...</div>"}
 * - On update: server sends {html: "<div>...</div>"}
 * - JS replaces #ignite-app innerHTML with server HTML
 *
 * Supported attributes:
 * - ignite-click="event" — sends event on click
 * - ignite-value="val"   — optional static value sent with click events
 */
(function () {
  "use strict";

  var APP_CONTAINER_ID = "ignite-app";
  var socket = null;

  function connect() {
    var container = document.getElementById(APP_CONTAINER_ID);
    if (!container) return;

    var livePath = container.dataset.livePath || "/live";
    var protocol = location.protocol === "https:" ? "wss:" : "ws:";
    var host = location.host;

    socket = new WebSocket(protocol + "//" + host + livePath);

    socket.onopen = function () {
      console.log("[Ignite] LiveView connected");
    };

    socket.onmessage = function (event) {
      var data = JSON.parse(event.data);
      if (data.html) {
        container.innerHTML = data.html;
      }
    };

    socket.onclose = function () {
      console.log("[Ignite] LiveView disconnected");
    };
  }

  // --- Event delegation ---
  // One listener on the document catches all ignite-click events,
  // even on elements added dynamically by LiveView.
  document.addEventListener("click", function (e) {
    var target = e.target;
    while (target && target !== document) {
      var eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();
        var params = {};
        var value = target.getAttribute("ignite-value");
        if (value) params.value = value;
        if (socket && socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify({ event: eventName, params: params }));
        }
        return;
      }
      target = target.parentElement;
    }
  });

  // Connect when DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", connect);
  } else {
    connect();
  }
})();
```

The complete frontend glue:
- WebSocket connection with automatic `ws:` / `wss:` protocol detection
- Event delegation for `ignite-click` with DOM tree walking
- Optional `ignite-value` for passing data with events
- Connection lifecycle logging

### `templates/live.html.eex`

**Create `templates/live.html.eex`:**

```html
<!DOCTYPE html>
<html>
<head>
  <title><%= @title || "Ignite LiveView" %></title>
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      text-align: center;
      margin-top: 50px;
      color: #333;
    }
    button { cursor: pointer; margin: 5px; }
    #ignite-app { min-height: 100px; }
  </style>
</head>
<body>
  <div id="ignite-app" data-live-path="<%= @live_path || "/live" %>">Connecting...</div>
  <hr>
  <p><small>Powered by <a href="/">Ignite</a></small></p>
  <script src="/assets/ignite.js"></script>
</body>
</html>
```

A reusable template for LiveView pages:
- Contains `#ignite-app` container div with a `data-live-path` attribute
- Loads `ignite.js` via `<script src="/assets/ignite.js">`
- Accepts `title` and `live_path` assigns

### Updated Application

**Update `lib/ignite/application.ex`** — add a static file route for `/assets/[...]` to the Cowboy dispatch rules:

```elixir
dispatch =
  :cowboy_router.compile([
    {:_,
     [
       {"/live", Ignite.LiveView.Handler, %{view: MyApp.CounterLive}},
       {"/assets/[...]", :cowboy_static, {:dir, "assets"}},
       {"/[...]", Ignite.Adapters.Cowboy, []}
     ]}
  ])
```

Note: the `/assets/[...]` route must come **before** the `"/[...]"` catch-all, otherwise Cowboy would never match it.

### Updated Controller

**Update `lib/my_app/controllers/welcome_controller.ex`** — replace the inline-JS `counter` action with:

```elixir
def counter(conn) do
  render(conn, "live", title: "Live Counter — Ignite")
end
```

The inline JavaScript from Step 12 is replaced by the external `ignite.js` file.

## How It Works

```
1. GET /counter
   → Server renders templates/live.html.eex
   → Browser loads the page
   → Browser fetches /assets/ignite.js

2. ignite.js opens WebSocket to /live
   → Server sends initial HTML: {html: "<div>Count: 0...</div>"}
   → JS puts it in #ignite-app

3. User clicks <button ignite-click="increment">
   → JS catches click via document listener
   → Walks DOM tree, finds ignite-click="increment"
   → Sends: {event: "increment", params: {}}

4. Server processes event, re-renders
   → Sends: {html: "<div>Count: 1...</div>"}
   → JS updates #ignite-app
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/counter

3. Click the buttons — same live counter, but now powered by the
   external `ignite.js` file.

4. Open DevTools (F12) → Network tab. You should see:
   - `/counter` — the HTML page
   - `/assets/ignite.js` — the JS file
   - `/live` — the WebSocket connection (type: "websocket")

5. In the Console tab, you'll see:
   ```
   [Ignite] LiveView connected
   ```

## File Checklist

| File | Status |
|------|--------|
| `assets/ignite.js` | **New** |
| `templates/live.html.eex` | **New** |
| `lib/ignite/application.ex` | **Modified** |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** |

## What's Next

Currently, the server sends the **entire HTML** every time something
changes. If you had a large page and only one number changed, you'd
still be sending kilobytes of HTML.

In **Step 14**, we'll build a **Diffing Engine** that splits templates
into "statics" (HTML that never changes) and "dynamics" (values that do).
The server will only send the changed values, reducing bandwidth by 90%.

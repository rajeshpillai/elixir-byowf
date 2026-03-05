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

The complete frontend glue:
- WebSocket connection with automatic `ws:` / `wss:` protocol detection
- Event delegation for `ignite-click` with DOM tree walking
- Optional `ignite-value` for passing data with events
- Connection lifecycle logging

### `templates/live.html.eex`

**Create `templates/live.html.eex`:**

A reusable template for LiveView pages:
- Contains `#ignite-app` container div
- Loads `ignite.js` via `<script src="/assets/ignite.js">`
- Accepts `title` assign for the page title

### Updated Application

**Update `lib/ignite/application.ex`** — add a static file route for `/assets/[...]` to the Cowboy dispatch rules.

Cowboy routing now includes static file serving:
```elixir
{"/assets/[...]", :cowboy_static, {:dir, "assets"}}
```

### Updated Controller

**Replace `lib/my_app/controllers/welcome_controller.ex` with:**

The counter action is now one line:
```elixir
def counter(conn) do
  render(conn, "live", title: "Live Counter — Ignite")
end
```

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

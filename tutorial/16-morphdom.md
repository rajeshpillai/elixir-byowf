# Step 16: Morphdom Integration

## What We're Building

Our LiveView currently uses `innerHTML` to update the page. This has
a major problem: it **destroys and recreates** all DOM elements, which:

- Loses input focus (user typing in a text box gets interrupted)
- Kills CSS animations mid-transition
- Resets scroll position inside scrollable elements
- Breaks third-party widgets that store state in the DOM

**Morphdom** solves this by comparing the old and new HTML and only
updating the specific elements that actually changed.

## Concepts You'll Learn

### innerHTML vs DOM Diffing

**innerHTML** (before):
```javascript
container.innerHTML = "<div><input value='hello'><p>Count: 5</p></div>";
// → Browser destroys ALL child elements
// → Rebuilds everything from scratch
// → Input loses focus, user's cursor position gone
```

**morphdom** (after):
```javascript
morphdom(container, newHtml);
// → Compares old DOM tree with new HTML
// → Only updates <p>Count: 5</p> → <p>Count: 6</p>
// → Input stays untouched — focus preserved!
```

### How Morphdom Works

Morphdom walks both trees (old DOM and new HTML) simultaneously:

1. **Same element, same attributes** → skip (no change needed)
2. **Same element, different attributes** → update only the attributes
3. **Same element, different text** → update only the text content
4. **New element** → insert it
5. **Missing element** → remove it

This is much faster than recreating everything, especially for large pages.

### onBeforeElUpdated Hook

Morphdom lets you intercept updates with hooks:

```javascript
morphdom(container, newHtml, {
  onBeforeElUpdated: function(fromEl, toEl) {
    // Preserve value of focused inputs
    if (fromEl === document.activeElement && fromEl.tagName === "INPUT") {
      toEl.value = fromEl.value;
    }
    return true;  // true = proceed with update
  }
});
```

This prevents the input's value from being overwritten when the user
is actively typing.

### Graceful Fallback

If morphdom fails to load, `ignite.js` falls back to `innerHTML`:

```javascript
function applyUpdate(container, newHtml) {
  if (typeof morphdom === "function") {
    // Use morphdom for efficient patching
    morphdom(container, wrapper);
  } else {
    // Fallback: replace everything
    container.innerHTML = newHtml;
  }
}
```

## The Code

### `assets/morphdom.min.js` (New)

**Download morphdom** from the npm package and place it at `assets/morphdom.min.js`:

```bash
curl -o assets/morphdom.min.js https://unpkg.com/morphdom@2.7.4/dist/morphdom-umd.min.js
```

Alternatively, install via npm and copy the UMD bundle:
```bash
npm install morphdom
cp node_modules/morphdom/dist/morphdom-umd.min.js assets/morphdom.min.js
```

The morphdom library (~12KB minified) is loaded via a `<script>` tag
before `ignite.js` so it's available as a global `morphdom` function.

### Updated `assets/ignite.js`

**Replace `assets/ignite.js` with the full updated file.** The key changes from Step 14:
- New `applyUpdate()` function that uses morphdom instead of `innerHTML`
- The `socket.onmessage` handler now calls `applyUpdate(container, html)` instead of `container.innerHTML = html`

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
 * - JS zips statics + dynamics, then morphdom patches the DOM
 */

(function () {
  "use strict";

  // --- Configuration ---
  var LIVE_PATH = "/live";
  var APP_CONTAINER_ID = "ignite-app";

  // Statics are saved from the first message and reused for every update
  var statics = null;

  // --- WebSocket Connection ---
  var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  var socket = new WebSocket(protocol + "//" + window.location.host + LIVE_PATH);

  // --- Reconstruct HTML from statics + dynamics ---
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

  // --- Apply update to DOM ---
  // Uses morphdom if available, falls back to innerHTML
  function applyUpdate(container, newHtml) {
    if (typeof morphdom === "function") {
      // Create a temporary wrapper to morph into
      var wrapper = document.createElement("div");
      wrapper.id = APP_CONTAINER_ID;
      wrapper.innerHTML = newHtml;

      morphdom(container, wrapper, {
        // Preserve focused input elements
        onBeforeElUpdated: function (fromEl, toEl) {
          // Don't update the element if the user is actively typing in it
          if (fromEl === document.activeElement && fromEl.tagName === "INPUT") {
            toEl.value = fromEl.value;
          }
          return true;
        },
      });
    } else {
      // Fallback: replace entire content
      container.innerHTML = newHtml;
    }
  }

  // --- Receive updates from server ---
  socket.onmessage = function (event) {
    var data = JSON.parse(event.data);
    var container = document.getElementById(APP_CONTAINER_ID);
    if (!container) return;

    // First message includes statics — save them
    if (data.s) {
      statics = data.s;
    }

    // Reconstruct HTML and patch the DOM
    if (statics && data.d) {
      var newHtml = buildHtml(statics, data.d);
      applyUpdate(container, newHtml);
    }
  };

  // --- Send events to server ---
  document.addEventListener("click", function (e) {
    var target = e.target;

    while (target && target !== document) {
      var eventName = target.getAttribute("ignite-click");
      if (eventName) {
        e.preventDefault();

        var params = {};
        var value = target.getAttribute("ignite-value");
        if (value) {
          params.value = value;
        }

        socket.send(
          JSON.stringify({
            event: eventName,
            params: params,
          })
        );
        return;
      }
      target = target.parentElement;
    }
  });

  // --- Connection lifecycle ---
  socket.onopen = function () {
    console.log("[Ignite] LiveView connected (morphdom: " + (typeof morphdom === "function") + ")");
  };

  socket.onclose = function () {
    console.log("[Ignite] LiveView disconnected");
  };

  socket.onerror = function (err) {
    console.error("[Ignite] WebSocket error:", err);
  };
})();
```

The key change: instead of `container.innerHTML = html` (which destroys and recreates all elements), we call `applyUpdate` which uses morphdom to diff and patch only the changed elements.

### Updated `templates/live.html.eex`

**Replace `templates/live.html.eex` with the full updated file.** The only change from Step 13 is the new `<script>` tag that loads morphdom *before* `ignite.js`:

```html
<!DOCTYPE html>
<html>
<head>
  <title><%= @assigns[:title] || "Ignite LiveView" %></title>
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
  <div id="ignite-app">Connecting...</div>
  <hr>
  <p><small>Powered by <a href="/">Ignite</a></small></p>
  <script src="/assets/morphdom.min.js"></script>
  <script src="/assets/ignite.js"></script>
</body>
</html>
```

Morphdom must be loaded **before** `ignite.js` so that `typeof morphdom === "function"` evaluates to `true` when our code runs.

## How It Works

```
1. Server sends update: {d: ["<h1>Count: 6</h1>..."]}

2. JS reconstructs full HTML from statics + dynamics

3. Instead of:
   container.innerHTML = newHtml  (destroys everything)

4. We do:
   morphdom(container, newHtml)  (patches only changes)

5. Morphdom compares:
   Old: <p>5</p>  →  New: <p>6</p>
   Only the text node "5" → "6" is updated.
   Everything else stays untouched.
```

## Try It Out

1. Start the server: `iex -S mix`

2. Visit http://localhost:4000/counter

3. Open the browser console. You should see:
   ```
   [Ignite] LiveView connected (morphdom: true)
   ```

4. Click the buttons — counter still works.

5. Open DevTools → Elements tab. Watch the DOM as you click:
   - With morphdom: only the count text node flashes (gets updated)
   - Without morphdom: the entire `#ignite-app` div would flash

6. The real benefit shows when you have inputs. If you add a text
   input to your LiveView template, typing in it won't be interrupted
   by server updates.

## File Checklist

| File | Status |
|------|--------|
| `assets/morphdom.min.js` | **New** |
| `assets/ignite.js` | **Modified** |
| `templates/live.html.eex` | **Modified** |

## The Framework Is Complete!

Congratulations! You've built **Ignite** — a real web framework with:

| Layer | Component | Step |
|-------|-----------|------|
| Networking | TCP Socket → Cowboy | 1, 10 |
| Parsing | HTTP Parser | 2, 9 |
| Routing | Macro-based DSL | 3, 5 |
| Controllers | Response helpers | 4 |
| Reliability | OTP Supervision | 6 |
| Templates | EEx Engine | 7 |
| Middleware | Plug pipeline | 8 |
| Error Handling | try/rescue boundary | 11 |
| Real-time | LiveView + WebSocket | 12, 13 |
| Optimization | Diffing Engine | 14 |
| Dev Tools | Hot Code Reloader | 15 |
| UI Performance | Morphdom DOM diffing | 16 |

You understand the internals of Phoenix better than most developers
who just run `mix phx.new`. Every concept here — the conn pipeline,
macros, OTP supervision, LiveView — is the same architecture that
powers production Elixir applications.

---

[← Previous: Step 15 - Hot Code Reloader](15-hot-reloader.md) | [Next: Step 17 - PubSub — Real-Time Broadcasting Between LiveViews →](17-pubsub.md)

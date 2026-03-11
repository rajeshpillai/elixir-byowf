# Refactor Guide: ignite.js (Elixir)

Reference implementation: **node-byowf/public/blaze.js**

---

## 1. Add Automatic Reconnection

**Priority: High** | **File: `assets/ignite.js`**

Currently ignite.js logs disconnect and does nothing. Users must manually refresh the page.

**Add reconnection state (near the top vars):**
```js
var reconnectDelay = 200;
var MAX_DELAY = 5000;
var reconnectTimer = null;
var navigating = false;
```

**Add reconnect function:**
```js
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

> **Why not `initialLivePath`?** After a live navigation, the container's
> `data-live-path` reflects the current view. Reconnecting to `initialLivePath`
> would drop the user back to the landing page.

**Update `navigate()` to set `navigating` flag:**
```js
function navigate(url, livePath) {
  navigating = true;
  // ...existing body...
  connect(livePath);
  navigating = false;
}
```

**Update `socket.onclose` (line 569):**
```js
socket.onclose = function () {
  if (navigating) return;
  setStatus("Disconnected — reconnecting...", "disconnected");
  scheduleReconnect();
};
```

**Reset delay on successful connect (in `socket.onopen`, line 557):**
```js
socket.onopen = function () {
  reconnectDelay = 200;
  setStatus("Connected", "connected");
  // ...existing log
};
```

> **Depends on:** Item 7 (status UI) — `setStatus` must exist before this
> item works. Implement Item 7 first, or guard with
> `if (typeof setStatus === "function")`.

---

## 2. Switch from Document-Level to Container-Level Event Delegation

**Priority: High** | **File: `assets/ignite.js`**

Currently event listeners are on `document` (lines 633, 665, 686). This means clicks anywhere in the page are processed, even outside the LiveView container. Scope to the container.

**Current (lines 633-662):**
```js
document.addEventListener("click", function (e) { ... });
document.addEventListener("input", function (e) { ... });
document.addEventListener("submit", function (e) { ... });
```

**Replace with:**
```js
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

appContainer.addEventListener("input", function (e) {
  var target = e.target.closest("[ignite-change]");
  if (target) {
    var name = e.target.getAttribute("name") || "value";
    var params = {};
    params[name] = e.target.value;
    sendEvent(resolveEvent(target.getAttribute("ignite-change"), e.target), params);
  }
});

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

**Note:** Keep drag-and-drop listeners on `document` since drop targets may exist outside the container.

---

## 3. Standardize Change Event Params

**Priority: High** | **File: `assets/ignite.js`**

Currently sends `{ field: name, value: value }`. All other implementations send `{ [name]: value }`.

**Current (lines 673-676):**
```js
var params = {
  field: target.getAttribute("name") || "",
  value: target.value,
};
```

**Fix:**
```js
var name = e.target.getAttribute("name") || "value";
var params = {};
params[name] = e.target.value;
```

**Note:** This requires updating server-side handlers that destructure `%{"field" => _, "value" => _}` to use the field name directly. Grep for `"field"` in these files:
- `lib/my_app/live/` — any `handle_event` that pattern-matches `%{"field" => _, "value" => _}`

---

## 4. Add `encodeURIComponent` to WebSocket Path

**Priority: Medium** | **File: `assets/ignite.js`**

The WebSocket URL uses the live path directly. If the path contains special characters, this could break.

**Current (line 495):**
```js
socket = new WebSocket(protocol + "//" + window.location.host + livePath);
```

This is less of an issue since Elixir uses direct paths (e.g., `/live`) rather than query parameters, but it's good practice to validate/sanitize.

---

## 5. Add `keydown` Event Binding

**Priority: Medium** | **File: `assets/ignite.js`**

Bun and Node support `bv-keydown` for real-time keyboard events (useful for search-as-you-type with key detection). Add:

```js
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

---

## 6. Use Composite Upload Refs

**Priority: Medium** | **File: `assets/ignite.js`**

Simple index refs can collide across multiple upload fields or re-selections.

**Current (line 172):**
```js
var ref = String(i);
```

**Fix (both in `initUploadInput` and drag-and-drop handler):**
```js
var ref = uploadName + "-" + i + "-" + Date.now();
```

---

## 7. Add Connection Status UI

**Priority: Medium** | **File: `assets/ignite.js`**

Node and Bun display connection status. Ignite only logs to console.

**Add status element handling:**
```js
var statusEl = document.getElementById("ignite-status");

function setStatus(text, className) {
  if (statusEl) {
    statusEl.textContent = text;
    statusEl.className = "status " + (className || "");
  }
}
```

**Update `templates/live.html.eex`** to include:
```html
<p class="status" id="ignite-status"></p>
```

---

## 8. Use Explicit `type` Field in Protocol

**Priority: Low** | **File: `assets/ignite.js` + server-side `lib/ignite/live_view/handler.ex`**

Currently the protocol uses implicit typing (presence of `s` = mount, presence of `redirect` = redirect). This works but is fragile and harder to debug.

**Current message handling (lines 497-554):**
```js
if (data.redirect) { ... }
if (data.s) { statics = data.s; }
if (statics && data.d) { ... }
if (data.upload) { ... }
```

**Proposed (matching Node's pattern):**
```js
switch (data.type) {
  case "mount":
    statics = data.statics;
    dynamics = data.dynamics;
    applyUpdate(el, buildHtml(statics, dynamics));
    break;
  case "diff":
    // merge sparse dynamics into existing dynamics array
    break;
  case "redirect":
    navigate(data.url, data.live_path);
    break;
  case "upload":
    // handle upload config
    break;
}

// Post-switch: these run for every message type
applyStreamOps(data);
initUploadInputs(el);
```

> **Note:** The current code runs `applyStreamOps(data)` and
> `initUploadInputs(el)` after every message. The switch must preserve this
> behavior — either with post-switch calls (shown above) or by adding them
> to each relevant case.

**Note:** This requires a coordinated change in `lib/ignite/live_view/handler.ex` to include a `type` field in all messages. This is a bigger refactor — do it last.

---

## 9. Consolidate Hook Lifecycle into Single Function

**Priority: Low** | **File: `assets/ignite.js`**

Currently hooks are managed by three separate functions: `mountHooks()`, `updateHooks()`, `cleanupHooks()`, called in sequence from `applyUpdate()`. Node consolidates this into a single `processHooks()` that does mount/update/destroy in one pass.

**Replace `mountHooks` + `updateHooks` + `cleanupHooks` with:**
```js
function processHooks(container) {
  var hookDefs = getHookDefinitions();
  var seenIds = {};

  var elements = container.querySelectorAll("[ignite-hook]");
  for (var idx = 0; idx < elements.length; idx++) {
    var el = elements[idx];
    var hookName = el.getAttribute("ignite-hook");
    var elId = el.id;
    if (!elId || !hookName) return;

    seenIds[elId] = true;
    var hookDef = hookDefs[hookName];
    if (!hookDef) return;

    var existing = mountedHooks[elId];
    if (existing) {
      existing.instance.el = el;
      if (typeof existing.instance.updated === "function") {
        existing.instance.updated();
      }
    } else {
      var instance = createHookInstance(hookDef, el);
      mountedHooks[elId] = { name: hookName, instance: instance };
      if (typeof instance.mounted === "function") {
        instance.mounted();
      }
    }
  }

  for (var id in mountedHooks) {
    if (!seenIds[id]) {
      var entry = mountedHooks[id];
      if (entry && typeof entry.instance.destroyed === "function") {
        entry.instance.destroyed();
      }
      delete mountedHooks[id];
    }
  }
}
```

Then in `applyUpdate()`, replace the three calls with just `processHooks(container)`.

---

## 10. hooks.js: Use `data-role` Selectors Instead of Hardcoded IDs

**Priority: Low** | **File: `assets/hooks.js`**

Currently uses hardcoded element IDs (`#copy-btn`, `#local-time-display`, `#send-time-btn`). This couples hooks to specific HTML structure.

**Current:**
```js
var btn = this.el.querySelector("#copy-btn");
var display = this.el.querySelector("#local-time-display");
var btn = this.el.querySelector("#send-time-btn");
```

**Fix (match Bun/Go/Node):**
```js
var btn = this.el.querySelector("[data-role='copy']");  // for CopyToClipboard
var display = this.el.querySelector("[data-role='display']");
var btn = this.el.querySelector("[data-role='send']");
```

Update the hooks demo template (`templates/hooks_demo.html.eex`) to replace
`id="copy-btn"` with `data-role="copy"`, `id="local-time-display"` with
`data-role="display"`, and `id="send-time-btn"` with `data-role="send"`.

---

## Summary Checklist

| # | Change | Priority |
|---|--------|----------|
| 1 | Add automatic reconnection with exponential backoff | High |
| 2 | Container-level event delegation (replace document listeners) | High |
| 3 | Standardize change event params to `{ [name]: value }` | High |
| 4 | `encodeURIComponent` on WS path (minor for direct paths) | Medium |
| 5 | Add `ignite-keydown` event binding | Medium |
| 6 | Composite upload refs (`name-idx-timestamp`) | Medium |
| 7 | Add connection status UI element | Medium |
| 8 | Explicit `type` field in protocol messages | Low |
| 9 | Consolidate hook lifecycle into single `processHooks()` | Low |
| 10 | hooks.js: `data-role` selectors instead of hardcoded IDs | Low |

## Recommended Implementation Order

Items have dependencies that differ from the priority ordering:

1. **Item 7** — Status UI (defines `setStatus`, needed by Item 1)
2. **Item 1** — Reconnection (depends on Item 7)
3. **Items 2 + 3** — Container delegation + change params (both touch event listeners; do together)
4. **Item 5** — Keydown binding (natural addition after Item 2)
5. **Item 6** — Composite upload refs (independent)
6. **Items 9, 10, 4** — Low-priority cleanups (independent of each other)
7. **Item 8** — Protocol refactor (requires coordinated server-side changes; do last)

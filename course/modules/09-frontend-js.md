# Frontend JS

<!-- metadata: complexity=Complex | files=3 | last-generated=2026-03-24 -->

[< Previous: Persistence](./08-persistence.md) | [Index](../01-overview.md) | [Next: Static Assets >](./10-static-assets.md)

---

## Purpose

The client-side half of Ignite's LiveView. A single vanilla JavaScript file — no build step, no bundler, no framework — handles WebSocket connections, event delegation, HTML reconstruction from statics+dynamics, DOM patching via morphdom, JS hooks lifecycle, stream operations, file uploads, and client-side live navigation. The design philosophy: the server owns state and rendering; the browser is a thin display layer that forwards user interactions and applies DOM diffs.

## Key Files

| File | Purpose |
|------|---------|
| `assets/ignite.js` | Main client: WebSocket, event delegation, DOM patching, streams, uploads, live navigation |
| `assets/hooks.js` | Example hooks: `CopyToClipboard`, `LocalTime` — demonstrate lifecycle callbacks |
| `assets/morphdom.min.js` | Third-party DOM diffing library — compares old/new trees, applies minimal mutations |
| `assets/todo.css` | Styles for the Todo capstone app |

## Architecture

```mermaid
flowchart TD
    subgraph Browser["Browser (ignite.js)"]
        Events["Event Listeners<br/>click · input · submit"]
        Nav["Live Navigation<br/>pushState · popstate"]
        Hooks["JS Hooks<br/>mounted · updated · destroyed"]
        Upload["Upload System<br/>chunked binary frames"]
    end

    Events -->|sendEvent JSON| WS["WebSocket Connection<br/>connect() line 474"]
    Nav -->|navigate()| WS
    Hooks -->|pushEvent()| WS
    Upload -->|binary frame| WS

    WS -->|mount: s + d| Build["buildHtml()<br/>line 341"]
    WS -->|update: sparse d| Build
    Build --> Morph["morphdom()<br/>applyUpdate() line 354"]
    Morph --> DOM["DOM"]
    WS -->|streams| StreamOps["applyStreamOps()<br/>line 402"]
    StreamOps --> DOM
    WS -->|redirect| Nav

    Morph --> HookLife["Hook Lifecycle<br/>cleanup → mount → update"]
    Morph --> UploadInit["initUploadInputs()<br/>line 241"]

    style Browser fill:#f0f4ff,stroke:#4A90D9
    style WS fill:#FFB347,stroke:#333
    style DOM fill:#50C878,stroke:#333
```

## How It Works

### Understanding the WebSocket Client

**The Big Picture:** Think of a walkie-talkie. When the page loads, the browser opens a persistent channel to the server. The server sends display instructions; the browser sends back user actions. The first message contains the full blueprint (statics) plus current values (dynamics). After that, only changed values travel the wire.

<details>
<summary>Intermediate: Protocol and state management</summary>

The IIFE at `assets/ignite.js:27` maintains three module-level variables:

- **`statics`** (line 34): Saved from the first message's `s` field. Never changes for a given view. Contains the HTML fragments between dynamic expressions.
- **`dynamics`** (line 37): The current dynamic values. Updated on each server message — either replaced entirely (full array) or patched at specific indices (sparse object).
- **`socket`** (line 40): The active `WebSocket` instance.

**Mount protocol** — `connect()` at line 474 creates a new WebSocket. The `onmessage` handler at line 497 processes the first message:
```
{"s": ["<h1>Count: ", "</h1>"], "d": ["42"]}
```
Statics are saved permanently. `buildHtml()` at line 341 interleaves them: `statics[0] + dynamics[0] + statics[1]` = `<h1>Count: 42</h1>`.

**Update protocol** — subsequent messages omit `s` and send only `d`. If `d` is an array, dynamics are fully replaced. If `d` is an object like `{"0": "43"}`, only the changed index is patched (line 518-529).

</details>

<details>
<summary>Advanced: Reconnection and navigation teardown</summary>

When `connect()` is called (line 474), it first closes any existing socket (line 476-479), destroys all hooks from the previous view via `destroyAllHooks()` (line 482), and resets both `statics` and `dynamics` to `null` (line 485-486). This ensures a clean slate when navigating between LiveViews.

The WebSocket URL is constructed from the current protocol — `wss:` for HTTPS, `ws:` for HTTP (line 494-495). The `livePath` is distinct from the browser URL: `/live/counter` vs `/counter`. The route mapping `liveRoutes` (line 43) is injected by the server as a `data-live-routes` JSON attribute on the app container (line 324-331).

</details>

### Understanding Event Delegation

**The Big Picture:** Rather than attaching a listener to every button, Ignite listens once at the document level and checks if the clicked element has special attributes. Like a mail room that reads the address on each letter and routes it accordingly.

<details>
<summary>Intermediate: Three event types</summary>

All three listeners use event bubbling — attached to `document`, they catch events from any element in the page:

1. **Click** (line 633): Walks up the DOM from the clicked element looking for `ignite-navigate` (triggers client-side navigation) or `ignite-click` (sends event to server). Optionally reads `ignite-value` for a static parameter.

2. **Input** (line 665): Fires on every keystroke. Walks up from the input to find `ignite-change`. Sends `{field: "name", value: "Alice"}` — the field name comes from the input's `name` attribute.

3. **Submit** (line 686): Catches form submissions. Reads `ignite-submit` from the form element. Collects all non-file fields via `FormData` and sends them as a flat params object.

All three use `resolveEvent()` (line 620) to namespace events inside components: if the element is inside `[ignite-component="comp-1"]`, the event becomes `"comp-1:increment"`.

</details>

<details>
<summary>Advanced: Delegation walk-up pattern</summary>

The click handler at line 633 uses a `while (target && target !== document)` loop, walking from the clicked element up through its parents. This means `ignite-click` can be placed on a parent `<div>` and will capture clicks on child elements (like a `<span>` inside a button). The loop checks `ignite-navigate` first (line 638), then `ignite-click` (line 646), establishing priority: navigation always wins over events.

The component namespacing in `resolveEvent()` (line 620-630) also walks up to find the nearest `[ignite-component]` ancestor. This means nested components scope their events — the server-side handler can split on `:` to route events to the correct component.

</details>

### Understanding DOM Patching with Morphdom

**The Big Picture:** Instead of tearing down the entire page and rebuilding it (like repainting a wall to fix one scratch), morphdom compares the old wall with a blueprint of the new one and only repaints the scratch. Focus, scroll position, animations, and form input values survive.

<details>
<summary>Intermediate: The applyUpdate flow</summary>

`applyUpdate()` at line 354 takes the container and new HTML string. It creates a temporary wrapper `<div>` with the same ID and data attributes, sets its `innerHTML` to the new HTML, and calls `morphdom(container, wrapper, options)`.

The `onBeforeElUpdated` callback (line 370) handles three special cases:
- **Stream containers** (line 372): Elements with `[ignite-stream]` are skipped — their children are managed by `applyStreamOps()` separately.
- **File inputs** (line 376): Browsers forbid setting file input values programmatically — skip them.
- **Active inputs** (line 380-384): If the user is typing in an input or textarea, the new element's value is set to the current value to preserve what the user typed.

After morphdom runs, the hook lifecycle executes: `cleanupHooks()` destroys removed hooks, `mountHooks()` initializes new ones, `updateHooks()` calls `updated()` on existing ones (line 394-396).

If morphdom is not loaded, `applyUpdate()` falls back to `innerHTML` replacement (line 389-391).

</details>

<details>
<summary>Advanced: Stream operations bypass</summary>

`applyStreamOps()` at line 402 processes stream data that arrives alongside (or instead of) regular diffs. Streams target DOM containers marked with `[ignite-stream="name"]`. Three operations in order:

1. **Reset** (line 417): Removes all children from the container.
2. **Deletes** (line 424): Removes elements by DOM ID.
3. **Inserts** (line 434): Adds new elements. If an element with the same ID exists, it's updated in-place via morphdom (upsert, line 449-460). New elements are prepended if `entry.at === 0` (line 461-463), otherwise appended.

The key insight: morphdom's `onBeforeElUpdated` returns `false` for stream containers (line 372-374), preventing morphdom from touching their children. This avoids conflicts between the two update mechanisms.

</details>

### Understanding JS Hooks

**The Big Picture:** Sometimes the server cannot do everything — copy to clipboard, read local time, animate a chart. Hooks let you attach JavaScript behavior to specific elements, with lifecycle callbacks that fire when the element appears, updates, or disappears.

<details>
<summary>Intermediate: Registration and lifecycle</summary>

Hooks are registered globally via `window.IgniteHooks` (line 46). Each hook is an object with optional callbacks: `mounted()`, `updated()`, `destroyed()`.

When morphdom finishes patching, `mountHooks()` (line 65) scans for `[ignite-hook]` elements. For each element with an `id` not already tracked in `mountedHooks`, it calls `createHookInstance()` (line 55) which creates a prototype-linked copy with:
- `this.el` — the DOM element
- `this.pushEvent(event, params)` — sends events to the server via `sendEvent()`

The `hooks.js` file shows two examples:
- **CopyToClipboard** (line 22): On mount, attaches a click handler to a button. Uses `navigator.clipboard.writeText()` and pushes the result back to the server.
- **LocalTime** (line 69): On mount, starts a `setInterval` to update a time display every second. On destroy, clears the interval to prevent memory leaks.

</details>

<details>
<summary>Advanced: Element reference and cleanup</summary>

A subtle issue: after morphdom patches the DOM, the element reference in a hook may be stale (morphdom can replace elements). `updateHooks()` at line 93-110 addresses this by re-assigning `entry.instance.el = el` with the fresh DOM reference (line 104) before calling `updated()`.

`cleanupHooks()` (line 113-134) builds a set of current hook element IDs, then removes any tracked hooks whose IDs are no longer in the DOM. `destroyAllHooks()` (line 137-145) is called during navigation to tear down everything from the previous view.

The `mountedHooks` registry (line 48) is keyed by element ID — this means every hooked element **must** have a unique `id` attribute. Without it, the hook is silently skipped (line 74).

</details>

### Understanding Live Navigation

**The Big Picture:** Clicking a link in a traditional app reloads the entire page. Live navigation swaps only the LiveView content — like changing the channel on a TV without turning it off and on again. The URL updates, the browser history works, but no full page reload occurs.

<details>
<summary>Intermediate: Navigate and popstate</summary>

`navigate()` at line 580 takes a URL (what the user sees) and an optional `livePath` (the WebSocket endpoint). If `livePath` is not provided, it looks up the URL in `liveRoutes` (line 582-584). If no live route exists, it falls back to a full page navigation (line 588).

For live routes: `history.pushState()` (line 593) updates the browser URL without reload, then `connect(livePath)` opens a new WebSocket to the target LiveView.

Browser back/forward buttons fire `popstate` (line 600). If the history state contains a `livePath`, it reconnects to that LiveView. Otherwise, a full page reload occurs.

On page load, `history.replaceState()` (line 612) seeds the initial history entry so the first back-button press works correctly.

</details>

<details>
<summary>Advanced: Route mapping injection</summary>

The server injects the route mapping as a JSON `data-live-routes` attribute on the `#ignite-app` container. On init (line 324-331), the JS parses this into the `liveRoutes` object: `{"/counter": "/live/counter", "/chat": "/live/chat"}`.

This decouples the user-facing URL from the WebSocket path. The server controls which URLs are "live" — any URL not in the mapping triggers a traditional page load, which is the correct behavior for non-LiveView routes.

</details>

## Key Flows

```flow-trace
{
  "title": "Click Event → Server → DOM Patch",
  "steps": [
    {"component": "Browser", "action": "User clicks button with ignite-click=\"increment\"", "file": "assets/ignite.js:633", "detail": "Document-level click listener fires, walks up DOM to find ignite-click attribute"},
    {"component": "Browser", "action": "resolveEvent checks component namespace", "file": "assets/ignite.js:620", "detail": "Walks up to find [ignite-component] ancestor; prefixes event name if found"},
    {"component": "Browser", "action": "sendEvent sends JSON over WebSocket", "file": "assets/ignite.js:334", "detail": "JSON.stringify({event: \"increment\", params: {}}) sent via socket.send()"},
    {"component": "Server", "action": "Handler receives event, calls handle_event/3", "file": "lib/ignite/live_view/handler.ex", "detail": "Decodes JSON, dispatches to view module, gets new assigns"},
    {"component": "Server", "action": "Engine diffs old vs new dynamics", "file": "lib/ignite/live_view/engine.ex", "detail": "Only changed indices sent: {d: {\"0\": \"43\"}}"},
    {"component": "Browser", "action": "onmessage patches dynamics array", "file": "assets/ignite.js:518", "detail": "Sparse object: dynamics[parseInt(key)] = value for each changed index"},
    {"component": "Browser", "action": "buildHtml interleaves statics + dynamics", "file": "assets/ignite.js:341", "detail": "Loops through statics, inserts dynamics between them to produce full HTML"},
    {"component": "Browser", "action": "morphdom patches only changed DOM nodes", "file": "assets/ignite.js:368", "detail": "morphdom(container, wrapper) diffs old/new trees, applies minimal mutations"},
    {"component": "Browser", "action": "Hook lifecycle runs", "file": "assets/ignite.js:394", "detail": "cleanupHooks → mountHooks → updateHooks on the patched container"}
  ]
}
```

```code-walkthrough
{
  "title": "WebSocket Message Handler",
  "file": "assets/ignite.js",
  "steps": [
    {"lines": "497-500", "label": "Parse incoming message", "description": "Every WebSocket message is JSON-parsed. The app container is looked up by ID — if removed, bail out."},
    {"lines": "502-506", "label": "Handle server-initiated redirect", "description": "If the message contains a `redirect` field, navigate() is called with the target URL and live_path. No DOM update occurs."},
    {"lines": "508-511", "label": "Save statics on first message", "description": "The first message includes `s` (statics array). Saved once and reused for all subsequent renders of this view."},
    {"lines": "514-529", "label": "Apply dynamics update", "description": "If `d` is an array, dynamics are fully replaced. If `d` is an object (sparse), only the specified indices are patched into the existing dynamics array."},
    {"lines": "532-533", "label": "Reconstruct and patch DOM", "description": "buildHtml() zips statics + dynamics into an HTML string. applyUpdate() runs morphdom to patch only changed nodes."},
    {"lines": "536-540", "label": "Process streams and uploads", "description": "Stream operations (insert/delete/reset) run after the main DOM update so containers exist. Upload inputs are initialized for newly rendered file inputs."},
    {"lines": "543-554", "label": "Handle upload config", "description": "After upload validation, the server responds with entry validity and chunk size. Valid entries with auto_upload trigger chunked binary uploads."}
  ]
}
```

```chat
{
  "title": "LiveView Click Lifecycle",
  "participants": {
    "Browser": {"color": "#FFB347", "icon": "laptop"},
    "WebSocket": {"color": "#4A90D9", "icon": "zap"},
    "Server": {"color": "#50C878", "icon": "server"}
  },
  "messages": [
    {"from": "Browser", "text": "User clicked a button with ignite-click=\"increment\".", "technical": "Document click listener at line 633 catches the event, walks up DOM, finds attribute"},
    {"from": "Browser", "text": "Sending event over the wire.", "technical": "sendEvent(\"increment\", {}) → socket.send(JSON.stringify({event: \"increment\", params: {}}))"},
    {"from": "WebSocket", "text": "Delivering JSON to server handler.", "technical": "WebSocket frame: {\"event\":\"increment\",\"params\":{}}"},
    {"from": "Server", "text": "Got it. Running handle_event, count goes from 42 to 43.", "technical": "handle_event(\"increment\", %{}, assigns) → {:noreply, %{count: 43}}"},
    {"from": "Server", "text": "Only index 0 changed. Sending sparse diff.", "technical": "Engine.diff([\"42\"], [\"43\"]) → %{\"0\" => \"43\"} → JSON: {\"d\":{\"0\":\"43\"}}"},
    {"from": "WebSocket", "text": "15 bytes heading to the browser.", "technical": "WebSocket frame: {\"d\":{\"0\":\"43\"}}"},
    {"from": "Browser", "text": "Patching dynamics[0] from 42 to 43.", "technical": "Sparse update: dynamics[0] = \"43\"; buildHtml(); morphdom patches one text node"},
    {"from": "Browser", "text": "Done. Only the counter text changed. Focus, scroll, animations all preserved.", "technical": "morphdom onBeforeElUpdated preserves activeElement value; hook lifecycle runs"}
  ]
}
```

## Hot Paths

| Path | Location | Why it matters |
|------|----------|----------------|
| `buildHtml()` | `assets/ignite.js:341` | Called on every server update — keep statics/dynamics arrays small |
| `morphdom()` call | `assets/ignite.js:368` | Most CPU-intensive client operation — minimized by sparse diffs |
| `sendEvent()` | `assets/ignite.js:334` | Every user interaction goes through here — keep params lean |
| `applyStreamOps()` | `assets/ignite.js:402` | Bypasses full rebuild for list mutations — O(n) in inserts/deletes |

## Gotchas

- **Hooked elements must have an `id`**: Without an `id` attribute, `mountHooks()` silently skips the element (line 74). No error, no warning — just a hook that never fires.
- **morphdom fallback**: If `morphdom.min.js` is not loaded, `applyUpdate()` falls back to `innerHTML` (line 389), which destroys focus, scroll, and form state on every update.
- **Stream containers are skipped by morphdom**: `onBeforeElUpdated` returns `false` for `[ignite-stream]` elements (line 372). If you put non-stream content inside a stream container, morphdom will not update it.
- **File inputs are never updated**: morphdom skips `type="file"` inputs (line 376) because browsers forbid setting their value. Re-rendering a file input will not clear the selection.
- **Sparse update requires prior dynamics**: If the first update is a sparse object but `dynamics` is null, the code enters the fallback at line 524 — this is defensive but indicates a protocol mismatch.

## Practice

```drag-match
{
  "title": "Match Frontend Concepts to Their Roles",
  "pairs": [
    {"concept": "statics", "description": "HTML fragments saved once on mount — reused to reconstruct HTML on every update"},
    {"concept": "sparse update", "description": "JSON object with only changed indices — patches dynamics array in place"},
    {"concept": "morphdom", "description": "Compares old and new DOM trees, applies only the minimal set of mutations"},
    {"concept": "ignite-click", "description": "Attribute caught by document-level click listener — sends named event over WebSocket"},
    {"concept": "ignite-hook", "description": "Attaches a JS Hook object with mounted/updated/destroyed lifecycle callbacks"},
    {"concept": "liveRoutes", "description": "Server-injected URL-to-WebSocket-path mapping for client-side navigation"},
    {"concept": "applyStreamOps", "description": "Processes insert/delete/reset operations directly on stream container DOM nodes"},
    {"concept": "resolveEvent", "description": "Walks up DOM to find ignite-component ancestor and namespace-prefixes the event"}
  ]
}
```

```spot-the-bug
{
  "title": "Find the Hook Bug",
  "language": "html",
  "code": "<div ignite-hook=\"LocalTime\">\n  <span id=\"local-time-display\">--:--:--</span>\n  <button id=\"send-time-btn\">Send to Server</button>\n</div>",
  "bug_lines": [1],
  "hints": [
    "What does mountHooks() check at line 74 before mounting a hook?",
    "Look at the outer <div> — what attribute is it missing?"
  ],
  "explanation": "The <div> with ignite-hook has no `id` attribute. At ignite.js line 74, mountHooks() checks `if (!elId || !hookName) continue` — elements without an id are silently skipped. Fix: add a unique id, e.g. <div id=\"local-time\" ignite-hook=\"LocalTime\">."
}
```

```spot-the-bug
{
  "title": "Find the Navigation Bug",
  "language": "html",
  "code": "<a href=\"/about\" ignite-navigate=\"/about\" ignite-click=\"track_nav\">\n  About Us\n</a>",
  "bug_lines": [1],
  "hints": [
    "What happens when both ignite-navigate and ignite-click are on the same element?",
    "Look at the click handler loop at line 637-661 — which attribute is checked first?"
  ],
  "explanation": "The click handler checks ignite-navigate before ignite-click (line 638 vs 646). When ignite-navigate is found, it calls navigate() and returns immediately — the ignite-click event is never sent. Fix: remove ignite-click from navigation links, or send the tracking event from the server's mount/2 callback."
}
```

> **Quiz: Sparse Dynamics**
>
> The server sends `{"d": {"1": "Bob"}}`. Current dynamics are `["Alice", "online", "3 messages"]`. What are the dynamics after patching?
>
> - A) `["Bob"]`
> - B) `["Alice", "Bob", "3 messages"]`
> - C) `["Bob", "online", "3 messages"]`
>
> <details>
> <summary>Show Answer</summary>
>
> **B)** Sparse patch at line 520-522: `dynamics[parseInt("1", 10)] = "Bob"`. Only index 1 is overwritten. Indices 0 and 2 remain unchanged.
>
> </details>

> **Quiz: Hook Lifecycle**
>
> After morphdom patches the DOM and a hooked element is removed, what is the correct callback order?
>
> - A) `destroyed()` on removed hooks, then `mounted()` on new hooks
> - B) `mounted()` on new hooks, then `destroyed()` on removed hooks
> - C) `updated()` on all hooks, then `destroyed()` on removed hooks
>
> <details>
> <summary>Show Answer</summary>
>
> **A)** At lines 394-396: `cleanupHooks()` runs first (calls `destroyed()`), then `mountHooks()` (calls `mounted()`), then `updateHooks()` (calls `updated()`).
>
> </details>

---

[< Previous: Persistence](./08-persistence.md) | [Index](../01-overview.md) | [Next: Static Assets >](./10-static-assets.md)

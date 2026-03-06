# Step 25: LiveView Streams

## What We're Building

A stream system for efficiently managing large collections in LiveView. Instead of re-rendering and re-sending an entire list when one item is added, streams send only the individual insert/delete operation — O(1) per update instead of O(N).

## The Problem

In the current system, a list of items is rendered as a single dynamic value. Consider a chat log with 100 messages:

```elixir
def render(assigns) do
  messages_html = Enum.map(assigns.messages, fn msg ->
    "<div>#{msg.text}</div>"
  end) |> Enum.join()

  ~L"""
  <div><%= messages_html %></div>
  """
end
```

The entire `messages_html` string is one entry in `dynamics[]`. Adding one new message re-sends all 100 messages' HTML (~10KB) even though only one item (~100 bytes) actually changed. The fine-grained diffing from Step 24 can't help — it's a single dynamic that changed.

## The Solution

### Three Key Ideas

1. **Operation-based updates** — Instead of tracking the full list, track only what changed: insert, delete, or reset. The server sends operations, not snapshots.

2. **Render function per stream** — Each stream has a render function registered at initialization. Items are rendered to HTML on the server and sent as individual DOM elements.

3. **Separate wire channel** — Stream operations are sent as a `streams` field alongside the existing `d` (dynamics) field. They're completely decoupled from the statics/dynamics diffing.

### Stream API

**Update `lib/ignite/live_view.ex`** — add the `stream`, `stream_insert`, and `stream_delete` functions:

```elixir
# Initialize a stream with a render function
assigns = stream(assigns, :events, initial_items,
  render: fn event ->
    ~s(<div id="events-#{event.id}">#{event.text}</div>)
  end
)

# Insert at end (append — default)
assigns = stream_insert(assigns, :events, new_event)

# Insert at beginning (prepend)
assigns = stream_insert(assigns, :events, new_event, at: 0)

# Delete by item
assigns = stream_delete(assigns, :events, event_to_remove)

# Reset — clear all items and optionally repopulate
assigns = stream(assigns, :events, [], reset: true)
assigns = stream(assigns, :events, new_items, reset: true)
```

### The `%Stream{}` Struct

**Create `lib/ignite/live_view/stream.ex`:**

```elixir
defstruct [
  :name,        # atom — :events, :messages, etc.
  :render_fn,   # fn(item) -> html_string
  :dom_prefix,  # "events" — prefix for DOM IDs
  :id_fn,       # fn(item) -> string — extracts unique ID
  ops: [],      # pending operations queue
  items: %{}    # %{dom_id => true} — tracks existing DOM IDs
]
```

Key properties:
- `render_fn` is provided once at initialization and reused for every insert
- `ops` accumulates operations between renders, then gets drained by the handler
- `items` tracks only DOM IDs (not item data) — items are freed after being sent

### How Operations Flow

1. LiveView calls `stream_insert(assigns, :events, item)` — queues `{:insert, item, "events-42", [at: 0]}`
2. Handler calls `render/1` → produces statics/dynamics as usual
3. Handler calls `Stream.extract_stream_ops(assigns)` → renders each queued item via `render_fn`, builds wire payload, clears the ops queue
4. Payload sent: `{"d": {"0": "5"}, "streams": {"events": {"inserts": [...]}}}`
5. JS client applies dynamics via morphdom, then applies stream ops to the DOM container

### Wire Protocol

Stream operations are sent as a `streams` field alongside the existing `d` field:

**Mount** (empty stream, no items yet):
```json
{"s": ["...", "..."], "d": ["0"]}
```

**Insert** (one new event prepended):
```json
{
  "d": {"0": "1"},
  "streams": {
    "events": {
      "inserts": [
        {"id": "events-1", "at": 0, "html": "<div id=\"events-1\">...</div>"}
      ]
    }
  }
}
```

**Delete**:
```json
{
  "d": {},
  "streams": {
    "events": {
      "deletes": ["events-3"]
    }
  }
}
```

**Reset** (clear all items):
```json
{
  "d": {"0": "0"},
  "streams": {
    "events": {
      "reset": true
    }
  }
}
```

### Template Integration

Stream containers are empty elements with an `ignite-stream` attribute:

```elixir
def render(assigns) do
  ~L"""
  <div id="stream-demo">
    <p>Total events: <strong><%= assigns.event_count %></strong></p>
    <div ignite-stream="events"
         style="max-height: 400px; overflow-y: auto;">
    </div>
  </div>
  """
end
```

The container starts empty. Stream operations populate and manage its children. The event count is a normal dynamic that uses sparse diffing.

### Frontend Changes

**Update `assets/ignite.js`** — add the `applyStreamOps` function and call it after morphdom updates:

```javascript
function applyStreamOps(data) {
  if (!data.streams) return;

  for (var streamName in data.streams) {
    var ops = data.streams[streamName];
    var container = document.querySelector(
      '[ignite-stream="' + streamName + '"]'
    );

    // Reset: remove all children
    if (ops.reset) {
      while (container.firstChild) {
        container.removeChild(container.firstChild);
      }
    }

    // Deletes: remove elements by DOM ID
    if (ops.deletes) {
      for (var i = 0; i < ops.deletes.length; i++) {
        var el = document.getElementById(ops.deletes[i]);
        if (el) el.parentNode.removeChild(el);
      }
    }

    // Inserts: add new elements (or upsert existing ones)
    if (ops.inserts) {
      for (var j = 0; j < ops.inserts.length; j++) {
        var entry = ops.inserts[j];
        var temp = document.createElement("div");
        temp.innerHTML = entry.html.trim();
        var newEl = temp.firstChild;

        // Upsert: if element with this ID already exists, update it in-place
        var existing = document.getElementById(entry.id);
        if (existing) {
          morphdom(existing, newEl);
        } else if (entry.at === 0) {
          container.insertBefore(newEl, container.firstChild);  // Prepend
        } else {
          container.appendChild(newEl);                          // Append
        }
      }
    }
  }
}
```

### Protecting Stream Children from Morphdom

There's a subtle but critical interaction between morphdom and streams. The template renders the stream container as **empty**:

```html
<div ignite-stream="events"></div>
```

But at runtime, `applyStreamOps` has populated it with children. When morphdom runs on the next update, it compares the current DOM (with children) against the new HTML (empty container) and **removes all children** — wiping out the stream items.

The fix: tell morphdom to skip stream containers entirely in `applyUpdate`:

```javascript
morphdom(container, wrapper, {
  onBeforeElUpdated: function (fromEl, toEl) {
    // Skip stream containers — their children are managed by applyStreamOps
    if (fromEl.hasAttribute("ignite-stream")) {
      return false;
    }
    // ... other checks
  }
});
```

Order matters: `applyUpdate` (morphdom) runs first to ensure the stream container exists in the DOM, then `applyStreamOps` manipulates its children. The `onBeforeElUpdated` guard ensures morphdom doesn't destroy the children that `applyStreamOps` manages.

### Backward Compatibility

Stream operations are only included in the payload when a LiveView uses streams. Existing LiveViews (Counter, Dashboard, etc.) never see a `streams` field — their payloads remain `{"d": {...}}` as before.

## Using It

### The StreamDemoLive Example

**Create `lib/my_app/live/stream_demo_live.ex`:**

```elixir
defmodule MyApp.StreamDemoLive do
  use Ignite.LiveView

  def mount(_params, _session) do
    Process.send_after(self(), :generate_event, 2000)

    assigns = %{event_count: 0}
    assigns = stream(assigns, :events, [],
      limit: 20,
      render: fn event ->
        ~s(<div id="events-#{event.id}">[#{event.type}] #{event.message}</div>)
      end
    )
    {:ok, assigns}
  end

  # Auto-generate a random event every 2 seconds (prepend)
  def handle_info(:generate_event, assigns) do
    Process.send_after(self(), :generate_event, 2000)
    event = %{id: assigns.event_count + 1, type: "info", message: "Auto event"}

    assigns = assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  # Prepend: insert at the top of the list
  def handle_event("add_event", _params, assigns) do
    event = %{id: assigns.event_count + 1, type: "info",
              message: "Manual event (prepended to top)", time: "..."}

    assigns = assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  # Append: insert at the bottom of the list (default behavior)
  def handle_event("append_event", _params, assigns) do
    event = %{id: assigns.event_count + 1, type: "debug",
              message: "Manual event (appended to bottom)", time: "..."}

    assigns = assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event)

    {:noreply, assigns}
  end

  # Upsert: re-insert an item with the same ID — updates in-place
  def handle_event("update_latest", _params, assigns) do
    if assigns.event_count > 0 do
      updated = %{id: assigns.event_count, type: "warning",
                  message: "UPDATED — modified in-place via upsert", time: "..."}
      assigns = stream_insert(assigns, :events, updated, at: 0)
      {:noreply, assigns}
    else
      {:noreply, assigns}
    end
  end

  # Reset: clear all items
  def handle_event("clear_log", _params, assigns) do
    assigns = assigns
      |> Map.put(:event_count, 0)
      |> stream(:events, [], reset: true)

    {:noreply, assigns}
  end
end
```

## Testing

Open the browser's DevTools → Network → WS tab to watch the wire protocol.

### Streams Demo (`/streams`)

Mount: statics/dynamics for the page layout, no stream items yet.

Every 2 seconds, a new event appears:
```json
{"d": {"0": "3"}, "streams": {"events": {"inserts": [{"id": "events-3", "at": 0, "html": "<div id=\"events-3\">...</div>"}]}}}
```

Click "Prepend Event" (inserts at top with `at: 0`):
```json
{"d": {"0": "4"}, "streams": {"events": {"inserts": [{"id": "events-4", "at": 0, "html": "<div id=\"events-4\">...</div>"}]}}}
```

Click "Append Event" (inserts at bottom, no `at` field):
```json
{"d": {"0": "5"}, "streams": {"events": {"inserts": [{"id": "events-5", "html": "<div id=\"events-5\">...</div>"}]}}}
```

Click "Update Latest" (upsert — same ID as latest event, updates in-place):
```json
{"d": {}, "streams": {"events": {"inserts": [{"id": "events-5", "at": 0, "html": "<div id=\"events-5\">UPDATED...</div>"}]}}}
```
Notice the `d` is empty (`{}`) — the event count didn't change, so the sparse diff sends nothing for dynamics.

Click "Clear Log":
```json
{"d": {"0": "0"}, "streams": {"events": {"reset": true}}}
```

### Bandwidth Savings

| Scenario | Without Streams | With Streams | Savings |
|----------|----------------|--------------|---------|
| Add 1 item to 10-item list | ~1500 bytes | ~150 bytes | 90% |
| Add 1 item to 100-item list | ~15000 bytes | ~150 bytes | 99% |
| Add 1 item to 1000-item list | ~150000 bytes | ~150 bytes | 99.9% |
| Clear 100 items | ~15000 bytes (empty re-render) | ~30 bytes (`reset: true`) | 99.8% |

The savings grow linearly with list size. Stream operations are always O(1) regardless of how many items are already in the list.

## Key Elixir Concepts

- **Operation queues**: Instead of storing the full collection, we store a queue of operations (`ops: []`). This is a common pattern in event-sourced systems — track what happened, not the current state.

- **Memory efficiency**: Items are rendered to HTML strings and immediately sent over the wire. The server only retains DOM IDs in the `items` map (~20 bytes per item), not the full item data. This makes streams suitable for lists of thousands of items.

- **Functional accumulation**: Each `stream_insert` call returns new assigns with the operation appended. The handler drains all accumulated operations in one batch via `extract_stream_ops/1`.

- **Separation of concerns**: The `render_fn` stored in the stream struct cleanly separates "what an item looks like" (defined once in mount) from "when items are added" (handle_event/handle_info). The handler orchestrates the rendering without knowing about the item structure.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/live_view/stream.ex` | **New** — `%Stream{}` struct and stream operations |
| `lib/my_app/live/stream_demo_live.ex` | **New** — demo LiveView using streams |
| `lib/ignite/live_view.ex` | **Modified** — added `stream`, `stream_insert`, `stream_delete` API |
| `lib/ignite/live_view/handler.ex` | **Modified** — extract and send stream ops in payloads |
| `lib/ignite/application.ex` | **Modified** — register StreamDemoLive route |
| `lib/my_app/router.ex` | **Modified** — added `/streams` route |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — added streams link |
| `assets/ignite.js` | **Modified** — added `applyStreamOps` for client-side stream handling |

## How Phoenix Does It

Phoenix LiveView's stream system is more sophisticated:

- **`@streams` assign** — Streams are a first-class concept in the socket, not stored in regular assigns
- **HEEx comprehensions** — Items are rendered inline in the template using `<div :for={{dom_id, item} <- @streams.events} id={dom_id}>`, with each item as a separate "rendered" struct
- **Change tracking** — Phoenix tracks which assigns changed and only re-evaluates expressions that reference changed assigns
- **Limits** — `stream(socket, :items, items, limit: 50)` constrains the client-side item count for infinite scroll
- **`stream_configure/3`** — Separate configuration step for custom DOM ID functions
- **DOM patching** — Uses `phx-update="stream"` attribute with specialized DOM patching that handles reordering

Our implementation covers the core concept: operation-based list management with O(1) wire overhead per change.

---

[← Previous: Step 24 - Fine-Grained Diffing](24-fine-grained-diffing.md) | [Next: Step 26 - File Uploads →](26-file-uploads.md)

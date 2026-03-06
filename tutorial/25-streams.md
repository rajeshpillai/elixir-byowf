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
defmodule Ignite.LiveView.Stream do
  defstruct [
    :name,        # atom — the stream name
    :render_fn,   # fn(item) -> html_string
    :dom_prefix,  # string — prefix for DOM IDs (e.g., "events")
    :id_fn,       # fn(item) -> string — extracts unique ID from item
    :limit,       # nil | pos_integer — max items on client (nil = unlimited)
    ops: [],      # pending operations queue
    items: %{},   # %{dom_id => true} — tracks existing DOM IDs
    order: []     # list of dom_ids in insertion order (for limit pruning)
  ]

  def stream(assigns, name, items, opts \\ []) do
    streams = Map.get(assigns, :__streams__, %{})
    existing = Map.get(streams, name)

    render_fn =
      Keyword.get(opts, :render) || (existing && existing.render_fn) ||
        raise ArgumentError,
              "stream #{inspect(name)} requires a :render function on first init"

    id_fn =
      Keyword.get(opts, :id) || (existing && existing.id_fn) ||
        fn item -> to_string(item.id) end

    dom_prefix =
      Keyword.get(opts, :dom_prefix) || (existing && existing.dom_prefix) ||
        to_string(name)

    reset? = Keyword.get(opts, :reset, false)
    at = Keyword.get(opts, :at, -1)
    limit = Keyword.get(opts, :limit) || (existing && existing.limit)

    # Start with existing ops/items/order or empty
    base_ops = if existing && !reset?, do: existing.ops, else: []
    base_items = if existing && !reset?, do: existing.items, else: %{}
    base_order = if existing && !reset?, do: existing.order, else: []

    # Add reset op if requested
    ops = if reset?, do: base_ops ++ [{:reset}], else: base_ops

    # Add insert ops for all provided items (with upsert detection)
    {ops, items_map, order} =
      Enum.reduce(items, {ops, base_items, base_order}, fn item, {acc_ops, acc_items, acc_order} ->
        dom_id = dom_prefix <> "-" <> id_fn.(item)
        is_update = Map.has_key?(acc_items, dom_id)

        new_order =
          if is_update do
            acc_order
          else
            if at == 0, do: [dom_id | acc_order], else: acc_order ++ [dom_id]
          end

        {acc_ops ++ [{:insert, item, dom_id, [at: at]}],
         Map.put(acc_items, dom_id, true),
         new_order}
      end)

    # Apply limit — prune excess items from the opposite end
    {ops, items_map, order} = apply_limit(ops, items_map, order, limit, at)

    stream_struct = %__MODULE__{
      name: name,
      render_fn: render_fn,
      id_fn: id_fn,
      dom_prefix: dom_prefix,
      limit: limit,
      ops: ops,
      items: items_map,
      order: order
    }

    Map.put(assigns, :__streams__, Map.put(streams, name, stream_struct))
  end

  def stream_insert(assigns, name, item, opts \\ []) do
    streams = Map.get(assigns, :__streams__, %{})

    stream = Map.get(streams, name) ||
      raise ArgumentError, "stream #{inspect(name)} not initialized — call stream/4 first"

    dom_id = stream.dom_prefix <> "-" <> stream.id_fn.(item)
    position = Keyword.get(opts, :at, -1)
    is_update = Map.has_key?(stream.items, dom_id)

    # Track insertion order (only for new items)
    new_order =
      if is_update do
        stream.order
      else
        if position == 0, do: [dom_id | stream.order], else: stream.order ++ [dom_id]
      end

    updated = %{stream |
      ops: stream.ops ++ [{:insert, item, dom_id, [at: position]}],
      items: Map.put(stream.items, dom_id, true),
      order: new_order
    }

    # Apply limit after insert
    {ops, items, order} = apply_limit(updated.ops, updated.items, updated.order, stream.limit, position)
    updated = %{updated | ops: ops, items: items, order: order}

    Map.put(assigns, :__streams__, Map.put(streams, name, updated))
  end

  def stream_delete(assigns, name, item) do
    streams = Map.get(assigns, :__streams__, %{})

    stream = Map.get(streams, name) ||
      raise ArgumentError, "stream #{inspect(name)} not initialized — call stream/4 first"

    dom_id = stream.dom_prefix <> "-" <> stream.id_fn.(item)

    updated = %{stream |
      ops: stream.ops ++ [{:delete, dom_id}],
      items: Map.delete(stream.items, dom_id),
      order: List.delete(stream.order, dom_id)
    }

    Map.put(assigns, :__streams__, Map.put(streams, name, updated))
  end

  def extract_stream_ops(assigns) do
    streams = Map.get(assigns, :__streams__, %{})

    if map_size(streams) == 0 do
      {nil, assigns}
    else
      {payload, cleaned_streams} =
        Enum.reduce(streams, {%{}, %{}}, fn {name, stream_data}, {payload_acc, streams_acc} ->
          if stream_data.ops == [] do
            {payload_acc, Map.put(streams_acc, name, stream_data)}
          else
            stream_payload = build_stream_payload(stream_data)
            cleaned = %{stream_data | ops: []}

            {Map.put(payload_acc, to_string(name), stream_payload),
             Map.put(streams_acc, name, cleaned)}
          end
        end)

      if map_size(payload) == 0 do
        {nil, Map.put(assigns, :__streams__, cleaned_streams)}
      else
        {payload, Map.put(assigns, :__streams__, cleaned_streams)}
      end
    end
  end

  # Prunes excess items when a limit is set.
  defp apply_limit(ops, items, order, nil, _at), do: {ops, items, order}

  defp apply_limit(ops, items, order, limit, at) when length(order) > limit do
    excess = length(order) - limit

    {to_prune, to_keep} =
      if at == 0 do
        {Enum.take(order, -excess), Enum.drop(order, -excess)}
      else
        {Enum.take(order, excess), Enum.drop(order, excess)}
      end

    prune_ops = Enum.map(to_prune, fn dom_id -> {:delete, dom_id} end)
    pruned_items = Enum.reduce(to_prune, items, fn dom_id, acc -> Map.delete(acc, dom_id) end)

    {ops ++ prune_ops, pruned_items, to_keep}
  end

  defp apply_limit(ops, items, order, _limit, _at), do: {ops, items, order}

  # Converts the ops queue into a wire-ready map
  defp build_stream_payload(stream) do
    {has_reset, inserts, deletes} =
      Enum.reduce(stream.ops, {false, [], []}, fn
        {:reset}, {_reset, _ins, _del} ->
          {true, [], []}

        {:insert, item, dom_id, opts}, {reset, ins, del} ->
          html = stream.render_fn.(item)
          position = Keyword.get(opts, :at, -1)

          entry = %{"id" => dom_id, "html" => html}
          entry = if position == 0, do: Map.put(entry, "at", 0), else: entry

          {reset, ins ++ [entry], del}

        {:delete, dom_id}, {reset, ins, del} ->
          {reset, ins, del ++ [dom_id]}
      end)

    result = %{}
    result = if has_reset, do: Map.put(result, "reset", true), else: result
    result = if inserts != [], do: Map.put(result, "inserts", inserts), else: result
    result = if deletes != [], do: Map.put(result, "deletes", deletes), else: result
    result
  end
end
```

Key properties:
- `render_fn` is provided once at initialization and reused for every insert
- `ops` accumulates operations between renders, then gets drained by the handler
- `items` tracks only DOM IDs (not item data) — items are freed after being sent
- `order` tracks insertion order so the `limit` feature knows which end to prune from

### Importing the Stream API

**Update `lib/ignite/live_view.ex`** — inside the `__using__` macro, import the stream functions so LiveViews can call them directly:

```elixir
import Ignite.LiveView.Stream, only: [
  stream: 3,
  stream: 4,
  stream_insert: 3,
  stream_insert: 4,
  stream_delete: 3
]
```

This goes alongside the existing imports for `push_redirect`, `live_component`, etc. With this import, any module that does `use Ignite.LiveView` can call `stream/4`, `stream_insert/4`, and `stream_delete/3` without qualifying the module name.

### Handler Integration

**Update `lib/ignite/live_view/handler.ex`** — after rendering, extract stream ops and include them in the payload. This applies to both the mount handler and the event handler.

In `websocket_init` (mount):

```elixir
{statics, dynamics} = Engine.render(view_module, assigns)

# Extract pending stream operations (initial items from mount)
{streams_payload, assigns} = Ignite.LiveView.Stream.extract_stream_ops(assigns)

new_state = %{view: view_module, assigns: assigns, prev_dynamics: dynamics}

# Include streams in mount payload if present
payload_map = %{s: statics, d: dynamics}
payload_map = if streams_payload, do: Map.put(payload_map, :streams, streams_payload), else: payload_map

payload = Jason.encode!(payload_map)
{:reply, {:text, payload}, new_state}
```

In `send_render_update` (after handling events or info messages):

```elixir
diff_payload =
  case Map.get(state, :prev_dynamics) do
    nil -> new_dynamics
    prev -> Engine.diff(prev, new_dynamics)
  end

# Extract pending stream operations
{streams_payload, assigns} = Ignite.LiveView.Stream.extract_stream_ops(assigns)

new_state = %{state | assigns: assigns, prev_dynamics: new_dynamics}

# Include streams in payload if present
payload_map = %{d: diff_payload}
payload_map = if streams_payload, do: Map.put(payload_map, :streams, streams_payload), else: payload_map

payload = Jason.encode!(payload_map)
{:reply, {:text, payload}, new_state}
```

The pattern is the same in both places: call `extract_stream_ops/1` to drain the pending ops queue, then conditionally merge the `streams` key into the payload. When no streams are used, `streams_payload` is `nil` and the payload remains unchanged.

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

  @event_types ["info", "warning", "debug", "error"]

  @impl true
  def mount(_params, _session) do
    Process.send_after(self(), :generate_event, 2000)

    assigns = %{event_count: 0}

    # Initialize the stream with a render function and a limit of 20.
    # :limit caps the client-side DOM — older items are auto-pruned when
    # new ones arrive. The render function defines how each item looks.
    assigns =
      stream(assigns, :events, [],
        limit: 20,
        render: fn event ->
          color = event_color(event.type)

          """
          <div id="events-#{event.id}"
               style="padding: 8px 12px; margin: 4px 0; background: #{color};
                      border-radius: 6px; font-size: 14px; display: flex;
                      justify-content: space-between; align-items: center;">
            <span>
              <strong>[#{String.upcase(event.type)}]</strong> #{event.message}
            </span>
            <span style="color: #888; font-size: 12px;">#{event.time}</span>
          </div>
          """
        end
      )

    {:ok, assigns}
  end

  # Auto-generate a random event every 2 seconds
  @impl true
  def handle_info(:generate_event, assigns) do
    Process.send_after(self(), :generate_event, 2000)
    event = random_event(assigns.event_count + 1)

    assigns =
      assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  @impl true
  def handle_event("add_event", _params, assigns) do
    event = %{
      id: assigns.event_count + 1,
      type: "info",
      message: "Manual event (prepended to top)",
      time: format_time()
    }

    assigns =
      assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event, at: 0)

    {:noreply, assigns}
  end

  @impl true
  def handle_event("append_event", _params, assigns) do
    event = %{
      id: assigns.event_count + 1,
      type: "debug",
      message: "Manual event (appended to bottom)",
      time: format_time()
    }

    assigns =
      assigns
      |> Map.put(:event_count, assigns.event_count + 1)
      |> stream_insert(:events, event)

    {:noreply, assigns}
  end

  # Upsert: re-insert an item with the same ID — updates in-place on the client
  @impl true
  def handle_event("update_latest", _params, assigns) do
    if assigns.event_count > 0 do
      updated_event = %{
        id: assigns.event_count,
        type: "warning",
        message: "UPDATED — this event was modified in-place via upsert",
        time: format_time()
      }

      assigns = stream_insert(assigns, :events, updated_event, at: 0)
      {:noreply, assigns}
    else
      {:noreply, assigns}
    end
  end

  @impl true
  def handle_event("clear_log", _params, assigns) do
    assigns =
      assigns
      |> Map.put(:event_count, 0)
      |> stream(:events, [], reset: true)

    {:noreply, assigns}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div id="stream-demo" style="max-width: 700px; margin: 0 auto;">
      <h1>LiveView Streams Demo</h1>
      <p style="color: #888; font-size: 14px;">
        Events stream in every 2 seconds — only new items are sent over the wire
      </p>

      <div style="display: flex; gap: 12px; margin: 16px 0; align-items: center;">
        <button ignite-click="add_event"
                style="padding: 8px 16px; background: #3498db; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Prepend Event
        </button>
        <button ignite-click="append_event"
                style="padding: 8px 16px; background: #2ecc71; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Append Event
        </button>
        <button ignite-click="update_latest"
                style="padding: 8px 16px; background: #f39c12; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Update Latest
        </button>
        <button ignite-click="clear_log"
                style="padding: 8px 16px; background: #e74c3c; color: white;
                       border: none; border-radius: 6px; cursor: pointer;">
          Clear Log
        </button>
        <span style="color: #666; font-size: 14px;">
          Total events: <strong><%= assigns.event_count %></strong>
        </span>
      </div>

      <div ignite-stream="events"
           style="max-height: 400px; overflow-y: auto; border: 1px solid #eee;
                  border-radius: 8px; padding: 8px;">
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp random_event(id) do
    type = Enum.random(@event_types)

    messages = %{
      "info" => ["System running normally", "Health check passed", "Cache refreshed"],
      "warning" => ["Memory usage high", "Response time slow", "Rate limit approaching"],
      "debug" => ["Query executed in 2ms", "Cache hit ratio: 94%", "GC cycle complete"],
      "error" => ["Connection timeout", "Invalid API key", "File not found"]
    }

    %{id: id, type: type, message: Enum.random(messages[type]), time: format_time()}
  end

  defp format_time do
    {{_, _, _}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end

  defp event_color("info"), do: "#e8f4f8"
  defp event_color("warning"), do: "#fff8e1"
  defp event_color("debug"), do: "#f3e5f5"
  defp event_color("error"), do: "#ffebee"
  defp event_color(_), do: "#f5f5f5"
end
```

### Route Registration

**Update `lib/my_app/router.ex`** — add the `/streams` route:

```elixir
get "/streams", to: MyApp.WelcomeController, action: :streams
```

**Update `lib/ignite/application.ex`** — register the WebSocket endpoint for the LiveView:

```elixir
{"/live/streams", Ignite.LiveView.Handler, %{view: MyApp.StreamDemoLive}}
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

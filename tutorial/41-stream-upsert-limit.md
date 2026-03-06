# Step 41: Stream Upsert & Limit

## What We're Building

Two enhancements to the LiveView Streams system from Step 25:

1. **Upsert** — `stream_insert` now detects if an item with the same ID
   already exists and updates it in-place instead of creating a duplicate.
2. **`:limit`** — cap the number of items on the client. When exceeded,
   items are automatically pruned from the opposite end, enabling
   infinite-scroll and log-tailing patterns without unbounded DOM growth.

After this step, you can write:

```elixir
# Initialize with a limit of 20 items
assigns = stream(assigns, :events, [], limit: 20, render: fn event -> ... end)

# Insert — if event with same ID exists, it updates in-place
assigns = stream_insert(assigns, :events, updated_event)

# When the 21st item arrives, the oldest is automatically pruned
```

## Concepts You'll Learn

### Upsert Pattern

"Upsert" means "insert or update." If a record with the same key already
exists, update it; otherwise, insert it. This is common in databases
(`INSERT ... ON CONFLICT UPDATE`) and UI patterns.

In our streams, the key is the DOM ID (e.g., `"events-42"`). The server
tracks which DOM IDs exist in the `items` map. When `stream_insert` is
called, it checks:

```elixir
is_update = Map.has_key?(stream.items, dom_id)
```

If `true`, the item already exists on the client. The server still emits
an `{:insert, item, dom_id, opts}` operation — but the JS client already
handles this correctly: it finds the existing element by ID and uses
morphdom to patch it in-place.

### Map.has_key?/2

Checks if a map contains a specific key. Returns `true` or `false`:

```elixir
Map.has_key?(%{name: "Rajesh", age: 30}, :name)  #=> true
Map.has_key?(%{name: "Rajesh", age: 30}, :email)  #=> false
```

We use it to detect whether a DOM ID is already tracked (upsert vs new insert).

### List.delete/2

Removes the first occurrence of an element from a list:

```elixir
List.delete([1, 2, 3, 2], 2)  #=> [1, 3, 2]
List.delete([:a, :b, :c], :b)  #=> [:a, :c]
```

We use it to remove a DOM ID from the `order` list when an item is deleted.

### Guard Clause with `when length(list) > limit`

Elixir allows **guard clauses** on function heads to add conditions
beyond pattern matching:

```elixir
defp apply_limit(ops, items, order, limit, at) when length(order) > limit do
  # Only runs when the order list exceeds the limit
end
```

`when` expressions run at match time — if the guard fails, Elixir tries
the next function clause. This lets us have a no-op clause for `nil`
limits and an active clause only when the limit is actually exceeded.

### Enum.take/2 and Enum.drop/2

`Enum.take/2` returns the first N elements (or last N with negative):

```elixir
Enum.take([1, 2, 3, 4, 5], 2)    #=> [1, 2]
Enum.take([1, 2, 3, 4, 5], -2)   #=> [4, 5]
```

`Enum.drop/2` returns everything except the first N (or last N):

```elixir
Enum.drop([1, 2, 3, 4, 5], 2)    #=> [3, 4, 5]
Enum.drop([1, 2, 3, 4, 5], -2)   #=> [1, 2, 3]
```

We use these together to split the order list into "items to keep" and
"items to prune" when the limit is exceeded.

## The Code

### Updated `%Stream{}` Struct

**Update `lib/ignite/live_view/stream.ex`** — add `limit` and `order` fields to the struct:

```elixir
defstruct [
  :name,        # atom — the stream name
  :render_fn,   # fn(item) -> html_string
  :dom_prefix,  # string — prefix for DOM IDs
  :id_fn,       # fn(item) -> string
  :limit,       # nil | pos_integer — max items on client
  ops: [],      # pending operations queue
  items: %{},   # %{dom_id => true} — tracks existing DOM IDs
  order: []     # list of dom_ids in insertion order (for limit pruning)
]
```

The new fields:
- **`limit`** — `nil` means unlimited (backward-compatible). A positive
  integer caps client-side items.
- **`order`** — tracks DOM IDs in the order they were inserted. When the
  limit is exceeded, we know which items are oldest and should be pruned.

### Upsert in `stream_insert/4`

**Update `lib/ignite/live_view/stream.ex`** — the key change in `stream_insert`:

```elixir
dom_id = stream.dom_prefix <> "-" <> stream.id_fn.(item)
is_update = Map.has_key?(stream.items, dom_id)

# Track insertion order (only for new items)
new_order =
  if is_update do
    stream.order  # Don't change order for updates
  else
    if position == 0, do: [dom_id | stream.order], else: stream.order ++ [dom_id]
  end
```

The insert operation is always emitted (the client needs the new HTML
either way), but we only add to the order list for genuinely new items.

### Limit Enforcement with `apply_limit/5`

**Update `lib/ignite/live_view/stream.ex`** — add the `apply_limit` helper:

```elixir
defp apply_limit(ops, items, order, nil, _at), do: {ops, items, order}

defp apply_limit(ops, items, order, limit, at) when length(order) > limit do
  excess = length(order) - limit

  # Prune from the opposite end of where inserts happen
  {to_prune, to_keep} =
    if at == 0 do
      # Inserting at front -> prune from end
      {Enum.take(order, -excess), Enum.drop(order, -excess)}
    else
      # Appending -> prune from front
      {Enum.take(order, excess), Enum.drop(order, excess)}
    end

  prune_ops = Enum.map(to_prune, fn dom_id -> {:delete, dom_id} end)
  pruned_items = Enum.reduce(to_prune, items, fn dom_id, acc -> Map.delete(acc, dom_id) end)

  {ops ++ prune_ops, pruned_items, to_keep}
end

defp apply_limit(ops, items, order, _limit, _at), do: {ops, items, order}
```

The three clauses:
1. `nil` limit — no-op (unlimited)
2. Limit exceeded — compute excess, determine which end to prune, emit
   delete operations
3. Within limit — no-op

The pruning direction is intentional:
- If you prepend items (`at: 0`), the oldest items are at the **bottom**,
  so prune from the end of the order list.
- If you append items (`at: -1`), the oldest items are at the **top**,
  so prune from the front of the order list.

### Updated Stream Demo

**Update `lib/my_app/live/stream_demo_live.ex`** — add `limit: 20` to the stream init and an "Update Latest" button:

```elixir
# In mount:
assigns = stream(assigns, :events, [], limit: 20, render: fn event -> ... end)

# New event handler for upsert demo:
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
```

The key insight: `updated_event` has the same `id` as the last event that
was inserted. Since the DOM ID (`events-42`) already exists in the stream's
`items` map, `stream_insert` emits an insert op but doesn't add to the
order list or trigger limit pruning.

### No JS Changes Needed

The client-side code from Step 25 already handles upsert correctly.
Looking at the `applyStreamOps` function in `ignite.js`:

```javascript
// If element with this ID already exists, update it
var existing = document.getElementById(entry.id);
if (existing) {
  morphdom(existing, newEl, { ... });  // Update in-place
} else if (entry.at === 0) {
  container.insertBefore(newEl, container.firstChild);  // Prepend
} else {
  container.appendChild(newEl);  // Append
}
```

It already checks for existing elements by ID and morphs them. The limit
feature works because prune operations are sent as regular deletes — the
JS `deletes` handler removes elements by ID.

## How It Works

### Upsert Flow

```
1. stream_insert(assigns, :events, %{id: 5, message: "Updated"})
2. DOM ID = "events-5"
3. Map.has_key?(stream.items, "events-5") → true (already exists)
4. Emit {:insert, item, "events-5", [at: 0]} op
5. Don't add to order list (not a new item)
6. Wire: {"streams": {"events": {"inserts": [{"id": "events-5", "html": "..."}]}}}
7. JS: document.getElementById("events-5") exists → morphdom patches it
```

### Limit Pruning Flow

```
1. Stream has limit: 20, currently 20 items, inserting at: 0
2. stream_insert adds item → order has 21 items
3. apply_limit detects excess = 1
4. at == 0, so prune from end: to_prune = [last_dom_id]
5. Emit {:delete, last_dom_id} op
6. Remove from items map and order list
7. Wire includes both: insert (new item) + delete (pruned item)
8. JS: inserts new item at top, removes oldest item from bottom
```

## Try It Out

1. Start the server:

```bash
iex -S mix
```

2. Visit http://localhost:4000/streams

3. **Test limit**: Watch events auto-generate every 2 seconds. After 20
   events, new ones appear at the top while old ones disappear from the
   bottom. The list never grows beyond 20 items.

4. **Test upsert**: Click "Update Latest" — the most recent event changes
   to a yellow warning saying "UPDATED — this event was modified in-place
   via upsert". No new item is added; the existing one is patched.

5. **Inspect the wire**: Open DevTools → Network → WS tab. When the limit
   kicks in, you'll see payloads like:
   ```json
   {
     "d": {"0": "21"},
     "streams": {
       "events": {
         "inserts": [{"id": "events-21", "at": 0, "html": "..."}],
         "deletes": ["events-1"]
       }
     }
   }
   ```
   Both an insert (new item) and a delete (pruned item) in the same message.

6. Click "Clear Log" — resets as before.

## Phoenix Comparison

| Feature | Phoenix LiveView | Ignite (after this step) |
|---------|-----------------|-------------------------|
| Upsert by DOM ID | Yes | Yes |
| `:limit` option | Yes | Yes |
| Arbitrary position (`at: N`) | Yes | Prepend/append only |
| Reordering (move items) | Yes | No |
| HEEx template integration | Yes (`:for` comprehension) | Separate render function |
| `stream_configure/3` | Yes | No (config via `stream/4` opts) |

The two biggest gaps (upsert and limit) are now closed. The remaining
differences are mostly about ergonomics (HEEx integration) and edge
cases (arbitrary positioning, reordering).

## File Checklist

| File | Status | Purpose |
|------|--------|---------|
| `lib/ignite/live_view/stream.ex` | **Modified** | Added `limit`, `order` fields, upsert detection, `apply_limit/5` |
| `lib/my_app/live/stream_demo_live.ex` | **Modified** | Added `limit: 20`, "Update Latest" button for upsert demo |

---

[← Previous: Step 40 - Deployment with `mix release` + Rate Limiting](40-release-and-rate-limit.md)

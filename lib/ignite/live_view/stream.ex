defmodule Ignite.LiveView.Stream do
  @moduledoc """
  Manages efficiently-diffed collections in LiveView.

  Streams allow you to work with large lists without holding all items
  in server memory or re-sending the entire list on every update.
  Instead, only insert/delete operations are sent over the wire.

  ## How It Works

  1. Initialize a stream with `stream/4` — provide a name, initial items,
     and a `:render` function that converts each item to HTML.
  2. Insert or update items with `stream_insert/3,4` — appends by default,
     prepends with `at: 0`, or updates in-place if the item already exists
     (upsert by DOM ID).
  3. Delete items with `stream_delete/3`.
  4. Reset the entire stream with `stream/4` and `reset: true`.
  5. Limit client-side items with `stream/4` and `limit: N` — excess items
     are automatically pruned from the opposite end of insertion.

  Stream state is stored in `assigns.__streams__` and processed by the
  handler after each render cycle. Items are freed from server memory
  after being rendered and sent — only their DOM IDs are retained.

  ## Example

      def mount(_params, _session) do
        assigns = stream(%{event_count: 0}, :events, [],
          render: fn event ->
            ~s(<div id="events-\#{event.id}">\#{event.text}</div>)
          end
        )
        {:ok, assigns}
      end

      def handle_event("add", _params, assigns) do
        event = %{id: assigns.event_count + 1, text: "New event"}
        assigns = assigns
          |> Map.put(:event_count, assigns.event_count + 1)
          |> stream_insert(:events, event, at: 0)
        {:noreply, assigns}
      end
  """

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

  @doc """
  Initializes or resets a stream in the assigns.

  ## Options

    - `:render` (required on first init) — `fn item -> html_string end`
    - `:id` — `fn item -> string end` (default: `fn i -> to_string(i.id) end`)
    - `:dom_prefix` — string prefix for DOM IDs (default: stream name as string)
    - `:reset` — if `true`, clears all existing items before inserting
    - `:at` — insertion position for items: `-1` for append (default), `0` for prepend
    - `:limit` — max number of items on the client. When exceeded, items are
      pruned from the opposite end (prepend with limit prunes from the end)

  ## Examples

      # Initialize with items and a render function
      assigns = stream(assigns, :messages, messages,
        render: fn msg -> ~s(<li id="messages-\#{msg.id}">\#{msg.text}</li>) end
      )

      # Reset stream with new items
      assigns = stream(assigns, :messages, new_messages, reset: true)

      # Initialize empty stream
      assigns = stream(assigns, :events, [],
        render: fn event -> ~s(<div id="events-\#{event.id}">\#{event.text}</div>) end
      )
  """
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

  @doc """
  Inserts or updates an item in a stream (upsert).

  If an item with the same DOM ID already exists, it is updated in-place
  (the client replaces the existing element). If it's new, it is inserted
  at the specified position.

  ## Options

    - `:at` — position to insert. Default is `-1` (append). Use `0` to prepend.
      Ignored for updates (existing items stay in their current position).

  ## Examples

      assigns = stream_insert(assigns, :events, new_event)
      assigns = stream_insert(assigns, :events, new_event, at: 0)  # prepend
      assigns = stream_insert(assigns, :events, updated_event)     # upsert
  """
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

  @doc """
  Deletes an item from a stream.

  The item must have an `id` field (or match the stream's `:id` function).

  ## Examples

      assigns = stream_delete(assigns, :events, event)
  """
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

  @doc """
  Extracts pending stream operations and builds the wire payload.

  Called by the handler after each render cycle. Returns
  `{streams_payload, cleaned_assigns}` where `streams_payload` is a map
  ready for JSON encoding (or `nil` if no operations pending), and
  `cleaned_assigns` has the ops queues cleared.
  """
  def extract_stream_ops(assigns) do
    streams = Map.get(assigns, :__streams__, %{})

    if map_size(streams) == 0 do
      {nil, assigns}
    else
      {payload, cleaned_streams} =
        Enum.reduce(streams, {%{}, %{}}, fn {name, stream_data}, {payload_acc, streams_acc} ->
          if stream_data.ops == [] do
            # No pending ops — keep stream state, skip in payload
            {payload_acc, Map.put(streams_acc, name, stream_data)}
          else
            # Process ops into wire format
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
  # If inserting at the front (at: 0), prune from the end (oldest at bottom).
  # If appending (at: -1), prune from the front (oldest at top).
  defp apply_limit(ops, items, order, nil, _at), do: {ops, items, order}

  defp apply_limit(ops, items, order, limit, at) when length(order) > limit do
    excess = length(order) - limit

    # Prune from the opposite end of where inserts happen
    {to_prune, to_keep} =
      if at == 0 do
        # Inserting at front → prune from end
        {Enum.take(order, -excess), Enum.drop(order, -excess)}
      else
        # Appending → prune from front
        {Enum.take(order, excess), Enum.drop(order, excess)}
      end

    prune_ops = Enum.map(to_prune, fn dom_id -> {:delete, dom_id} end)
    pruned_items = Enum.reduce(to_prune, items, fn dom_id, acc -> Map.delete(acc, dom_id) end)

    {ops ++ prune_ops, pruned_items, to_keep}
  end

  defp apply_limit(ops, items, order, _limit, _at), do: {ops, items, order}

  # Converts the ops queue into a wire-ready map:
  # %{"reset" => true, "inserts" => [...], "deletes" => [...]}
  defp build_stream_payload(stream) do
    {has_reset, inserts, deletes} =
      Enum.reduce(stream.ops, {false, [], []}, fn
        {:reset}, {_reset, _ins, _del} ->
          # Reset clears previously queued inserts/deletes
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

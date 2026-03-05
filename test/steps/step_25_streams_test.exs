defmodule Step25.StreamsTest do
  @moduledoc """
  Step 25 — Streams

  TDD spec: LiveView streams should efficiently manage collections
  with insert, update (upsert), delete, and reset operations
  without holding all items in memory.
  """
  use ExUnit.Case

  alias Ignite.LiveView.Stream

  defp render_fn do
    fn item -> ~s(<div id="items-#{item.id}">#{item.name}</div>) end
  end

  describe "stream/4 initialization" do
    test "initializes a stream with items" do
      assigns = Stream.stream(%{}, :items, [%{id: 1, name: "a"}, %{id: 2, name: "b"}],
        render: render_fn()
      )

      stream = assigns.__streams__[:items]
      assert stream.name == :items
      assert Map.has_key?(stream.items, "items-1")
      assert Map.has_key?(stream.items, "items-2")
      assert length(stream.ops) == 2
    end

    test "initializes empty stream" do
      assigns = Stream.stream(%{}, :items, [], render: render_fn())
      stream = assigns.__streams__[:items]
      assert stream.items == %{}
      assert stream.ops == []
    end

    test "raises without render function on first init" do
      assert_raise ArgumentError, ~r/requires a :render function/, fn ->
        Stream.stream(%{}, :items, [])
      end
    end
  end

  describe "stream_insert/3,4" do
    test "appends item by default" do
      assigns =
        %{}
        |> Stream.stream(:items, [], render: render_fn())
        |> Stream.stream_insert(:items, %{id: 1, name: "first"})

      stream = assigns.__streams__[:items]
      assert Map.has_key?(stream.items, "items-1")
      [{:insert, item, dom_id, opts}] = stream.ops
      assert item.name == "first"
      assert dom_id == "items-1"
      assert Keyword.get(opts, :at) == -1
    end

    test "prepends with at: 0" do
      assigns =
        %{}
        |> Stream.stream(:items, [], render: render_fn())
        |> Stream.stream_insert(:items, %{id: 1, name: "first"}, at: 0)

      [{:insert, _, _, opts}] = assigns.__streams__[:items].ops
      assert Keyword.get(opts, :at) == 0
    end

    test "upserts existing item (same DOM ID)" do
      assigns =
        %{}
        |> Stream.stream(:items, [%{id: 1, name: "original"}], render: render_fn())
        |> Stream.stream_insert(:items, %{id: 1, name: "updated"})

      stream = assigns.__streams__[:items]
      # Should have 2 ops: initial insert + upsert
      assert length(stream.ops) == 2
      # Both ops reference same DOM ID
      dom_ids = Enum.map(stream.ops, fn {:insert, _, dom_id, _} -> dom_id end)
      assert dom_ids == ["items-1", "items-1"]
    end
  end

  describe "stream_delete/3" do
    test "removes item and adds delete op" do
      assigns =
        %{}
        |> Stream.stream(:items, [%{id: 1, name: "doomed"}], render: render_fn())
        |> Stream.stream_delete(:items, %{id: 1})

      stream = assigns.__streams__[:items]
      refute Map.has_key?(stream.items, "items-1")

      # Last op should be a delete
      last_op = List.last(stream.ops)
      assert last_op == {:delete, "items-1"}
    end
  end

  describe "stream/4 with reset" do
    test "reset clears existing items and adds reset op" do
      assigns =
        %{}
        |> Stream.stream(:items, [%{id: 1, name: "old"}], render: render_fn())

      # Extract ops to clear them (simulating a render cycle)
      {_payload, assigns} = Stream.extract_stream_ops(assigns)

      # Reset with new items
      assigns = Stream.stream(assigns, :items, [%{id: 2, name: "new"}], reset: true)
      stream = assigns.__streams__[:items]

      # Should have reset op + insert op
      ops_types = Enum.map(stream.ops, fn
        {:reset} -> :reset
        {:insert, _, _, _} -> :insert
        {:delete, _} -> :delete
      end)

      assert :reset in ops_types
      assert :insert in ops_types
    end
  end

  describe "extract_stream_ops/1" do
    test "builds wire payload and clears ops" do
      assigns =
        %{}
        |> Stream.stream(:items, [%{id: 1, name: "hello"}], render: render_fn())

      {payload, cleaned} = Stream.extract_stream_ops(assigns)

      assert is_map(payload["items"])
      inserts = payload["items"]["inserts"]
      assert length(inserts) == 1
      assert hd(inserts)["id"] == "items-1"
      assert hd(inserts)["html"] =~ "hello"

      # Ops should be cleared
      assert cleaned.__streams__[:items].ops == []
    end

    test "returns nil payload when no ops pending" do
      assigns =
        %{}
        |> Stream.stream(:items, [%{id: 1, name: "x"}], render: render_fn())

      {_payload, assigns} = Stream.extract_stream_ops(assigns)
      {payload, _assigns} = Stream.extract_stream_ops(assigns)
      assert payload == nil
    end
  end

  describe "stream/4 with limit" do
    test "prunes excess items from opposite end when appending" do
      assigns =
        %{}
        |> Stream.stream(:items,
          [%{id: 1, name: "a"}, %{id: 2, name: "b"}, %{id: 3, name: "c"}],
          render: render_fn(),
          limit: 2
        )

      stream = assigns.__streams__[:items]
      # Should have pruned item 1 (oldest when appending)
      refute Map.has_key?(stream.items, "items-1")
      assert Map.has_key?(stream.items, "items-2")
      assert Map.has_key?(stream.items, "items-3")
    end
  end
end

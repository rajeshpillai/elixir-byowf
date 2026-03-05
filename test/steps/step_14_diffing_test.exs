defmodule Step14.DiffingTest do
  @moduledoc """
  Step 14 — Diffing Engine

  TDD spec: The engine should split rendered HTML into statics
  (unchanging template parts) and dynamics (variable values),
  then compute sparse diffs to minimize wire payload.
  """
  use ExUnit.Case

  alias Ignite.LiveView.Engine

  describe "diff/2" do
    test "returns empty map when nothing changed" do
      old = ["42", "hello"]
      new = ["42", "hello"]
      assert Engine.diff(old, new) == %{}
    end

    test "returns sparse map for partial changes" do
      old = ["42", "hello", "world"]
      new = ["42", "hello", "WORLD"]
      assert Engine.diff(old, new) == %{"2" => "WORLD"}
    end

    test "returns only changed indices" do
      old = ["a", "b", "c", "d"]
      new = ["a", "B", "c", "D"]
      diff = Engine.diff(old, new)
      assert diff == %{"1" => "B", "3" => "D"}
    end

    test "returns full list when all dynamics changed" do
      old = ["a", "b"]
      new = ["x", "y"]
      assert Engine.diff(old, new) == ["x", "y"]
    end

    test "returns full list when structure changed (different lengths)" do
      old = ["a", "b"]
      new = ["a", "b", "c"]
      assert Engine.diff(old, new) == ["a", "b", "c"]
    end

    test "handles single dynamic" do
      old = ["42"]
      new = ["43"]
      # All changed (1 out of 1) → returns as list
      assert Engine.diff(old, new) == ["43"]
    end

    test "handles single dynamic unchanged" do
      assert Engine.diff(["42"], ["42"]) == %{}
    end
  end

  describe "normalize (via render)" do
    defmodule StringView do
      def render(_assigns), do: "<h1>Hello</h1>"
    end

    test "wraps plain string in empty statics" do
      {statics, dynamics} = Engine.render(StringView, %{})
      assert statics == ["", ""]
      assert dynamics == ["<h1>Hello</h1>"]
    end
  end

  describe "normalize (via %Rendered{})" do
    defmodule RenderedView do
      def render(assigns) do
        %Ignite.LiveView.Rendered{
          statics: ["<h1>Count: ", "</h1>"],
          dynamics: [to_string(assigns[:count])]
        }
      end
    end

    test "uses statics and dynamics from %Rendered{}" do
      {statics, dynamics} = Engine.render(RenderedView, %{count: 42})
      assert statics == ["<h1>Count: ", "</h1>"]
      assert dynamics == ["42"]
    end

    test "render_dynamics returns only dynamics" do
      dynamics = Engine.render_dynamics(RenderedView, %{count: 99})
      assert dynamics == ["99"]
    end
  end
end

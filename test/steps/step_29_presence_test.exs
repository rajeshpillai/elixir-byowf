defmodule Step29.PresenceTest do
  @moduledoc """
  Step 29 — Presence

  TDD spec: Presence should track which processes are connected
  to which topics, with metadata. When a process dies, it should
  be automatically removed.
  """
  use ExUnit.Case

  # Presence is started by the application supervisor.

  describe "track/3 and list/1" do
    test "tracks a process with metadata" do
      topic = "test:presence:#{System.unique_integer()}"
      Ignite.Presence.track(topic, "user_1", %{name: "Jose"})

      result = Ignite.Presence.list(topic)
      assert result["user_1"] == %{name: "Jose"}
    end

    test "tracks multiple processes" do
      topic = "test:presence:multi:#{System.unique_integer()}"
      Ignite.Presence.track(topic, "user_1", %{name: "Jose"})

      # Track a second user from a different process
      task =
        Task.async(fn ->
          Ignite.Presence.track(topic, "user_2", %{name: "Chris"})
          Process.sleep(500)
        end)

      Process.sleep(50)
      result = Ignite.Presence.list(topic)
      assert map_size(result) == 2
      assert result["user_1"] == %{name: "Jose"}
      assert result["user_2"] == %{name: "Chris"}

      Task.await(task)
    end

    test "returns empty map for unknown topic" do
      assert Ignite.Presence.list("nonexistent:#{System.unique_integer()}") == %{}
    end
  end

  describe "untrack/2" do
    test "removes presence" do
      topic = "test:presence:untrack:#{System.unique_integer()}"
      Ignite.Presence.track(topic, "user_1", %{name: "Jose"})
      assert map_size(Ignite.Presence.list(topic)) == 1

      Ignite.Presence.untrack(topic, "user_1")
      assert Ignite.Presence.list(topic) == %{}
    end
  end

  describe "automatic cleanup on process death" do
    test "removes presence when tracked process exits" do
      topic = "test:presence:death:#{System.unique_integer()}"

      task =
        Task.async(fn ->
          Ignite.Presence.track(topic, "ephemeral", %{name: "Ghost"})
        end)

      Task.await(task)

      # Give the DOWN message time to be processed
      Process.sleep(100)

      result = Ignite.Presence.list(topic)
      refute Map.has_key?(result, "ephemeral")
    end
  end

  describe "metadata update" do
    test "re-tracking updates metadata" do
      topic = "test:presence:update:#{System.unique_integer()}"
      Ignite.Presence.track(topic, "user_1", %{name: "Jose", status: "online"})
      Ignite.Presence.track(topic, "user_1", %{name: "Jose", status: "away"})

      result = Ignite.Presence.list(topic)
      assert result["user_1"][:status] == "away"
    end
  end
end

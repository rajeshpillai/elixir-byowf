defmodule Step17.PubSubTest do
  @moduledoc """
  Step 17 — PubSub

  TDD spec: Processes should be able to subscribe to topics
  and broadcast messages to all other subscribers. Dead
  processes are automatically removed by `:pg`.
  """
  use ExUnit.Case

  # PubSub is started by the application supervisor,
  # so it's already running during tests.

  describe "subscribe/1 and broadcast/2" do
    test "subscriber receives broadcast messages" do
      topic = "test:pubsub:#{System.unique_integer()}"
      Ignite.PubSub.subscribe(topic)

      # Spawn another process that broadcasts
      test_pid = self()

      spawn(fn ->
        Ignite.PubSub.subscribe(topic)
        Ignite.PubSub.broadcast(topic, {:hello, "world"})
        send(test_pid, :done)
      end)

      assert_receive :done, 1000
      assert_receive {:hello, "world"}, 1000
    end

    test "broadcaster does not receive its own message" do
      topic = "test:pubsub:self:#{System.unique_integer()}"
      Ignite.PubSub.subscribe(topic)
      Ignite.PubSub.broadcast(topic, :echo_test)

      refute_receive :echo_test, 200
    end

    test "unsubscribed processes don't receive messages" do
      topic = "test:pubsub:unsub:#{System.unique_integer()}"
      # Don't subscribe, just broadcast
      Ignite.PubSub.broadcast(topic, :ghost)
      refute_receive :ghost, 200
    end
  end
end

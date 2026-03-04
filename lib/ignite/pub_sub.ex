defmodule Ignite.PubSub do
  @moduledoc """
  A lightweight publish/subscribe system built on Erlang's `:pg` (process groups).

  Allows LiveView processes to broadcast messages to each other in real time.
  When a process dies (e.g. WebSocket disconnects), `:pg` automatically removes
  it from all groups — no manual cleanup needed.

  ## Example

      # In a LiveView's mount:
      Ignite.PubSub.subscribe("chat_room")

      # To broadcast to all other subscribers:
      Ignite.PubSub.broadcast("chat_room", {:new_message, "Hello!"})

      # In handle_info, receive the broadcast:
      def handle_info({:new_message, text}, assigns) do
        {:noreply, %{assigns | messages: assigns.messages ++ [text]}}
      end
  """

  @doc "Starts the `:pg` scope under the supervision tree."
  def start_link(_opts) do
    :pg.start_link(__MODULE__)
  end

  @doc "Subscribes the calling process to the given topic."
  def subscribe(topic) do
    :pg.join(__MODULE__, topic, self())
  end

  @doc """
  Broadcasts a message to all subscribers of the given topic,
  excluding the sender (to avoid echo loops).
  """
  def broadcast(topic, message) do
    for pid <- :pg.get_members(__MODULE__, topic), pid != self() do
      send(pid, message)
    end

    :ok
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end
end

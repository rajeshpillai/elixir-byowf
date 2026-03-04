defmodule Ignite.Application do
  @moduledoc """
  The OTP Application for Ignite.

  Starts Cowboy as the HTTP server with our custom handler.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = 4000

    # Tell Cowboy to route ALL requests to our adapter
    dispatch =
      :cowboy_router.compile([
        {:_, [{"/[...]", Ignite.Adapters.Cowboy, []}]}
      ])

    children = [
      # Start Cowboy under our supervision tree
      %{
        id: :cowboy_listener,
        start:
          {:cowboy, :start_clear,
           [
             :ignite_http,
             [port: port],
             %{env: %{dispatch: dispatch}}
           ]}
      }
    ]

    Logger.info("Ignite is heating up on http://localhost:#{port}")

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

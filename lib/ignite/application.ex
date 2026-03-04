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

    # Cowboy routing: WebSocket, static files, and HTTP
    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"/live", Ignite.LiveView.Handler, %{view: MyApp.CounterLive}},
           {"/assets/[...]", :cowboy_static, {:dir, "assets"}},
           {"/[...]", Ignite.Adapters.Cowboy, []}
         ]}
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

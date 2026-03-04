defmodule Ignite.Application do
  @moduledoc """
  The OTP Application for Ignite.

  Starts Cowboy as the HTTP server with our custom handler.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:ignite, :port, 4000)

    # Build static asset manifest (file hashes for cache-busting URLs).
    # Must run before Cowboy starts accepting requests.
    Ignite.Static.init()

    # Cowboy routing: WebSocket, static files, and HTTP
    dispatch =
      :cowboy_router.compile([
        {:_,
         [
           {"/live", Ignite.LiveView.Handler, %{view: MyApp.CounterLive}},
           {"/live/register", Ignite.LiveView.Handler, %{view: MyApp.RegistrationLive}},
           {"/live/dashboard", Ignite.LiveView.Handler, %{view: MyApp.DashboardLive}},
           {"/live/shared-counter", Ignite.LiveView.Handler, %{view: MyApp.SharedCounterLive}},
           {"/live/components", Ignite.LiveView.Handler, %{view: MyApp.ComponentsDemoLive}},
           {"/live/hooks", Ignite.LiveView.Handler, %{view: MyApp.HooksDemoLive}},
           {"/live/streams", Ignite.LiveView.Handler, %{view: MyApp.StreamDemoLive}},
           {"/live/upload-demo", Ignite.LiveView.Handler, %{view: MyApp.UploadDemoLive}},
           {"/live/presence", Ignite.LiveView.Handler, %{view: MyApp.PresenceDemoLive}},
           {"/assets/[...]", :cowboy_static, {:dir, "assets"}},
           {"/uploads/[...]", :cowboy_static, {:dir, "uploads"}},
           {"/[...]", Ignite.Adapters.Cowboy, []}
         ]}
      ])

    children =
      [
        # Start the database connection pool first
        MyApp.Repo,
        # Start PubSub before Cowboy so it's available when LiveViews mount
        Ignite.PubSub,
        # Start Presence after PubSub (it broadcasts diffs via PubSub)
        Ignite.Presence,

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
      ] ++ dev_children()

    Logger.info("Ignite is heating up on http://localhost:#{port}")

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Only start the reloader in dev mode
  defp dev_children do
    if Mix.env() == :dev do
      [{Ignite.Reloader, [path: "lib"]}]
    else
      []
    end
  end
end

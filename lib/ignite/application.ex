defmodule Ignite.Application do
  @moduledoc """
  The OTP Application for Ignite.

  Starts Cowboy as the HTTP server (or HTTPS when SSL is configured)
  with our custom handler.
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
           {"/live/todo", Ignite.LiveView.Handler, %{view: TodoApp.TodoLive}},
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

        # Start rate limiter before Cowboy (must be ready for first request)
        Ignite.RateLimiter,

        # Start Cowboy — HTTP or HTTPS depending on :ssl config
        Ignite.SSL.child_spec(port, dispatch)
      ] ++ redirect_children(port) ++ dev_children()

    scheme = if Ignite.SSL.ssl_configured?(), do: "https", else: "http"
    Logger.info("Ignite is heating up on #{scheme}://localhost:#{port}")

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Optional HTTP→HTTPS redirect listener (only when SSL is configured).
  # Set `config :ignite, http_redirect_port: 4080` to enable.
  defp redirect_children(https_port) do
    http_port = Application.get_env(:ignite, :http_redirect_port)

    if http_port && Ignite.SSL.ssl_configured?() do
      Logger.info("HTTP→HTTPS redirect on port #{http_port}")
      [Ignite.SSL.redirect_child_spec(http_port, https_port)]
    else
      []
    end
  end

  # Only start the reloader in dev mode.
  # Uses Application config instead of Mix.env() so this works in releases
  # (Mix is not available at runtime in a release).
  defp dev_children do
    if Application.get_env(:ignite, :env) == :dev do
      [{Ignite.Reloader, [path: "lib"]}]
    else
      []
    end
  end
end

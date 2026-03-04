defmodule MyApp.Router do
  @moduledoc """
  The application router — maps URLs to controller actions.
  """

  use Ignite.Router
  require Logger

  # Middleware — runs before every request, in order
  plug :log_request
  plug :add_server_header

  # Routes
  get "/", to: MyApp.WelcomeController, action: :index
  get "/hello", to: MyApp.WelcomeController, action: :hello
  get "/users/:id", to: MyApp.UserController, action: :show
  get "/crash", to: MyApp.WelcomeController, action: :crash
  post "/users", to: MyApp.UserController, action: :create

  # This must be the last line — it catches everything that didn't match above
  finalize_routes()

  # --- Plug Implementations ---

  def log_request(conn) do
    Logger.info("[Ignite] #{conn.method} #{conn.path}")
    conn
  end

  def add_server_header(conn) do
    new_headers = Map.put(conn.resp_headers, "x-powered-by", "Ignite")
    %Ignite.Conn{conn | resp_headers: new_headers}
  end
end

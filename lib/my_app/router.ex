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
  get "/counter", to: MyApp.WelcomeController, action: :counter
  get "/register", to: MyApp.WelcomeController, action: :register
  get "/dashboard", to: MyApp.WelcomeController, action: :dashboard
  get "/shared-counter", to: MyApp.WelcomeController, action: :shared_counter
  get "/components", to: MyApp.WelcomeController, action: :components
  get "/hooks", to: MyApp.WelcomeController, action: :hooks
  get "/streams", to: MyApp.WelcomeController, action: :streams
  post "/users", to: MyApp.UserController, action: :create
  put "/users/:id", to: MyApp.UserController, action: :update
  patch "/users/:id", to: MyApp.UserController, action: :update
  delete "/users/:id", to: MyApp.UserController, action: :delete

  # API routes (JSON) — grouped under /api using scope
  scope "/api" do
    get "/status", to: MyApp.ApiController, action: :status
    post "/echo", to: MyApp.ApiController, action: :echo
  end

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

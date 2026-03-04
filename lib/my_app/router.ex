defmodule MyApp.Router do
  @moduledoc """
  The application router — maps URLs to controller actions.
  """

  use Ignite.Router
  require Logger

  # Middleware — runs before every request, in order
  # Note: request logging (with request_id + timing) is now handled by the
  # Cowboy adapter, so we no longer need a log_request plug here.
  plug :add_server_header
  plug :set_csp_headers
  plug :verify_csrf_token

  # Routes
  get "/", to: MyApp.WelcomeController, action: :index
  get "/hello", to: MyApp.WelcomeController, action: :hello
  get "/crash", to: MyApp.WelcomeController, action: :crash
  get "/counter", to: MyApp.WelcomeController, action: :counter
  get "/register", to: MyApp.WelcomeController, action: :register
  get "/dashboard", to: MyApp.WelcomeController, action: :dashboard
  get "/shared-counter", to: MyApp.WelcomeController, action: :shared_counter
  get "/components", to: MyApp.WelcomeController, action: :components
  get "/hooks", to: MyApp.WelcomeController, action: :hooks
  get "/streams", to: MyApp.WelcomeController, action: :streams
  get "/upload", to: MyApp.UploadController, action: :upload_form
  post "/upload", to: MyApp.UploadController, action: :upload
  get "/upload-demo", to: MyApp.WelcomeController, action: :upload_demo
  get "/presence", to: MyApp.WelcomeController, action: :presence
  get "/health", to: MyApp.ApiController, action: :health

  # Resource routes — expands into GET/POST/PUT/PATCH/DELETE for users
  resources "/users", MyApp.UserController

  # API routes (JSON) — grouped under /api using scope
  scope "/api" do
    get "/status", to: MyApp.ApiController, action: :status
    post "/echo", to: MyApp.ApiController, action: :echo
  end

  # This must be the last line — it catches everything that didn't match above
  finalize_routes()

  # --- Plug Implementations ---

  def add_server_header(conn) do
    new_headers = Map.put(conn.resp_headers, "x-powered-by", "Ignite")
    %Ignite.Conn{conn | resp_headers: new_headers}
  end

  @doc """
  Content Security Policy plug.

  Generates a per-request nonce and sets the `content-security-policy`
  response header. Inline `<script>` tags must include `nonce="..."` to
  be allowed by the browser.
  """
  def set_csp_headers(conn) do
    Ignite.CSP.put_csp_headers(conn)
  end

  @doc """
  CSRF protection plug.

  Allows safe HTTP methods (GET, HEAD, OPTIONS) through without checks.
  For state-changing methods (POST, PUT, PATCH, DELETE), validates that
  the `_csrf_token` form parameter matches the token stored in the session.

  JSON API requests (content-type: application/json) are exempt — they
  rely on SameSite cookies and browser CORS policy instead.
  """
  def verify_csrf_token(%Ignite.Conn{method: method} = conn)
      when method in ["GET", "HEAD", "OPTIONS"] do
    conn
  end

  def verify_csrf_token(conn) do
    content_type = Map.get(conn.headers, "content-type", "")

    if String.starts_with?(content_type, "application/json") do
      # JSON APIs are exempt — protected by SameSite cookies + CORS
      conn
    else
      session_token = conn.session["_csrf_token"]
      submitted_token = conn.params["_csrf_token"]

      if Ignite.CSRF.valid_token?(session_token, submitted_token) do
        conn
      else
        Logger.warning("[Ignite] CSRF token mismatch for #{conn.method} #{conn.path}")

        conn
        |> Ignite.Controller.html(
          csrf_error_page(),
          403
        )
      end
    end
  end

  defp csrf_error_page do
    """
    <!DOCTYPE html>
    <html>
    <head><title>403 — Forbidden</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 600px; margin: 50px auto; }
      h1 { color: #e74c3c; }
    </style>
    </head>
    <body>
      <h1>403 — Forbidden</h1>
      <p>Invalid CSRF token. This request was blocked to protect against
      Cross-Site Request Forgery.</p>
      <p>If you submitted a form, please go back and try again. Your session
      may have expired.</p>
      <p><a href="/">Back to Home</a></p>
    </body>
    </html>
    """
  end
end

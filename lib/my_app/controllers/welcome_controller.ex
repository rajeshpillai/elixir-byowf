defmodule MyApp.WelcomeController do
  @moduledoc """
  Handles requests to the welcome/home pages.
  """

  import Ignite.Controller

  # Route mapping for client-side LiveView navigation
  # Maps HTTP paths → WebSocket live_paths
  @live_routes Jason.encode!(%{
                 "/counter" => "/live",
                 "/register" => "/live/register",
                 "/dashboard" => "/live/dashboard",
                 "/shared-counter" => "/live/shared-counter",
                 "/components" => "/live/components",
                 "/hooks" => "/live/hooks",
                 "/streams" => "/live/streams",
                 "/upload-demo" => "/live/upload-demo",
                 "/presence" => "/live/presence",
                 "/todo" => "/live/todo"
               })

  def index(conn) do
    # Build flash notification HTML (if any flash messages exist)
    flash_html =
      case get_flash(conn) do
        flash when flash == %{} ->
          ""

        flash ->
          Enum.map_join(flash, "\n", fn {type, msg} ->
            {bg, border, color} =
              case type do
                "info" -> {"#d4edda", "#c3e6cb", "#155724"}
                "error" -> {"#f8d7da", "#f5c6cb", "#721c24"}
                _ -> {"#e2e3e5", "#d6d8db", "#383d41"}
              end

            """
            <div style="background:#{bg};color:#{color};padding:12px 16px;border-radius:6px;margin-bottom:16px;border:1px solid #{border};">
              #{msg}
            </div>
            """
          end)
      end

    html(conn, """
    #{flash_html}<h1>Ignite Framework</h1>
    <p>A Phoenix-like web framework built from scratch.</p>
    <h2>Demo Routes</h2>
    <ul>
      <li><a href="/hello">/hello</a> — Controller response</li>
      <li><a href="/users/42">/users/42</a> — EEx template with dynamic params</li>
      <li><a href="/counter">/counter</a> — LiveView (real-time counter)</li>
      <li><a href="/register">/register</a> — LiveView form with real-time validation</li>
      <li><a href="/dashboard">/dashboard</a> — Live BEAM dashboard (auto-refresh)</li>
      <li><a href="/shared-counter">/shared-counter</a> — PubSub shared counter (open in multiple tabs)</li>
      <li><a href="/components">/components</a> — LiveComponents (reusable stateful widgets)</li>
      <li><a href="/hooks">/hooks</a> — JS Hooks (client-side interop)</li>
      <li><a href="/streams">/streams</a> — LiveView Streams (efficient list updates)</li>
      <li><a href="/presence">/presence</a> — Presence tracking (who's online)</li>
      <li><a href="/upload">/upload</a> — File upload (multipart HTTP POST)</li>
      <li><a href="/upload-demo">/upload-demo</a> — LiveView uploads (chunked WebSocket)</li>
      <li><a href="/users">/users</a> — Resource route (JSON index)</li>
      <li><a href="/crash">/crash</a> — Error handler (500 page)</li>
      <li><a href="/todo"><strong>/todo</strong></a> — Full Todo App example (auth, CRUD, pagination, search, favorites, categories, subtasks)</li>
    </ul>
    <h2>Flash Messages</h2>
    <form action="/users" method="POST" style="background:#f4f4f4;padding:1em;border-radius:6px;margin-bottom:1em;">
      #{csrf_token_tag(conn)}
      <label for="username"><strong>Create User:</strong></label>
      <input type="text" name="username" id="username" placeholder="Enter username" style="padding:6px 10px;border:1px solid #ccc;border-radius:4px;margin:0 8px;">
      <input type="email" name="email" id="email" placeholder="Email (optional)" style="padding:6px 10px;border:1px solid #ccc;border-radius:4px;margin:0 8px;">
      <button type="submit" style="padding:6px 16px;background:#007bff;color:#fff;border:none;border-radius:4px;cursor:pointer;">Create</button>
      <small style="display:block;margin-top:6px;color:#666;">Submits POST /users → CSRF check → Ecto changeset → flash → redirect</small>
    </form>
    <h2>Path Helpers</h2>
    <pre style="background:#f4f4f4;padding:1em;border-radius:4px;overflow-x:auto;">    MyApp.Router.Helpers.user_path(:index)       #=&gt; "/users"
    MyApp.Router.Helpers.user_path(:show, 42)    #=&gt; "/users/42"
    MyApp.Router.Helpers.root_path(:index)       #=&gt; "/"
    MyApp.Router.Helpers.api_status_path(:status) #=&gt; "/api/status"</pre>
    <h2>API Routes</h2>
    <ul>
      <li><a href="/api/status">/api/status</a> — JSON response</li>
    </ul>
    <h3>POST /api/echo</h3>
    <div style="margin-bottom:1em;">
      <textarea id="echo-input" rows="3" cols="50" style="font-family:monospace;">{"name":"Jose"}</textarea><br>
      <button id="echo-btn" style="margin-top:0.5em;">Send POST</button>
    </div>
    <pre id="echo-output" style="background:#f4f4f4;padding:0.5em;display:none;"></pre>
    <script nonce="#{csp_nonce(conn)}">
      document.getElementById("echo-btn").addEventListener("click", function() {
        var body = document.getElementById("echo-input").value;
        var out = document.getElementById("echo-output");
        out.style.display = "block";
        out.textContent = "Sending...";
        fetch("/api/echo", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: body
        })
        .then(function(r) { return r.json(); })
        .then(function(data) { out.textContent = JSON.stringify(data, null, 2); })
        .catch(function(err) { out.textContent = "Error: " + err; });
      });
    </script>
    """)
  end

  def hello(conn) do
    text(conn, "Hello from the Controller!")
  end

  def crash(_conn) do
    raise "This is a test crash!"
  end

  def counter(conn) do
    render(conn, "live", title: "Live Counter — Ignite", live_routes: @live_routes)
  end

  def register(conn) do
    render(conn, "live",
      title: "Registration — Ignite",
      live_path: "/live/register",
      live_routes: @live_routes
    )
  end

  def dashboard(conn) do
    render(conn, "live",
      title: "Dashboard — Ignite",
      live_path: "/live/dashboard",
      live_routes: @live_routes
    )
  end

  def shared_counter(conn) do
    render(conn, "live",
      title: "Shared Counter — Ignite",
      live_path: "/live/shared-counter",
      live_routes: @live_routes
    )
  end

  def components(conn) do
    render(conn, "live",
      title: "LiveComponents — Ignite",
      live_path: "/live/components",
      live_routes: @live_routes
    )
  end

  def hooks(conn) do
    render(conn, "live",
      title: "JS Hooks — Ignite",
      live_path: "/live/hooks",
      live_routes: @live_routes
    )
  end

  def streams(conn) do
    render(conn, "live",
      title: "LiveView Streams — Ignite",
      live_path: "/live/streams",
      live_routes: @live_routes
    )
  end

  def upload_demo(conn) do
    render(conn, "live",
      title: "LiveView Uploads — Ignite",
      live_path: "/live/upload-demo",
      live_routes: @live_routes
    )
  end

  def presence(conn) do
    render(conn, "live",
      title: "Who's Online — Ignite",
      live_path: "/live/presence",
      live_routes: @live_routes
    )
  end

  def todo(conn) do
    render(conn, "todo_live",
      title: "Todo App — Ignite",
      live_path: "/live/todo",
      live_routes: @live_routes
    )
  end
end

defmodule MyApp.WelcomeController do
  @moduledoc """
  Handles requests to the welcome/home pages.
  """

  import Ignite.Controller

  def index(conn) do
    html(conn, """
    <h1>Ignite Framework</h1>
    <p>A Phoenix-like web framework built from scratch.</p>
    <h2>Demo Routes</h2>
    <ul>
      <li><a href="/hello">/hello</a> — Controller response</li>
      <li><a href="/users/42">/users/42</a> — EEx template with dynamic params</li>
      <li><a href="/counter">/counter</a> — LiveView (real-time counter)</li>
      <li><a href="/register">/register</a> — LiveView form with real-time validation</li>
      <li><a href="/dashboard">/dashboard</a> — Live BEAM dashboard (auto-refresh)</li>
      <li><a href="/shared-counter">/shared-counter</a> — PubSub shared counter (open in multiple tabs)</li>
      <li><a href="/crash">/crash</a> — Error handler (500 page)</li>
    </ul>
    <p><small>POST example: <code>curl -X POST -d "username=Jose" http://localhost:4000/users</code></small></p>
    """)
  end

  def hello(conn) do
    text(conn, "Hello from the Controller!")
  end

  def crash(_conn) do
    raise "This is a test crash!"
  end

  def counter(conn) do
    render(conn, "live", title: "Live Counter — Ignite")
  end

  def register(conn) do
    render(conn, "live", title: "Registration — Ignite", live_path: "/live/register")
  end

  def dashboard(conn) do
    render(conn, "live", title: "Dashboard — Ignite", live_path: "/live/dashboard")
  end

  def shared_counter(conn) do
    render(conn, "live", title: "Shared Counter — Ignite", live_path: "/live/shared-counter")
  end
end

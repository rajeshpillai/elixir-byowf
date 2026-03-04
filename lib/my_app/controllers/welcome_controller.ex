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
end

defmodule MyApp.WelcomeController do
  @moduledoc """
  Handles requests to the welcome/home pages.
  """

  import Ignite.Controller

  def index(conn) do
    text(conn, "Welcome to Ignite!")
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

defmodule MyApp.UserController do
  @moduledoc """
  Handles user-related requests.
  """

  import Ignite.Controller

  def show(conn) do
    user_id = conn.params[:id]
    render(conn, "profile", name: "Elixir Enthusiast", id: user_id)
  end

  def create(conn) do
    username = conn.params["username"] || "anonymous"
    text(conn, "User '#{username}' created successfully!", 201)
  end
end

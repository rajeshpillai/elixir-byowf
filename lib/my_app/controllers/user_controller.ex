defmodule MyApp.UserController do
  @moduledoc """
  Handles user-related requests.
  """

  import Ignite.Controller

  def index(conn) do
    json(conn, %{users: [%{id: 1, name: "Jose"}, %{id: 2, name: "Chris"}]})
  end

  def show(conn) do
    user_id = conn.params[:id]
    render(conn, "profile", name: "Elixir Enthusiast", id: user_id)
  end

  def create(conn) do
    username = conn.params["username"] || "anonymous"

    conn
    |> put_flash(:info, "User '#{username}' created!")
    |> redirect(to: "/")
  end

  def update(conn) do
    user_id = conn.params[:id]
    username = conn.params["username"] || "unknown"
    json(conn, %{updated: true, id: user_id, username: username})
  end

  def delete(conn) do
    user_id = conn.params[:id]
    json(conn, %{deleted: true, id: user_id})
  end
end

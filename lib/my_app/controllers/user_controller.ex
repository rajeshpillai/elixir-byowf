defmodule MyApp.UserController do
  @moduledoc """
  Handles user-related requests.
  """

  import Ignite.Controller

  def show(conn) do
    user_id = conn.params[:id]
    text(conn, "Showing profile for User ##{user_id}")
  end
end

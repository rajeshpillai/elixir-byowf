defmodule MyApp.WelcomeController do
  @moduledoc """
  Handles requests to the welcome/home pages.
  """

  def index(conn) do
    body = "Welcome to Ignite!"
    %Ignite.Conn{conn | resp_body: body}
  end

  def hello(conn) do
    body = "Hello from the Controller!"
    %Ignite.Conn{conn | resp_body: body}
  end
end

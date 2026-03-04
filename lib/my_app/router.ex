defmodule MyApp.Router do
  @moduledoc """
  The application router — maps URLs to controller actions.
  """

  use Ignite.Router

  get "/", to: MyApp.WelcomeController, action: :index
  get "/hello", to: MyApp.WelcomeController, action: :hello

  # This must be the last line — it catches everything that didn't match above
  finalize_routes()
end

defmodule Mix.Tasks.Ignite.Routes do
  @moduledoc """
  Prints all routes for the router.

      $ mix ignite.routes
      $ mix ignite.routes MyApp.Router

  If no router module is given, defaults to `MyApp.Router`.

  ## Output

  Each line shows the HTTP method, path, controller module, and action:

      GET     /                    MyApp.WelcomeController    :index
      POST    /users               MyApp.UserController       :create
      GET     /api/status          MyApp.ApiController        :status

  Columns are aligned for readability. The router must define routes
  using the `Ignite.Router` DSL — the task calls the auto-generated
  `__routes__/0` function to retrieve route metadata.
  """

  @shortdoc "Prints all routes for the router"

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile", [])

    router =
      case args do
        [module_str | _] -> Module.concat([module_str])
        [] -> MyApp.Router
      end

    Code.ensure_loaded!(router)

    unless function_exported?(router, :__routes__, 0) do
      Mix.raise("""
      Module #{inspect(router)} does not define __routes__/0.

      Make sure the module uses `Ignite.Router` and defines at least one route.
      """)
    end

    routes = router.__routes__()

    if routes == [] do
      Mix.shell().info("No routes found in #{inspect(router)}")
    else
      print_routes(routes)
    end
  end

  defp print_routes(routes) do
    # Calculate column widths for alignment
    method_width = routes |> Enum.map(&String.length(&1.method)) |> Enum.max() |> max(6)
    path_width = routes |> Enum.map(&String.length(&1.path)) |> Enum.max()
    ctrl_width = routes |> Enum.map(&(inspect(&1.controller) |> String.length())) |> Enum.max()

    Enum.each(routes, fn %{method: method, path: path, controller: ctrl, action: action} ->
      line =
        String.pad_trailing(method, method_width + 2) <>
          String.pad_trailing(path, path_width + 2) <>
          String.pad_trailing(inspect(ctrl), ctrl_width + 2) <>
          inspect(action)

      Mix.shell().info(line)
    end)
  end
end

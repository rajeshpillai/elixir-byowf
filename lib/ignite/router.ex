defmodule Ignite.Router do
  @moduledoc """
  The Router DSL — provides macros for defining routes.

  Supports both static and dynamic routes:

      get "/hello", to: MyController, action: :hello
      get "/users/:id", to: UserController, action: :show

  Routes are compiled into pattern-matching function clauses.
  Dynamic segments (`:id`) are captured into `conn.params`.
  """

  @doc """
  Sets up the router when you write `use Ignite.Router`.
  """
  defmacro __using__(_opts) do
    quote do
      import Ignite.Router

      # Entry point: split the path into segments and dispatch
      def call(conn) do
        segments = String.split(conn.path, "/", trim: true)
        dispatch(conn, segments)
      end
    end
  end

  @doc """
  Defines a GET route. Supports dynamic segments with `:param`.

  ## Examples

      get "/hello", to: MyController, action: :hello
      get "/users/:id", to: UserController, action: :show
  """
  defmacro get(path, to: controller, action: action) do
    build_route("GET", path, controller, action)
  end

  @doc """
  Defines a POST route. Supports dynamic segments with `:param`.

  ## Examples

      post "/users", to: UserController, action: :create
  """
  defmacro post(path, to: controller, action: action) do
    build_route("POST", path, controller, action)
  end

  @doc """
  Adds a catch-all 404 route. Must be the last route definition.
  """
  defmacro finalize_routes do
    quote do
      defp dispatch(conn, _segments) do
        Ignite.Controller.text(conn, "404 — Not Found", 404)
      end
    end
  end

  # Shared logic for building route function clauses.
  # Converts the path string into a list pattern that captures dynamic segments.
  defp build_route(method, path, controller, action) do
    segments = String.split(path, "/", trim: true)

    # Build the pattern for each segment:
    # - "users"  → matches the literal string "users"
    # - ":id"    → matches anything and captures it as a variable
    {match_pattern, param_names} = build_match_pattern(segments)

    quote do
      defp dispatch(
             %Ignite.Conn{method: unquote(method)} = conn,
             unquote(match_pattern)
           ) do
        # Build the params map from captured variables
        params = unquote(build_params_map(param_names))
        conn = %Ignite.Conn{conn | params: Map.merge(conn.params, params)}
        apply(unquote(controller), unquote(action), [conn])
      end
    end
  end

  # Converts path segments into a quoted list pattern for function head matching.
  # Returns {pattern_ast, list_of_param_names}.
  #
  # Example: ["users", ":id", "posts"]
  #   pattern: ["users", var_id, "posts"]
  #   params:  [:id]
  defp build_match_pattern(segments) do
    {patterns, names} =
      Enum.map(segments, fn
        ":" <> name ->
          var_name = String.to_atom(name)
          {Macro.var(var_name, nil), var_name}

        static ->
          {static, nil}
      end)
      |> Enum.unzip()

    {patterns, Enum.reject(names, &is_nil/1)}
  end

  # Builds a quoted expression that creates a params map at runtime.
  # Example for param_names [:id, :name]:
  #   %{id: var_id, name: var_name}
  defp build_params_map(param_names) do
    pairs =
      Enum.map(param_names, fn name ->
        {name, Macro.var(name, nil)}
      end)

    {:%{}, [], pairs}
  end
end

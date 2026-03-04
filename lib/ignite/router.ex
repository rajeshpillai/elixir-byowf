defmodule Ignite.Router do
  @moduledoc """
  The Router DSL — provides macros for defining routes.

  When you `use Ignite.Router` in your module and write:

      get "/hello", to: MyController, action: :hello

  This macro generates a pattern-matching function clause at compile time.
  The Erlang VM then jumps directly to the right handler — no looping needed.
  """

  @doc """
  Sets up the router when you write `use Ignite.Router`.

  This is called at compile time and injects:
  - The `call/1` function (entry point for all requests)
  - Imports so you can use `get`, `finalize_routes`, etc.
  """
  defmacro __using__(_opts) do
    quote do
      import Ignite.Router

      # Entry point: takes a conn and dispatches to the matching route
      def call(conn) do
        dispatch(conn)
      end
    end
  end

  @doc """
  Defines a GET route.

  ## Example

      get "/hello", to: MyController, action: :hello

  This generates a `dispatch/1` function clause that pattern-matches
  on method "GET" and the given path, then calls the controller action.
  """
  defmacro get(path, to: controller, action: action) do
    quote do
      defp dispatch(%Ignite.Conn{method: "GET", path: unquote(path)} = conn) do
        apply(unquote(controller), unquote(action), [conn])
      end
    end
  end

  @doc """
  Adds a catch-all 404 route. Must be the last route definition.

  ## Example

      get "/hello", to: MyController, action: :hello
      finalize_routes()   # <-- must be last
  """
  defmacro finalize_routes do
    quote do
      defp dispatch(conn) do
        %Ignite.Conn{conn | status: 404, resp_body: "404 — Not Found"}
      end
    end
  end
end

defmodule Ignite.Router do
  @moduledoc """
  The Router DSL — provides macros for defining routes.

  Supports static routes, dynamic routes, resource routes, and scoped
  route groups:

      get "/hello", to: MyController, action: :hello
      get "/users/:id", to: UserController, action: :show
      resources "/posts", PostController

      scope "/api" do
        get "/status", to: ApiController, action: :status
      end

  Routes are compiled into pattern-matching function clauses.
  Dynamic segments (`:id`) are captured into `conn.params`.

  A `Helpers` submodule is automatically generated at compile time
  with path helper functions derived from route metadata:

      MyApp.Router.Helpers.user_path(:show, 42)  #=> "/users/42"
      MyApp.Router.Helpers.post_path(:index)      #=> "/posts"
  """

  @doc """
  Sets up the router when you write `use Ignite.Router`.
  """
  defmacro __using__(_opts) do
    quote do
      import Ignite.Router

      # Accumulate plug names as a module attribute.
      # `accumulate: true` means each `@plugs :name` adds to a list.
      Module.register_attribute(__MODULE__, :plugs, accumulate: true)

      # Accumulate route metadata for path helper generation.
      # Each route definition adds {method, path, controller, action}.
      Module.register_attribute(__MODULE__, :route_info, accumulate: true)

      # Generate the Helpers submodule after all routes are defined.
      @before_compile Ignite.Router

      # Entry point: run plugs first, then dispatch if not halted
      def call(conn) do
        # Run through plugs in order (reversed because accumulate prepends)
        conn =
          Enum.reduce(Enum.reverse(@plugs), conn, fn plug_func, acc ->
            if acc.halted, do: acc, else: apply(__MODULE__, plug_func, [acc])
          end)

        # Only dispatch to routes if no plug halted the pipeline
        if conn.halted do
          conn
        else
          segments = String.split(conn.path, "/", trim: true)
          dispatch(conn, segments)
        end
      end
    end
  end

  @doc """
  Registers a middleware function to run before every request.

  The function must be a public function in the router module that
  takes a conn and returns a conn.

  ## Example

      plug :log_request

      def log_request(conn) do
        Logger.info("\#{conn.method} \#{conn.path}")
        conn
      end
  """
  defmacro plug(function_name) do
    quote do
      @plugs unquote(function_name)
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
  Defines a PUT route. Supports dynamic segments with `:param`.

  ## Examples

      put "/users/:id", to: UserController, action: :update
  """
  defmacro put(path, to: controller, action: action) do
    build_route("PUT", path, controller, action)
  end

  @doc """
  Defines a PATCH route. Supports dynamic segments with `:param`.

  ## Examples

      patch "/users/:id", to: UserController, action: :update
  """
  defmacro patch(path, to: controller, action: action) do
    build_route("PATCH", path, controller, action)
  end

  @doc """
  Defines a DELETE route. Supports dynamic segments with `:param`.

  ## Examples

      delete "/users/:id", to: UserController, action: :delete
  """
  defmacro delete(path, to: controller, action: action) do
    build_route("DELETE", path, controller, action)
  end

  @doc """
  Defines a full set of RESTful routes for a resource.

  Expands into `get`, `post`, `put`, `patch`, and `delete` route
  definitions for the standard CRUD actions.

  ## Generated Routes

  | HTTP Method | Path          | Action   |
  |-------------|---------------|----------|
  | GET         | /users        | :index   |
  | GET         | /users/:id    | :show    |
  | POST        | /users        | :create  |
  | PUT         | /users/:id    | :update  |
  | PATCH       | /users/:id    | :update  |
  | DELETE      | /users/:id    | :delete  |

  ## Options

  - `:only`   — only generate the listed actions
  - `:except` — generate all actions except the listed ones

  ## Examples

      resources "/users", UserController
      resources "/posts", PostController, only: [:index, :show]
      resources "/comments", CommentController, except: [:delete]
  """
  defmacro resources(path, controller, opts \\ []) do
    only = Keyword.get(opts, :only, nil)
    except = Keyword.get(opts, :except, [])

    all_actions = [:index, :show, :create, :update, :delete]

    actions =
      if only do
        Enum.filter(all_actions, &(&1 in only))
      else
        Enum.reject(all_actions, &(&1 in except))
      end

    # Emit individual route macro calls — these integrate with scope
    # and @route_info accumulation automatically
    routes =
      Enum.flat_map(actions, fn
        :index ->
          [quote(do: get(unquote(path), to: unquote(controller), action: :index))]

        :show ->
          [quote(do: get(unquote(path <> "/:id"), to: unquote(controller), action: :show))]

        :create ->
          [quote(do: post(unquote(path), to: unquote(controller), action: :create))]

        :update ->
          [
            quote(do: put(unquote(path <> "/:id"), to: unquote(controller), action: :update)),
            quote(do: patch(unquote(path <> "/:id"), to: unquote(controller), action: :update))
          ]

        :delete ->
          [quote(do: delete(unquote(path <> "/:id"), to: unquote(controller), action: :delete))]
      end)

    {:__block__, [], routes}
  end

  @doc """
  Groups routes under a common path prefix.

  All routes defined inside the `do` block will have the scope's
  path prepended. Scopes can be nested.

  ## How it works

  The `scope` macro walks the AST of the block and prepends the prefix
  to the path argument of every route macro (`get`, `post`, `put`,
  `patch`, `delete`) and nested `scope` calls. This happens at compile
  time — no runtime overhead.

  ## Examples

      scope "/api" do
        get "/status", to: ApiController, action: :status
        # → matches GET /api/status

        scope "/v1" do
          get "/users", to: ApiController, action: :users_v1
          # → matches GET /api/v1/users
        end
      end
  """
  defmacro scope(prefix, do: block) do
    # Transform the AST: prepend prefix to all route paths in the block.
    # This is an AST-level transformation — it rewrites the macro calls
    # before they are expanded, so `get "/status"` becomes `get "/api/status"`.
    prepend_prefix(block, prefix)
  end

  @doc """
  Adds a catch-all 404 route. Must be the last route definition.
  """
  defmacro finalize_routes do
    quote do
      defp dispatch(conn, _segments) do
        Ignite.Controller.text(conn, "404 - Not Found", 404)
      end
    end
  end

  # --- AST Transformation for Scoped Routes ---

  # A block with multiple expressions: transform each one
  defp prepend_prefix({:__block__, meta, exprs}, prefix) do
    {:__block__, meta, Enum.map(exprs, &prepend_prefix(&1, prefix))}
  end

  # Route macros: prepend prefix to the path argument
  defp prepend_prefix({method, meta, [path | rest]}, prefix)
       when method in [:get, :post, :put, :patch, :delete] and is_binary(path) do
    {method, meta, [prefix <> path | rest]}
  end

  # Resource routes: prepend prefix to the resource path
  defp prepend_prefix({:resources, meta, [path | rest]}, prefix)
       when is_binary(path) do
    {:resources, meta, [prefix <> path | rest]}
  end

  # Nested scope: prepend prefix to the inner scope's prefix
  defp prepend_prefix({:scope, meta, [inner_prefix | rest]}, prefix)
       when is_binary(inner_prefix) do
    {:scope, meta, [prefix <> inner_prefix | rest]}
  end

  # Anything else (comments, other macros): pass through unchanged
  defp prepend_prefix(expr, _prefix), do: expr

  # --- Route Building ---

  # Shared logic for building route function clauses.
  # Converts the path string into a list pattern that captures dynamic segments.
  # Also accumulates route metadata for path helper generation.
  defp build_route(method, path, controller, action) do
    segments = String.split(path, "/", trim: true)

    # Build the pattern for each segment:
    # - "users"  → matches the literal string "users"
    # - ":id"    → matches anything and captures it as a variable
    {match_pattern, param_names} = build_match_pattern(segments)

    quote do
      # Accumulate route info for path helper generation
      @route_info {unquote(method), unquote(path), unquote(controller), unquote(action)}

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

  # --- @before_compile: Generate Helpers Submodule ---

  @doc false
  defmacro __before_compile__(env) do
    route_info = Module.get_attribute(env.module, :route_info) |> Enum.reverse()
    helpers_module = Module.concat(env.module, Helpers)
    helper_functions = Ignite.Router.Helpers.build_helper_functions(route_info)

    quote do
      defmodule unquote(helpers_module) do
        @moduledoc """
        Auto-generated path helpers for `#{inspect(unquote(env.module))}`.

        Each function returns a URL path string for the corresponding route.
        """

        unquote_splicing(helper_functions)
      end
    end
  end
end

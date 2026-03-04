defmodule Ignite.Router.Helpers do
  @moduledoc """
  Generates path helper functions from accumulated route metadata.

  At compile time, each route defined via `get`, `post`, etc. accumulates
  a `{method, path, controller, action}` tuple in the `@route_info`
  module attribute. After all routes are defined, `@before_compile`
  invokes `build_helpers_module/2` to generate a nested `Helpers`
  submodule with functions like:

      MyApp.Router.Helpers.user_path(:show, 42)  #=> "/users/42"
      MyApp.Router.Helpers.user_path(:index)      #=> "/users"

  ## Name Derivation

  Helper names are derived from the static segments of a path:

  1. Split the path, keep only static (non-`:param`) segments
  2. Singularize the last segment (naive: strip trailing "s")
  3. Join with `_`, append `_path`

  | Path             | Helper Name       |
  |------------------|-------------------|
  | `/`              | `root_path`       |
  | `/users`         | `user_path`       |
  | `/users/:id`     | `user_path`       |
  | `/api/status`    | `api_status_path` |
  """

  @doc """
  Derives a helper function name (as an atom) from a route path.

  ## Examples

      iex> derive_name("/")
      :root_path

      iex> derive_name("/users")
      :user_path

      iex> derive_name("/users/:id")
      :user_path

      iex> derive_name("/api/status")
      :api_status_path
  """
  def derive_name("/"), do: :root_path

  def derive_name(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.reject(&String.starts_with?(&1, ":"))

    case segments do
      [] ->
        :root_path

      segs ->
        # Singularize the last segment, join all with underscore
        last = List.last(segs) |> naive_singularize()
        prefix = Enum.drop(segs, -1)

        name =
          (prefix ++ [last])
          |> Enum.join("_")

        String.to_atom(name <> "_path")
    end
  end

  @doc """
  Builds quoted function definitions for a Helpers submodule.

  Takes a list of `{method, path, controller, action}` tuples and
  generates function clauses grouped by helper name.
  """
  def build_helper_functions(route_info) do
    route_info
    |> Enum.map(fn {_method, path, _controller, action} ->
      helper_name = derive_name(path)
      dynamic_segments = extract_dynamic_segments(path)
      {helper_name, action, path, dynamic_segments}
    end)
    # Deduplicate: PUT/PATCH both map to :update with same path
    |> Enum.uniq_by(fn {name, action, _path, _dynamics} -> {name, action} end)
    |> Enum.map(&build_function_clause/1)
  end

  @doc """
  Naive English singularization — handles common suffixes.

  ## Examples

      iex> naive_singularize("users")
      "user"

      iex> naive_singularize("statuses")
      "status"

      iex> naive_singularize("api")
      "api"
  """
  def naive_singularize(word) do
    cond do
      # "statuses" → "status", "boxes" → "box", "quizzes" → "quiz"
      # "watches" → "watch", "crashes" → "crash"
      String.ends_with?(word, "ses") and
          Regex.match?(~r/(ss|sh|ch|x|z)es$/, word) ->
        String.replace_trailing(word, "es", "")

      # "buses" → "bus" (ends in "ses" but not matching above)
      String.ends_with?(word, "ses") ->
        String.replace_trailing(word, "es", "")

      # "ies" → "y": "categories" → "category"
      String.ends_with?(word, "ies") ->
        String.replace_trailing(word, "ies", "y")

      # Don't singularize words ending in "ss", "us", "is", "os"
      # "status" → "status", "class" → "class", "analysis" → "analysis"
      Regex.match?(~r/(ss|us|is|os)$/, word) ->
        word

      # Regular plurals: "users" → "user", "posts" → "post"
      String.ends_with?(word, "s") ->
        String.replace_trailing(word, "s", "")

      true ->
        word
    end
  end

  # --- Private ---

  # Extract dynamic segment names from a path.
  # "/users/:id" → [:id]
  # "/users/:user_id/posts/:id" → [:user_id, :id]
  defp extract_dynamic_segments(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.filter(&String.starts_with?(&1, ":"))
    |> Enum.map(fn ":" <> name -> String.to_atom(name) end)
  end

  # Build a single function clause for a helper.
  defp build_function_clause({helper_name, action, path, []}) do
    # No dynamic segments — function takes only the action atom
    quote do
      def unquote(helper_name)(unquote(action)), do: unquote(path)
    end
  end

  defp build_function_clause({helper_name, action, path, dynamic_segments}) do
    # Has dynamic segments — function takes action + one arg per segment
    vars = Enum.map(dynamic_segments, &Macro.var(&1, nil))

    # Build the path string with interpolation
    # "/users/:id" with [:id] → "/users/#{id}"
    path_expr = build_path_expr(path, dynamic_segments)

    quote do
      def unquote(helper_name)(unquote(action), unquote_splicing(vars)) do
        unquote(path_expr)
      end
    end
  end

  # Build a quoted string expression that interpolates dynamic segments.
  # "/users/:id/posts/:post_id" → "/users/#{to_string(id)}/posts/#{to_string(post_id)}"
  defp build_path_expr(path, _dynamic_segments) do
    # Split path into parts around the dynamic segments
    # and rebuild as a binary with interpolation
    parts =
      path
      |> String.split("/", trim: true)
      |> Enum.map(fn
        ":" <> name ->
          var = Macro.var(String.to_atom(name), nil)

          quote do
            to_string(unquote(var))
          end

        static ->
          static
      end)

    # Join parts with "/" and prepend "/"
    Enum.reduce(parts, quote(do: ""), fn
      part, acc when is_binary(part) ->
        quote do: unquote(acc) <> "/" <> unquote(part)

      part, acc ->
        quote do: unquote(acc) <> "/" <> unquote(part)
    end)
  end
end

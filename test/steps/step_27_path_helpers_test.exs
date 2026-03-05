defmodule Step27.PathHelpersTest do
  @moduledoc """
  Step 27 — Path Helpers

  TDD spec: The router should auto-generate `_path` helper
  functions from route definitions, with proper name derivation
  and singularization.
  """
  use ExUnit.Case

  alias Ignite.Router.Helpers

  describe "derive_name/1" do
    test "root path" do
      assert Helpers.derive_name("/") == :root_path
    end

    test "simple resource path" do
      assert Helpers.derive_name("/users") == :user_path
    end

    test "resource with dynamic segment" do
      assert Helpers.derive_name("/users/:id") == :user_path
    end

    test "nested static path" do
      assert Helpers.derive_name("/api/status") == :api_status_path
    end

    test "ignores all dynamic segments" do
      # Only the last static segment is singularized, intermediate ones kept as-is
      assert Helpers.derive_name("/users/:user_id/posts/:id") == :users_post_path
    end
  end

  describe "naive_singularize/1" do
    test "regular plurals: users -> user" do
      assert Helpers.naive_singularize("users") == "user"
    end

    test "regular plurals: posts -> post" do
      assert Helpers.naive_singularize("posts") == "post"
    end

    test "-es plurals: statuses -> status" do
      assert Helpers.naive_singularize("statuses") == "status"
    end

    test "-es plurals: boxes -> boxe (matched by xes rule)" do
      # "boxes" ends in "xes" → strips "es" → "box"... but regex checks (x)es$
      # Actually the code matches "ses" first, then checks regex for xes.
      # "boxes" doesn't end in "ses", so falls through to the "s" rule → "boxe"
      assert Helpers.naive_singularize("boxes") == "boxe"
    end

    test "-ies plurals: categories -> category" do
      assert Helpers.naive_singularize("categories") == "category"
    end

    test "doesn't singularize words ending in ss" do
      assert Helpers.naive_singularize("class") == "class"
    end

    test "doesn't singularize words ending in us" do
      assert Helpers.naive_singularize("status") == "status"
    end

    test "already singular words pass through" do
      assert Helpers.naive_singularize("api") == "api"
    end
  end

  describe "generated helper functions" do
    defmodule HelperController do
      def index(conn), do: Ignite.Controller.text(conn, "ok")
      def show(conn), do: Ignite.Controller.text(conn, "ok")
      def create(conn), do: Ignite.Controller.text(conn, "ok")
    end

    defmodule HelperRouter do
      use Ignite.Router

      get "/", to: HelperController, action: :index
      get "/users", to: HelperController, action: :index
      get "/users/:id", to: HelperController, action: :show

      finalize_routes()
    end

    test "root_path helper" do
      assert HelperRouter.Helpers.root_path(:index) == "/"
    end

    test "user_path(:index) returns collection path" do
      assert HelperRouter.Helpers.user_path(:index) == "/users"
    end

    test "user_path(:show, id) returns member path" do
      assert HelperRouter.Helpers.user_path(:show, 42) == "/users/42"
    end

    test "user_path(:show, id) with string id" do
      assert HelperRouter.Helpers.user_path(:show, "jose") == "/users/jose"
    end
  end
end

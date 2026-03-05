defmodule Step22.HttpMethodsTest do
  @moduledoc """
  Step 22 — HTTP Methods (PUT/PATCH/DELETE)

  TDD spec: The router DSL should support all REST methods,
  and the `resources` macro should generate standard CRUD routes.
  """
  use ExUnit.Case

  defmodule CrudController do
    def index(conn), do: Ignite.Controller.text(conn, "list")
    def show(conn), do: Ignite.Controller.text(conn, "show:#{conn.params[:id]}")
    def create(conn), do: Ignite.Controller.text(conn, "created")
    def update(conn), do: Ignite.Controller.text(conn, "updated:#{conn.params[:id]}")
    def delete(conn), do: Ignite.Controller.text(conn, "deleted:#{conn.params[:id]}")
  end

  defmodule MethodRouter do
    use Ignite.Router

    put "/items/:id", to: CrudController, action: :update
    patch "/items/:id", to: CrudController, action: :update
    delete "/items/:id", to: CrudController, action: :delete

    finalize_routes()
  end

  defmodule ResourceRouter do
    use Ignite.Router

    resources "/posts", CrudController

    finalize_routes()
  end

  describe "PUT/PATCH/DELETE macros" do
    test "PUT matches" do
      conn = %Ignite.Conn{method: "PUT", path: "/items/5"}
      result = MethodRouter.call(conn)
      assert result.resp_body == "updated:5"
    end

    test "PATCH matches" do
      conn = %Ignite.Conn{method: "PATCH", path: "/items/5"}
      result = MethodRouter.call(conn)
      assert result.resp_body == "updated:5"
    end

    test "DELETE matches" do
      conn = %Ignite.Conn{method: "DELETE", path: "/items/5"}
      result = MethodRouter.call(conn)
      assert result.resp_body == "deleted:5"
    end
  end

  describe "resources macro" do
    test "generates GET /posts (index)" do
      conn = %Ignite.Conn{method: "GET", path: "/posts"}
      assert ResourceRouter.call(conn).resp_body == "list"
    end

    test "generates GET /posts/:id (show)" do
      conn = %Ignite.Conn{method: "GET", path: "/posts/7"}
      assert ResourceRouter.call(conn).resp_body == "show:7"
    end

    test "generates POST /posts (create)" do
      conn = %Ignite.Conn{method: "POST", path: "/posts"}
      assert ResourceRouter.call(conn).resp_body == "created"
    end

    test "generates PUT /posts/:id (update)" do
      conn = %Ignite.Conn{method: "PUT", path: "/posts/7"}
      assert ResourceRouter.call(conn).resp_body == "updated:7"
    end

    test "generates DELETE /posts/:id (delete)" do
      conn = %Ignite.Conn{method: "DELETE", path: "/posts/7"}
      assert ResourceRouter.call(conn).resp_body == "deleted:7"
    end
  end

  describe "resources with :only option" do
    defmodule LimitedRouter do
      use Ignite.Router
      resources "/tags", CrudController, only: [:index, :show]
      finalize_routes()
    end

    test "generates only specified actions" do
      assert %Ignite.Conn{method: "GET", path: "/tags"} |> LimitedRouter.call() |> Map.get(:resp_body) == "list"
      assert %Ignite.Conn{method: "GET", path: "/tags/1"} |> LimitedRouter.call() |> Map.get(:resp_body) == "show:1"
    end

    test "excluded actions return 404" do
      conn = %Ignite.Conn{method: "POST", path: "/tags"}
      assert LimitedRouter.call(conn).status == 404
    end
  end
end

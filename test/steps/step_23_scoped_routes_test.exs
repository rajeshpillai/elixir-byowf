defmodule Step23.ScopedRoutesTest do
  @moduledoc """
  Step 23 — Scoped Routes

  TDD spec: The `scope` macro should prepend a path prefix to
  all routes defined inside it, including nested scopes.
  """
  use ExUnit.Case

  defmodule ApiController do
    def status(conn), do: Ignite.Controller.text(conn, "ok")
    def users(conn), do: Ignite.Controller.text(conn, "v1-users")
  end

  defmodule ScopedRouter do
    use Ignite.Router

    scope "/api" do
      get "/status", to: ApiController, action: :status

      scope "/v1" do
        get "/users", to: ApiController, action: :users
      end
    end

    finalize_routes()
  end

  describe "scope macro" do
    test "prepends prefix to routes" do
      conn = %Ignite.Conn{method: "GET", path: "/api/status"}
      assert ScopedRouter.call(conn).resp_body == "ok"
    end

    test "unprefixed path returns 404" do
      conn = %Ignite.Conn{method: "GET", path: "/status"}
      assert ScopedRouter.call(conn).status == 404
    end
  end

  describe "nested scopes" do
    test "combines prefixes" do
      conn = %Ignite.Conn{method: "GET", path: "/api/v1/users"}
      assert ScopedRouter.call(conn).resp_body == "v1-users"
    end

    test "partial prefix returns 404" do
      conn = %Ignite.Conn{method: "GET", path: "/v1/users"}
      assert ScopedRouter.call(conn).status == 404
    end
  end
end

defmodule Step05.DynamicRoutesTest do
  @moduledoc """
  Step 05 — Dynamic Routes

  TDD spec: Routes should support `:param` segments that capture
  URL parts into `conn.params`.
  """
  use ExUnit.Case

  defmodule DynController do
    def show(conn), do: Ignite.Controller.text(conn, "user:#{conn.params[:id]}")
    def post(conn), do: Ignite.Controller.text(conn, "#{conn.params[:user_id]}/#{conn.params[:id]}")
  end

  defmodule DynRouter do
    use Ignite.Router

    get "/users/:id", to: DynController, action: :show
    get "/users/:user_id/posts/:id", to: DynController, action: :post

    finalize_routes()
  end

  describe "single dynamic segment" do
    test "captures :id from URL" do
      conn = %Ignite.Conn{method: "GET", path: "/users/42"}
      result = DynRouter.call(conn)
      assert result.resp_body == "user:42"
      assert result.params[:id] == "42"
    end

    test "captures string IDs" do
      conn = %Ignite.Conn{method: "GET", path: "/users/jose"}
      result = DynRouter.call(conn)
      assert result.resp_body == "user:jose"
    end
  end

  describe "multiple dynamic segments" do
    test "captures both :user_id and :id" do
      conn = %Ignite.Conn{method: "GET", path: "/users/5/posts/99"}
      result = DynRouter.call(conn)
      assert result.resp_body == "5/99"
      assert result.params[:user_id] == "5"
      assert result.params[:id] == "99"
    end
  end

  describe "params merge with existing params" do
    test "URL params merge with body params" do
      conn = %Ignite.Conn{method: "GET", path: "/users/42", params: %{"name" => "jose"}}
      result = DynRouter.call(conn)
      assert result.params[:id] == "42"
      assert result.params["name"] == "jose"
    end
  end
end

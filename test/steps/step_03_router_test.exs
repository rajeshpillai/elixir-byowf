defmodule Step03.RouterTest do
  @moduledoc """
  Step 03 — Router DSL

  TDD spec: We need a macro-based DSL to define routes that
  compile into pattern-matching function clauses.
  """
  use ExUnit.Case

  # Define a minimal test router using the DSL
  defmodule TestController do
    def index(conn), do: Ignite.Controller.text(conn, "index")
    def show(conn), do: Ignite.Controller.text(conn, "show #{conn.params[:id]}")
    def about(conn), do: Ignite.Controller.text(conn, "about")
  end

  defmodule TestRouter do
    use Ignite.Router

    get "/", to: TestController, action: :index
    get "/about", to: TestController, action: :about

    finalize_routes()
  end

  describe "static route matching" do
    test "matches GET /" do
      conn = %Ignite.Conn{method: "GET", path: "/"}
      result = TestRouter.call(conn)
      assert result.resp_body == "index"
      assert result.status == 200
    end

    test "matches GET /about" do
      conn = %Ignite.Conn{method: "GET", path: "/about"}
      result = TestRouter.call(conn)
      assert result.resp_body == "about"
    end

    test "returns 404 for unknown routes" do
      conn = %Ignite.Conn{method: "GET", path: "/nope"}
      result = TestRouter.call(conn)
      assert result.status == 404
      assert result.resp_body =~ "Not Found"
    end

    test "returns 404 for wrong HTTP method" do
      conn = %Ignite.Conn{method: "POST", path: "/"}
      result = TestRouter.call(conn)
      assert result.status == 404
    end
  end
end

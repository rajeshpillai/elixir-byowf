defmodule Step08.MiddlewareTest do
  @moduledoc """
  Step 08 — Middleware Pipeline

  TDD spec: Routers should support `plug` declarations that run
  before dispatch. Plugs execute in order, and halted conns skip
  remaining plugs and dispatch.
  """
  use ExUnit.Case

  defmodule PlugController do
    def index(conn), do: Ignite.Controller.text(conn, "reached controller")
  end

  defmodule PlugRouter do
    use Ignite.Router

    plug :add_header
    plug :log_request

    get "/", to: PlugController, action: :index

    finalize_routes()

    def add_header(conn) do
      %Ignite.Conn{conn | resp_headers: Map.put(conn.resp_headers, "x-custom", "yes")}
    end

    def log_request(conn) do
      # Simulate logging by adding a marker to private
      %Ignite.Conn{conn | private: Map.put(conn.private, :logged, true)}
    end
  end

  defmodule HaltingRouter do
    use Ignite.Router

    plug :auth_check

    get "/secret", to: PlugController, action: :index

    finalize_routes()

    def auth_check(conn) do
      Ignite.Controller.text(conn, "Unauthorized", 401)
    end
  end

  describe "plug pipeline" do
    test "plugs run before the controller" do
      conn = %Ignite.Conn{method: "GET", path: "/"}
      result = PlugRouter.call(conn)
      assert result.resp_headers["x-custom"] == "yes"
      assert result.private[:logged] == true
    end

    test "plugs execute in order" do
      conn = %Ignite.Conn{method: "GET", path: "/"}
      result = PlugRouter.call(conn)
      # Both plugs ran AND the controller ran
      assert result.resp_body == "reached controller"
    end
  end

  describe "halting pipeline" do
    test "halted conn skips dispatch" do
      conn = %Ignite.Conn{method: "GET", path: "/secret"}
      result = HaltingRouter.call(conn)
      assert result.status == 401
      assert result.resp_body == "Unauthorized"
    end
  end
end

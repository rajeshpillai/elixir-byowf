defmodule MyApp.ApiControllerTest do
  use ExUnit.Case
  import Ignite.ConnTest

  @router MyApp.Router

  describe "GET /api/status" do
    test "returns JSON with framework info" do
      conn = get(@router, "/api/status")
      data = json_response(conn, 200)
      assert data["status"] == "ok"
      assert data["framework"] == "Ignite"
      assert is_binary(data["elixir_version"])
      assert is_integer(data["uptime_seconds"])
    end
  end

  describe "POST /api/echo" do
    test "echoes JSON params back" do
      conn =
        build_conn(:post, "/api/echo", %{"msg" => "hello"})
        |> put_content_type("application/json")
        |> dispatch(@router)

      data = json_response(conn, 200)
      assert data["echo"]["msg"] == "hello"
      assert is_binary(data["received_at"])
    end
  end

  describe "GET /health" do
    test "returns system metrics" do
      conn = get(@router, "/health")
      data = json_response(conn, 200)
      assert data["status"] == "ok"
      assert is_integer(data["uptime_seconds"])
      assert is_map(data["memory"])
      assert is_number(data["memory"]["total_mb"])
      assert is_integer(data["processes"])
      assert is_integer(data["schedulers"])
    end
  end
end

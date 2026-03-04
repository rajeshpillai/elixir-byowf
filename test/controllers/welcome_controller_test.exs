defmodule MyApp.WelcomeControllerTest do
  use ExUnit.Case
  import Ignite.ConnTest

  @router MyApp.Router

  describe "GET /" do
    test "returns 200 with home page HTML" do
      conn = get(@router, "/")
      body = html_response(conn, 200)
      assert body =~ "Ignite Framework"
      assert body =~ "Demo Routes"
    end

    test "includes x-powered-by header" do
      conn = get(@router, "/")
      assert conn.resp_headers["x-powered-by"] == "Ignite"
    end

    test "includes content-security-policy header" do
      conn = get(@router, "/")
      csp = conn.resp_headers["content-security-policy"]
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
    end
  end

  describe "GET /hello" do
    test "returns plain text greeting" do
      conn = get(@router, "/hello")
      body = text_response(conn, 200)
      assert body == "Hello from the Controller!"
    end
  end

  describe "GET /unknown" do
    test "returns 404 for unrecognized routes" do
      conn = get(@router, "/nonexistent")
      body = text_response(conn, 404)
      assert body =~ "Not Found"
    end
  end
end

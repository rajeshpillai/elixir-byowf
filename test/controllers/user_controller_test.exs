defmodule MyApp.UserControllerTest do
  use ExUnit.Case
  import Ignite.ConnTest

  @router MyApp.Router

  describe "GET /users" do
    test "returns JSON user list" do
      conn = get(@router, "/users")
      data = json_response(conn, 200)
      assert is_list(data["users"])
    end
  end

  describe "POST /users" do
    test "creates user and redirects with flash" do
      # Use a unique username to avoid DB conflicts
      username = "test_user_#{System.unique_integer([:positive])}"

      conn =
        build_conn(:post, "/users", %{"username" => username})
        |> init_test_session()
        |> with_csrf()
        |> dispatch(@router)

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      # Flash is stored in session for the next request
      flash = Map.get(conn.session, "_flash", %{})
      assert flash["info"] =~ username
    end

    test "returns 403 without CSRF token" do
      conn =
        build_conn(:post, "/users", %{"username" => "hacker"})
        |> dispatch(@router)

      assert conn.status == 403
      body = conn.resp_body
      assert body =~ "Forbidden"
    end

    test "redirects with error flash for empty username" do
      conn =
        build_conn(:post, "/users", %{"username" => ""})
        |> init_test_session()
        |> with_csrf()
        |> dispatch(@router)

      assert conn.status == 302
      assert redirected_to(conn) == "/"

      flash = Map.get(conn.session, "_flash", %{})
      assert flash["error"] =~ "Failed"
    end
  end
end

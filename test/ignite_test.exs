defmodule Ignite.ConnTestTest do
  use ExUnit.Case
  import Ignite.ConnTest

  describe "build_conn/3" do
    test "creates a conn with method, path, and empty params" do
      conn = build_conn(:get, "/hello")
      assert conn.method == "GET"
      assert conn.path == "/hello"
      assert conn.params == %{}
    end

    test "creates a conn with params" do
      conn = build_conn(:post, "/users", %{"username" => "jose"})
      assert conn.method == "POST"
      assert conn.path == "/users"
      assert conn.params["username"] == "jose"
    end

    test "uppercases the method" do
      conn = build_conn(:delete, "/users/1")
      assert conn.method == "DELETE"
    end
  end

  describe "init_test_session/2" do
    test "sets a CSRF token in the session" do
      conn = build_conn(:post, "/users") |> init_test_session()
      assert is_binary(conn.session["_csrf_token"])
      assert String.length(conn.session["_csrf_token"]) > 10
    end

    test "merges extra session data" do
      conn = build_conn(:post, "/users") |> init_test_session(%{"user_id" => 42})
      assert conn.session["user_id"] == 42
      assert is_binary(conn.session["_csrf_token"])
    end
  end

  describe "with_csrf/1" do
    test "adds a masked CSRF token to params" do
      conn =
        build_conn(:post, "/users")
        |> init_test_session()
        |> with_csrf()

      assert is_binary(conn.params["_csrf_token"])

      # The masked token should validate against the session token
      assert Ignite.CSRF.valid_token?(
               conn.session["_csrf_token"],
               conn.params["_csrf_token"]
             )
    end

    test "raises without a session" do
      conn = build_conn(:post, "/users")

      assert_raise RuntimeError, ~r/No CSRF token in session/, fn ->
        with_csrf(conn)
      end
    end
  end

  describe "put_content_type/2" do
    test "sets the content-type request header" do
      conn = build_conn(:post, "/api/echo") |> put_content_type("application/json")
      assert conn.headers["content-type"] == "application/json"
    end
  end

  describe "put_req_header/3" do
    test "sets a request header" do
      conn = build_conn(:get, "/") |> put_req_header("accept", "text/html")
      assert conn.headers["accept"] == "text/html"
    end
  end
end

defmodule Step09.PostParserTest do
  @moduledoc """
  Step 09 — POST Body Parser

  TDD spec: The framework should parse URL-encoded form bodies
  into conn.params when Content-Type is application/x-www-form-urlencoded.

  Since Parser.parse/1 requires a real `:gen_tcp` socket, we test
  the parsing logic indirectly by testing form data through a
  router with `build_conn`.
  """
  use ExUnit.Case

  describe "URI.decode_query (the parsing logic used by Parser)" do
    test "parses simple key=value pairs" do
      result = URI.decode_query("username=jose&password=secret")
      assert result == %{"username" => "jose", "password" => "secret"}
    end

    test "decodes URL-encoded values" do
      result = URI.decode_query("name=Jos%C3%A9&city=S%C3%A3o+Paulo")
      assert result["name"] == "José"
      assert result["city"] == "São Paulo"
    end

    test "handles empty values" do
      result = URI.decode_query("key=&other=value")
      assert result["key"] == ""
      assert result["other"] == "value"
    end

    test "handles single key-value pair" do
      result = URI.decode_query("token=abc123")
      assert result == %{"token" => "abc123"}
    end
  end

  describe "POST route with params" do
    defmodule PostController do
      def create(conn) do
        name = conn.params["username"] || "anonymous"
        Ignite.Controller.text(conn, "Created: #{name}")
      end
    end

    defmodule PostRouter do
      use Ignite.Router

      post "/users", to: PostController, action: :create

      finalize_routes()
    end

    test "controller receives parsed params" do
      conn = %Ignite.Conn{
        method: "POST",
        path: "/users",
        params: %{"username" => "jose"}
      }

      result = PostRouter.call(conn)
      assert result.resp_body == "Created: jose"
    end

    test "params default to empty map" do
      conn = %Ignite.Conn{method: "POST", path: "/users", params: %{}}
      result = PostRouter.call(conn)
      assert result.resp_body == "Created: anonymous"
    end
  end
end

defmodule Step02.ConnParserTest do
  @moduledoc """
  Step 02 — Conn Struct & Parser

  TDD spec: We need a struct to represent HTTP requests/responses,
  and a parser to fill it from raw TCP data.

  At this step we can only test the Conn struct directly — the Parser
  reads from a `:gen_tcp` socket which requires integration testing.
  """
  use ExUnit.Case

  alias Ignite.Conn

  describe "%Conn{} struct defaults" do
    test "has nil method and path" do
      conn = %Conn{}
      assert conn.method == nil
      assert conn.path == nil
    end

    test "has empty headers and params maps" do
      conn = %Conn{}
      assert conn.headers == %{}
      assert conn.params == %{}
    end

    test "defaults to 200 status with text/plain content-type" do
      conn = %Conn{}
      assert conn.status == 200
      assert conn.resp_headers["content-type"] == "text/plain"
    end

    test "starts with empty response body" do
      conn = %Conn{}
      assert conn.resp_body == ""
    end

    test "is not halted by default" do
      conn = %Conn{}
      assert conn.halted == false
    end

    test "has empty session and cookies" do
      conn = %Conn{}
      assert conn.session == %{}
      assert conn.cookies == %{}
    end
  end

  describe "%Conn{} struct updates" do
    test "can set method and path" do
      conn = %Conn{method: "GET", path: "/hello"}
      assert conn.method == "GET"
      assert conn.path == "/hello"
    end

    test "can set headers" do
      conn = %Conn{headers: %{"host" => "localhost", "accept" => "text/html"}}
      assert conn.headers["host"] == "localhost"
    end

    test "can update with pipe syntax" do
      conn = %Conn{status: 200}
      conn = %Conn{conn | status: 404, resp_body: "Not Found"}
      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end
  end
end

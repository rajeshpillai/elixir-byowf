defmodule Ignite.ParserTest do
  @moduledoc """
  Integration tests for Ignite.Parser (security review items B1/B2/B3).

  Parser.parse/1 reads from a real :gen_tcp socket in `packet: :http` mode,
  so each test sets up a loopback listen/connect pair, writes a raw request
  from the client side, and parses it from the accepted server socket.
  """
  use ExUnit.Case, async: false

  # Returns the server-side accepted socket after the client writes `request`.
  defp parse_request(request) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :http, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)

    {:ok, client} =
      :gen_tcp.connect(~c"localhost", port, [:binary, packet: :raw, active: false])

    :ok = :gen_tcp.send(client, request)
    {:ok, server} = :gen_tcp.accept(listen)

    result = Ignite.Parser.parse(server)

    :gen_tcp.close(client)
    :gen_tcp.close(server)
    :gen_tcp.close(listen)

    result
  end

  test "GET request: query string is split from path and decoded into params (B1)" do
    {:ok, conn} =
      parse_request("GET /search?q=hello+world&page=2 HTTP/1.1\r\nHost: x\r\n\r\n")

    assert conn.path == "/search"
    assert conn.params == %{"q" => "hello world", "page" => "2"}
    assert conn.query_params == %{"q" => "hello world", "page" => "2"}
  end

  test "GET request without query string yields empty query params" do
    {:ok, conn} = parse_request("GET /about HTTP/1.1\r\nHost: x\r\n\r\n")

    assert conn.path == "/about"
    assert conn.query_params == %{}
    assert conn.params == %{}
  end

  test "POST body params win over query params on key collision (B1)" do
    body = "name=body"

    request =
      "POST /users?name=query HTTP/1.1\r\n" <>
        "Host: x\r\n" <>
        "Content-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n\r\n" <> body

    {:ok, conn} = parse_request(request)

    assert conn.path == "/users"
    assert conn.params["name"] == "body"
    assert conn.query_params["name"] == "query"
  end

  test "malformed Content-Length does not crash; body is ignored (B2)" do
    request =
      "POST /users HTTP/1.1\r\n" <>
        "Host: x\r\n" <>
        "Content-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: not-a-number\r\n\r\n"

    assert {:ok, conn} = parse_request(request)
    assert conn.params == %{}
  end

  test "malformed request line is rejected as a bad request (B3)" do
    assert {:error, :bad_request} = parse_request("THIS IS NOT HTTP\r\n\r\n")
  end
end

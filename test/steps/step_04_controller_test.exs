defmodule Step04.ControllerTest do
  @moduledoc """
  Step 04 — Response Helpers

  TDD spec: Controllers need helpers to set response status,
  body, and content-type on a conn without manual string building.
  """
  use ExUnit.Case

  alias Ignite.Conn
  import Ignite.Controller

  defp new_conn, do: %Conn{method: "GET", path: "/test"}

  describe "text/2,3" do
    test "sets plain text response with 200 status" do
      conn = text(new_conn(), "Hello!")
      assert conn.status == 200
      assert conn.resp_body == "Hello!"
      assert conn.resp_headers["content-type"] == "text/plain"
    end

    test "sets custom status" do
      conn = text(new_conn(), "Oops", 500)
      assert conn.status == 500
      assert conn.resp_body == "Oops"
    end

    test "halts the pipeline" do
      conn = text(new_conn(), "done")
      assert conn.halted == true
    end
  end

  describe "html/2,3" do
    test "sets HTML response with utf-8 charset" do
      conn = html(new_conn(), "<h1>Hi</h1>")
      assert conn.status == 200
      assert conn.resp_body == "<h1>Hi</h1>"
      assert conn.resp_headers["content-type"] == "text/html; charset=utf-8"
    end

    test "sets custom status" do
      conn = html(new_conn(), "<p>Error</p>", 422)
      assert conn.status == 422
    end

    test "halts the pipeline" do
      conn = html(new_conn(), "<p>done</p>")
      assert conn.halted == true
    end
  end

  describe "redirect/2" do
    test "sets 302 status and location header" do
      conn = redirect(new_conn(), to: "/dashboard")
      assert conn.status == 302
      assert conn.resp_headers["location"] == "/dashboard"
    end

    test "sets empty body and halts" do
      conn = redirect(new_conn(), to: "/")
      assert conn.resp_body == ""
      assert conn.halted == true
    end
  end

  describe "send_resp/1" do
    test "builds a valid HTTP response string" do
      conn = text(new_conn(), "OK")
      response = send_resp(conn)

      assert response =~ "HTTP/1.1 200 OK\r\n"
      assert response =~ "content-type: text/plain\r\n"
      assert response =~ "content-length: 2\r\n"
      assert response =~ "\r\n\r\nOK"
    end

    test "includes correct content-length for multi-byte strings" do
      conn = text(new_conn(), "café")
      response = send_resp(conn)
      # "café" is 5 bytes in UTF-8
      assert response =~ "content-length: 5\r\n"
    end

    test "sets connection: close header" do
      conn = text(new_conn(), "bye")
      response = send_resp(conn)
      assert response =~ "connection: close\r\n"
    end
  end
end

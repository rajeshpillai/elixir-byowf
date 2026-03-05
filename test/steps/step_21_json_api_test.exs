defmodule Step21.JsonApiTest do
  @moduledoc """
  Step 21 — JSON API

  TDD spec: Controllers need a `json/2,3` helper that encodes
  data as JSON and sets the correct content-type header.
  """
  use ExUnit.Case

  import Ignite.Controller

  defp new_conn, do: %Ignite.Conn{method: "GET", path: "/api/test"}

  describe "json/2,3" do
    test "encodes a map as JSON" do
      conn = json(new_conn(), %{status: "ok", count: 42})
      assert conn.resp_headers["content-type"] == "application/json"
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["status"] == "ok"
      assert decoded["count"] == 42
    end

    test "encodes a list as JSON" do
      conn = json(new_conn(), [1, 2, 3])
      assert Jason.decode!(conn.resp_body) == [1, 2, 3]
    end

    test "sets custom status" do
      conn = json(new_conn(), %{error: "not found"}, 404)
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "not found"
    end

    test "halts the pipeline" do
      conn = json(new_conn(), %{})
      assert conn.halted == true
    end

    test "handles nested data" do
      data = %{user: %{name: "jose", roles: ["admin", "dev"]}}
      conn = json(new_conn(), data)
      decoded = Jason.decode!(conn.resp_body)
      assert decoded["user"]["name"] == "jose"
      assert decoded["user"]["roles"] == ["admin", "dev"]
    end
  end
end

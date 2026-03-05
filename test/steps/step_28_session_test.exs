defmodule Step28.SessionTest do
  @moduledoc """
  Step 28 — Flash Messages & Sessions

  TDD spec: Sessions should be signed cookies that survive
  round-trips. Flash messages should persist for one redirect.
  """
  use ExUnit.Case

  alias Ignite.Session
  import Ignite.Controller

  describe "Session.encode/1 and decode/1" do
    test "round-trips a session map" do
      original = %{"user_id" => 42, "role" => "admin"}
      encoded = Session.encode(original)
      assert {:ok, decoded} = Session.decode(encoded)
      assert decoded == original
    end

    test "rejects tampered cookies" do
      encoded = Session.encode(%{"user_id" => 1})
      tampered = encoded <> "TAMPERED"
      assert Session.decode(tampered) == :error
    end

    test "rejects nil cookie" do
      assert Session.decode(nil) == :error
    end

    test "rejects empty string cookie" do
      assert Session.decode("") == :error
    end
  end

  describe "Session.parse_cookies/1" do
    test "parses a cookie header string" do
      result = Session.parse_cookies("name=value; session=abc123")
      assert result["name"] == "value"
      assert result["session"] == "abc123"
    end

    test "handles nil" do
      assert Session.parse_cookies(nil) == %{}
    end

    test "handles empty string" do
      assert Session.parse_cookies("") == %{}
    end

    test "handles single cookie" do
      result = Session.parse_cookies("token=xyz")
      assert result == %{"token" => "xyz"}
    end
  end

  describe "Session.build_cookie_header/1" do
    test "builds a set-cookie header with HttpOnly and SameSite" do
      header = Session.build_cookie_header(%{"user_id" => 1})
      assert header =~ "_ignite_session="
      assert header =~ "Path=/"
      assert header =~ "HttpOnly"
      assert header =~ "SameSite=Lax"
    end
  end

  describe "Session.cookie_name/0" do
    test "returns the session cookie name" do
      assert Session.cookie_name() == "_ignite_session"
    end
  end

  describe "put_flash/3 and get_flash/1,2" do
    test "stores flash message in session" do
      conn = %Ignite.Conn{session: %{}}
      conn = put_flash(conn, :info, "User created!")
      assert conn.session["_flash"]["info"] == "User created!"
    end

    test "stores multiple flash messages" do
      conn =
        %Ignite.Conn{session: %{}}
        |> put_flash(:info, "Success!")
        |> put_flash(:error, "But also this")

      assert conn.session["_flash"]["info"] == "Success!"
      assert conn.session["_flash"]["error"] == "But also this"
    end

    test "get_flash reads from private.flash" do
      conn = %Ignite.Conn{private: %{flash: %{"info" => "Hello"}}}
      assert get_flash(conn) == %{"info" => "Hello"}
      assert get_flash(conn, :info) == "Hello"
      assert get_flash(conn, :error) == nil
    end

    test "get_flash returns empty map when no flash" do
      conn = %Ignite.Conn{private: %{}}
      assert get_flash(conn) == %{}
    end
  end
end

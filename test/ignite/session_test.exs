defmodule Ignite.SessionTest do
  @moduledoc """
  Tests for signed cookie sessions, including the Secure flag (review item A4).
  """
  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:ignite, :ssl)
    on_exit(fn -> restore(:ssl, original) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:ignite, key)
  defp restore(key, value), do: Application.put_env(:ignite, key, value)

  test "encode then decode round-trips a session map" do
    cookie = Ignite.Session.encode(%{"user_id" => 42})
    assert {:ok, %{"user_id" => 42}} = Ignite.Session.decode(cookie)
  end

  test "decode rejects a tampered cookie" do
    cookie = Ignite.Session.encode(%{"user_id" => 42})
    assert :error = Ignite.Session.decode(cookie <> "tampered")
  end

  test "cookie has no Secure flag in plain-HTTP (no :ssl config)" do
    Application.delete_env(:ignite, :ssl)
    header = Ignite.Session.build_cookie_header(%{"a" => 1})

    assert header =~ "HttpOnly"
    assert header =~ "SameSite=Lax"
    refute header =~ "Secure"
  end

  test "cookie gains the Secure flag when SSL is configured (A4)" do
    Application.put_env(:ignite, :ssl, certfile: "x.pem", keyfile: "x.key")
    header = Ignite.Session.build_cookie_header(%{"a" => 1})

    assert header =~ "; Secure"
  end
end

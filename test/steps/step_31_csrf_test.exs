defmodule Step31.CsrfTest do
  @moduledoc """
  Step 31 — CSRF Protection

  TDD spec: CSRF tokens should be random, maskable (for BREACH
  resistance), and verifiable. Each mask produces a different
  string but validates against the same session token.
  """
  use ExUnit.Case

  alias Ignite.CSRF

  describe "generate_token/0" do
    test "produces a base64url-encoded string" do
      token = CSRF.generate_token()
      assert is_binary(token)
      assert {:ok, _} = Base.url_decode64(token, padding: false)
    end

    test "produces unique tokens each call" do
      t1 = CSRF.generate_token()
      t2 = CSRF.generate_token()
      assert t1 != t2
    end

    test "token is 32 bytes when decoded" do
      token = CSRF.generate_token()
      {:ok, decoded} = Base.url_decode64(token, padding: false)
      assert byte_size(decoded) == 32
    end
  end

  describe "mask_token/1" do
    test "produces a different string than the original" do
      token = CSRF.generate_token()
      masked = CSRF.mask_token(token)
      assert masked != token
    end

    test "each mask is different (random mask bytes)" do
      token = CSRF.generate_token()
      m1 = CSRF.mask_token(token)
      m2 = CSRF.mask_token(token)
      assert m1 != m2
    end

    test "masked token is double the decoded size" do
      token = CSRF.generate_token()
      masked = CSRF.mask_token(token)
      {:ok, decoded_masked} = Base.url_decode64(masked, padding: false)
      {:ok, decoded_token} = Base.url_decode64(token, padding: false)
      assert byte_size(decoded_masked) == byte_size(decoded_token) * 2
    end
  end

  describe "valid_token?/2" do
    test "validates a masked token against the session token" do
      token = CSRF.generate_token()
      masked = CSRF.mask_token(token)
      assert CSRF.valid_token?(token, masked) == true
    end

    test "validates multiple different masks of same token" do
      token = CSRF.generate_token()
      for _ <- 1..5 do
        masked = CSRF.mask_token(token)
        assert CSRF.valid_token?(token, masked) == true
      end
    end

    test "rejects wrong token" do
      token1 = CSRF.generate_token()
      token2 = CSRF.generate_token()
      masked = CSRF.mask_token(token1)
      assert CSRF.valid_token?(token2, masked) == false
    end

    test "rejects nil inputs" do
      assert CSRF.valid_token?(nil, nil) == false
      assert CSRF.valid_token?(nil, "abc") == false
      assert CSRF.valid_token?("abc", nil) == false
    end

    test "rejects garbage input" do
      token = CSRF.generate_token()
      assert CSRF.valid_token?(token, "not-a-valid-token!!!") == false
    end
  end

  describe "csrf_token_tag/1" do
    test "returns a hidden input element" do
      conn = %Ignite.Conn{session: %{"_csrf_token" => CSRF.generate_token()}}
      tag = CSRF.csrf_token_tag(conn)
      assert tag =~ ~s(<input type="hidden" name="_csrf_token")
      assert tag =~ ~s(value=")
    end
  end

  describe "get_token/1" do
    test "returns session token when present" do
      token = CSRF.generate_token()
      conn = %Ignite.Conn{session: %{"_csrf_token" => token}}
      assert CSRF.get_token(conn) == token
    end

    test "generates new token when session is empty" do
      conn = %Ignite.Conn{session: %{}}
      token = CSRF.get_token(conn)
      assert is_binary(token)
      assert byte_size(token) > 10
    end
  end
end

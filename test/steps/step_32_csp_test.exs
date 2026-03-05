defmodule Step32.CspTest do
  @moduledoc """
  Step 32 — Content Security Policy

  TDD spec: CSP should generate per-request nonces, embed them
  in the CSP header, and provide helpers to tag inline scripts.
  """
  use ExUnit.Case

  alias Ignite.CSP

  describe "generate_nonce/0" do
    test "produces a base64url-encoded string" do
      nonce = CSP.generate_nonce()
      assert is_binary(nonce)
      assert {:ok, _} = Base.url_decode64(nonce, padding: false)
    end

    test "each nonce is unique" do
      n1 = CSP.generate_nonce()
      n2 = CSP.generate_nonce()
      assert n1 != n2
    end

    test "nonce is 16 bytes when decoded" do
      nonce = CSP.generate_nonce()
      {:ok, decoded} = Base.url_decode64(nonce, padding: false)
      assert byte_size(decoded) == 16
    end
  end

  describe "put_csp_headers/1" do
    test "adds content-security-policy header" do
      conn = %Ignite.Conn{}
      conn = CSP.put_csp_headers(conn)
      csp = conn.resp_headers["content-security-policy"]
      assert is_binary(csp)
      assert csp =~ "default-src 'self'"
    end

    test "stores nonce in conn.private" do
      conn = CSP.put_csp_headers(%Ignite.Conn{})
      assert is_binary(conn.private[:csp_nonce])
    end

    test "CSP header includes the nonce" do
      conn = CSP.put_csp_headers(%Ignite.Conn{})
      nonce = conn.private[:csp_nonce]
      csp = conn.resp_headers["content-security-policy"]
      assert csp =~ "nonce-#{nonce}"
    end
  end

  describe "csp_nonce/1" do
    test "returns the nonce from conn" do
      conn = CSP.put_csp_headers(%Ignite.Conn{})
      nonce = CSP.csp_nonce(conn)
      assert nonce == conn.private[:csp_nonce]
    end

    test "returns empty string when no nonce set" do
      conn = %Ignite.Conn{}
      assert CSP.csp_nonce(conn) == ""
    end
  end

  describe "csp_script_tag/2" do
    test "wraps JS in a script tag with nonce" do
      conn = CSP.put_csp_headers(%Ignite.Conn{})
      tag = CSP.csp_script_tag(conn, "alert('hi');")
      nonce = CSP.csp_nonce(conn)
      expected = "<script nonce=\"#{nonce}\">alert('hi');</script>"
      assert tag == expected
    end
  end

  describe "build_header/1" do
    test "includes all security directives" do
      header = CSP.build_header("test-nonce")
      assert header =~ "default-src 'self'"
      assert header =~ "script-src 'self' 'nonce-test-nonce'"
      assert header =~ "style-src 'self' 'unsafe-inline'"
      assert header =~ "img-src 'self' data:"
      assert header =~ "connect-src 'self' ws: wss:"
      assert header =~ "object-src 'none'"
      assert header =~ "form-action 'self'"
    end

    test "directives are semicolon-separated" do
      header = CSP.build_header("n")
      parts = String.split(header, "; ")
      assert length(parts) == 9
    end
  end
end

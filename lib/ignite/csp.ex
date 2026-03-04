defmodule Ignite.CSP do
  @moduledoc """
  Content Security Policy (CSP) header generation.

  CSP tells the browser which sources of scripts, styles, images, and
  connections are allowed. Even if an attacker injects HTML via an XSS
  vulnerability, the browser will refuse to execute scripts that don't
  match the policy.

  ## Nonce-based script protection

  Instead of allowing all inline scripts (`'unsafe-inline'`), we generate
  a random **nonce** per request. Only `<script nonce="...">` tags whose
  nonce matches the CSP header are executed. This blocks injected scripts
  while allowing our own inline code to work.

  ## Usage

      # In a router plug:
      def set_csp_headers(conn) do
        Ignite.CSP.put_csp_headers(conn)
      end

      # In a controller (inline script with nonce):
      html(conn, \"""
      <script nonce="\#{csp_nonce(conn)}">
        console.log("allowed!");
      </script>
      \""")
  """

  @nonce_size 16

  @doc """
  Generates a random nonce (base64-encoded, 16 bytes).
  """
  def generate_nonce do
    @nonce_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Adds CSP headers to the conn and stores a nonce in `conn.private`.

  Call this in a router plug. The nonce is then available via
  `csp_nonce(conn)` in controllers.
  """
  def put_csp_headers(conn) do
    nonce = generate_nonce()

    %Ignite.Conn{
      conn
      | private: Map.put(conn.private, :csp_nonce, nonce),
        resp_headers: Map.put(conn.resp_headers, "content-security-policy", build_header(nonce))
    }
  end

  @doc """
  Reads the CSP nonce from the conn.

  Returns the nonce string, or `""` if none was set.
  """
  def csp_nonce(conn) do
    Map.get(conn.private, :csp_nonce, "")
  end

  @doc """
  Wraps JavaScript code in a `<script>` tag with the CSP nonce.

  ## Example

      csp_script_tag(conn, "console.log('hello');")
      #=> ~s(<script nonce="abc123">console.log('hello');</script>)
  """
  def csp_script_tag(conn, js_code) do
    nonce = csp_nonce(conn)
    ~s(<script nonce="#{nonce}">#{js_code}</script>)
  end

  @doc """
  Builds the CSP header value with the given nonce.

  Policy:
  - `default-src 'self'` — only load resources from same origin
  - `script-src 'self' 'nonce-...'` — scripts must be same-origin or have correct nonce
  - `style-src 'self' 'unsafe-inline'` — allow inline styles (too pervasive to nonce)
  - `img-src 'self' data:` — allow images and data URIs
  - `connect-src 'self' ws: wss:` — allow WebSocket for LiveView
  - `font-src 'self'` — fonts from same origin
  - `object-src 'none'` — block Flash/Java plugins
  - `base-uri 'self'` — prevent base tag hijacking
  - `form-action 'self'` — forms can only submit to same origin
  """
  def build_header(nonce) do
    [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "connect-src 'self' ws: wss:",
      "font-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end

defmodule Ignite.CSRF do
  @moduledoc """
  Cross-Site Request Forgery (CSRF) protection.

  Generates a per-session token, embeds it in HTML forms as a hidden
  input, and validates it on every state-changing request (POST, PUT,
  PATCH, DELETE).

  ## How it works

  1. On the first request, a random token is generated and stored in
     `conn.session["_csrf_token"]`.

  2. When rendering a form, `csrf_token_tag/1` embeds a **masked**
     version of the token in a hidden input. Masking prevents the
     BREACH compression attack — each page load produces a
     different-looking token even though the underlying secret is
     the same.

  3. On form submission, the router's `verify_csrf_token` plug
     compares the submitted `_csrf_token` param against the session
     token. If they don't match, the request is rejected with 403.

  4. JSON API requests are exempt — they rely on SameSite cookies
     and browser CORS policy instead.

  ## Masking (BREACH mitigation)

  The masked token is `Base.url_encode64(mask <> xor(mask, token))`.
  To unmask: split the decoded bytes in half, XOR the two halves.
  This is the same approach Phoenix uses.
  """

  @token_size 32

  @doc """
  Generates a new random CSRF token (base64url-encoded).
  """
  def generate_token do
    @token_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns the CSRF token from the session, or generates one if missing.
  """
  def get_token(conn) do
    conn.session["_csrf_token"] || generate_token()
  end

  @doc """
  Produces a masked version of the given token.

  Each call returns a different string (because the mask is random),
  but `valid_token?/2` can still verify it against the original.
  """
  def mask_token(token) do
    decoded = Base.url_decode64!(token, padding: false)
    mask = :crypto.strong_rand_bytes(byte_size(decoded))
    masked = xor_bytes(mask, decoded)
    Base.url_encode64(mask <> masked, padding: false)
  end

  @doc """
  Validates a submitted (masked) token against the session token.

  Returns `true` if the unmasked submitted token matches the session
  token, `false` otherwise.
  """
  def valid_token?(session_token, submitted_token)
      when is_binary(session_token) and is_binary(submitted_token) do
    with {:ok, decoded_session} <- Base.url_decode64(session_token, padding: false),
         {:ok, decoded_submitted} <- Base.url_decode64(submitted_token, padding: false) do
      size = byte_size(decoded_session)

      if byte_size(decoded_submitted) == size * 2 do
        <<mask::binary-size(size), masked::binary-size(size)>> = decoded_submitted
        unmasked = xor_bytes(mask, masked)
        Plug.Crypto.secure_compare(decoded_session, unmasked)
      else
        false
      end
    else
      _ -> false
    end
  end

  def valid_token?(_, _), do: false

  @doc """
  Returns an HTML hidden input containing a masked CSRF token.

  ## Example

      csrf_token_tag(conn)
      #=> ~s(<input type="hidden" name="_csrf_token" value="...">)
  """
  def csrf_token_tag(conn) do
    token = get_token(conn)
    masked = mask_token(token)
    ~s(<input type="hidden" name="_csrf_token" value="#{masked}">)
  end

  # Bitwise XOR of two equal-length binaries.
  defp xor_bytes(a, b) do
    a_list = :binary.bin_to_list(a)
    b_list = :binary.bin_to_list(b)

    a_list
    |> Enum.zip(b_list)
    |> Enum.map(fn {x, y} -> Bitwise.bxor(x, y) end)
    |> :binary.list_to_bin()
  end
end

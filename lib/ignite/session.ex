defmodule Ignite.Session do
  @moduledoc """
  Signed cookie-based sessions.

  Session data is serialized with `:erlang.term_to_binary/1`, signed
  using `Plug.Crypto.MessageVerifier` (a transitive dependency of
  plug_cowboy — no new deps needed), and stored in a cookie.

  The signature prevents tampering: if anyone modifies the cookie value,
  `decode/1` returns `:error` and the session is treated as empty.

  ## How it works

  1. On request: the Cowboy adapter reads the `_ignite_session` cookie,
     calls `decode/1` to verify + deserialize it into a map.

  2. During the request: controllers can read/write `conn.session`.
     `put_flash/3` stores messages in `session["_flash"]`.

  3. On response: the adapter calls `encode/1` to serialize + sign
     the updated session and sets it as a `set-cookie` header.
  """

  # In production, set SECRET_KEY_BASE as an environment variable.
  # Must be at least 64 bytes for security.
  # In dev/test, the default fallback is used automatically.
  @default_secret "ignite-secret-key-change-in-prod-min-64-bytes-long-for-security!!"

  defp secret do
    Application.get_env(:ignite, :secret_key_base, @default_secret)
  end
  @cookie_name "_ignite_session"

  @doc "Returns the session cookie name."
  def cookie_name, do: @cookie_name

  @doc """
  Encodes a session map into a signed cookie value.

  ## Example

      iex> Ignite.Session.encode(%{"user_id" => 42})
      "SFMy..."
  """
  def encode(session) when is_map(session) do
    session
    |> :erlang.term_to_binary()
    |> Plug.Crypto.MessageVerifier.sign(secret())
  end

  @doc """
  Decodes and verifies a signed session cookie.

  Returns `{:ok, session_map}` if the signature is valid,
  or `:error` if the cookie is missing, tampered, or malformed.

  ## Example

      iex> {:ok, session} = Ignite.Session.decode(cookie_value)
      iex> session["user_id"]
      42
  """
  def decode(nil), do: :error
  def decode(""), do: :error

  def decode(cookie_value) when is_binary(cookie_value) do
    case Plug.Crypto.MessageVerifier.verify(cookie_value, secret()) do
      {:ok, binary} ->
        # safe: only allow existing atoms — prevents atom table DoS
        {:ok, :erlang.binary_to_term(binary, [:safe])}

      :error ->
        :error
    end
  end

  @doc """
  Parses a raw `Cookie` header string into a map.

  ## Example

      iex> Ignite.Session.parse_cookies("name=value; _ignite_session=abc123")
      %{"name" => "value", "_ignite_session" => "abc123"}
  """
  def parse_cookies(nil), do: %{}
  def parse_cookies(""), do: %{}

  def parse_cookies(cookie_header) when is_binary(cookie_header) do
    cookie_header
    |> String.split(";")
    |> Enum.into(%{}, fn pair ->
      case String.split(String.trim(pair), "=", parts: 2) do
        [key, value] -> {key, value}
        [key] -> {key, ""}
      end
    end)
  end

  @doc """
  Builds a `set-cookie` header value for the session.
  """
  def build_cookie_header(session) do
    value = encode(session)
    "#{@cookie_name}=#{value}; Path=/; HttpOnly; SameSite=Lax"
  end
end

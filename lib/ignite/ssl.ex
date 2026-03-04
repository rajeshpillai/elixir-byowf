defmodule Ignite.SSL do
  @moduledoc """
  SSL/TLS configuration for Ignite.

  Reads the `:ssl` key from application config and determines whether
  to start Cowboy in clear (HTTP) or TLS (HTTPS) mode.

  ## Configuration

      # config/prod.exs
      config :ignite,
        port: 4443,
        ssl: [
          certfile: "priv/ssl/cert.pem",
          keyfile: "priv/ssl/key.pem"
        ]

  When `:ssl` is nil (dev/test), Cowboy starts with `:start_clear`.
  When `:ssl` is set, it starts with `:start_tls` using the given
  certificate and key files.
  """

  @doc """
  Returns the Cowboy child spec for either HTTP or HTTPS.

  Reads `Application.get_env(:ignite, :ssl)` to decide which mode.
  Validates that certificate files exist before starting TLS.
  """
  def child_spec(port, dispatch) do
    case Application.get_env(:ignite, :ssl) do
      nil ->
        # Plain HTTP (dev/test)
        %{
          id: :cowboy_listener,
          start:
            {:cowboy, :start_clear,
             [
               :ignite_http,
               [port: port],
               %{env: %{dispatch: dispatch}}
             ]}
        }

      ssl_opts when is_list(ssl_opts) ->
        # HTTPS (prod)
        certfile = Keyword.fetch!(ssl_opts, :certfile)
        keyfile = Keyword.fetch!(ssl_opts, :keyfile)

        validate_file!(certfile, "SSL certificate")
        validate_file!(keyfile, "SSL private key")

        # Erlang :ssl expects charlists for file paths
        tls_opts =
          [
            port: port,
            certfile: String.to_charlist(certfile),
            keyfile: String.to_charlist(keyfile)
          ]
          |> maybe_add(:cacertfile, ssl_opts)

        %{
          id: :cowboy_listener,
          start:
            {:cowboy, :start_tls,
             [
               :ignite_https,
               tls_opts,
               %{env: %{dispatch: dispatch}}
             ]}
        }
    end
  end

  @doc """
  Returns a Cowboy child spec for the HTTP-to-HTTPS redirect listener.

  All requests receive a 301 redirect to the HTTPS URL on the given port.
  """
  def redirect_child_spec(http_port, https_port) do
    redirect_dispatch =
      :cowboy_router.compile([
        {:_, [{"/[...]", Ignite.SSL.RedirectHandler, %{https_port: https_port}}]}
      ])

    %{
      id: :cowboy_redirect_listener,
      start:
        {:cowboy, :start_clear,
         [
           :ignite_http_redirect,
           [port: http_port],
           %{env: %{dispatch: redirect_dispatch}}
         ]}
    }
  end

  @doc """
  Returns true if SSL is configured.
  """
  def ssl_configured? do
    Application.get_env(:ignite, :ssl) != nil
  end

  # Adds an optional SSL option (like :cacertfile) if present in config.
  defp maybe_add(tls_opts, key, ssl_opts) do
    case Keyword.get(ssl_opts, key) do
      nil -> tls_opts
      value -> Keyword.put(tls_opts, key, String.to_charlist(value))
    end
  end

  defp validate_file!(path, label) do
    unless File.exists?(path) do
      raise """
      #{label} not found: #{path}

      To generate self-signed certificates for testing:

          mix ignite.gen.cert

      For production, use certificates from Let's Encrypt or your CA.
      """
    end
  end
end

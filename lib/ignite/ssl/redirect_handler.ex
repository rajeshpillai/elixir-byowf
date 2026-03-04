defmodule Ignite.SSL.RedirectHandler do
  @moduledoc """
  Cowboy handler that 301-redirects all HTTP requests to HTTPS.

  Preserves the original path and query string. The target HTTPS port
  is passed in via init state.

  ## Example

  A request to `http://localhost:4080/hello?name=Jose` becomes:

      301 → https://localhost:4443/hello?name=Jose

  If the HTTPS port is 443 (standard), the port is omitted from the URL.
  """

  @behaviour :cowboy_handler

  @impl true
  def init(req, state) do
    https_port = state.https_port
    host = :cowboy_req.host(req)
    path = :cowboy_req.path(req)
    qs = :cowboy_req.qs(req)

    location = build_https_url(host, https_port, path, qs)

    req =
      :cowboy_req.reply(
        301,
        %{"location" => location},
        "Moved permanently to #{location}",
        req
      )

    {:ok, req, state}
  end

  defp build_https_url(host, 443, path, ""), do: "https://#{host}#{path}"
  defp build_https_url(host, 443, path, qs), do: "https://#{host}#{path}?#{qs}"
  defp build_https_url(host, port, path, ""), do: "https://#{host}:#{port}#{path}"
  defp build_https_url(host, port, path, qs), do: "https://#{host}:#{port}#{path}?#{qs}"
end

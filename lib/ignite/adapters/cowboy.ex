defmodule Ignite.Adapters.Cowboy do
  @moduledoc """
  Bridges Cowboy's request format with Ignite's %Conn{} struct.

  Cowboy calls `init/2` for every HTTP request. We convert the Cowboy
  request into an %Ignite.Conn{}, run it through the router, and send
  the response back through Cowboy.
  """

  @behaviour :cowboy_handler

  require Logger

  @impl true
  def init(req, state) do
    req =
      try do
        # 1. Convert Cowboy request → Ignite.Conn
        conn = cowboy_to_conn(req)

        # 2. Route through our framework
        conn = MyApp.Router.call(conn)

        # 3. Send response back through Cowboy
        :cowboy_req.reply(conn.status, conn.resp_headers, conn.resp_body, req)
      rescue
        exception ->
          # Log the error with full stacktrace for debugging
          Logger.error("""
          [Ignite] Request crashed:
          #{Exception.format(:error, exception, __STACKTRACE__)}
          """)

          # Return a 500 error page to the user
          :cowboy_req.reply(
            500,
            %{"content-type" => "text/html"},
            error_page(exception),
            req
          )
      end

    {:ok, req, state}
  end

  # In development, show the error details. In production, you'd
  # want a generic "Something went wrong" page instead.
  defp error_page(exception) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>500 — Internal Server Error</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 700px; margin: 50px auto; }
      h1 { color: #e74c3c; }
      pre { background: #2d2d2d; color: #f8f8f2; padding: 16px;
            border-radius: 8px; overflow-x: auto; }
    </style>
    </head>
    <body>
      <h1>500 — Internal Server Error</h1>
      <p>Something went wrong while processing your request.</p>
      <pre>#{Exception.message(exception)}</pre>
      <p><a href="/">Back to Home</a></p>
    </body>
    </html>
    """
  end

  defp cowboy_to_conn(req) do
    # Read the body if present (POST/PUT/PATCH)
    {body_params, _req} = read_cowboy_body(req)

    # Convert Cowboy headers (list of tuples) to a map
    headers =
      req.headers
      |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)

    %Ignite.Conn{
      method: req.method,
      path: req.path,
      headers: headers,
      params: body_params
    }
  end

  defp read_cowboy_body(req) do
    case :cowboy_req.has_body(req) do
      true ->
        {:ok, body, req} = :cowboy_req.read_body(req)
        content_type = :cowboy_req.header("content-type", req, "")
        {parse_body(body, content_type), req}

      false ->
        {%{}, req}
    end
  end

  defp parse_body(body, "application/x-www-form-urlencoded" <> _) do
    URI.decode_query(body)
  end

  defp parse_body(body, "application/json" <> _) when byte_size(body) > 0 do
    case Jason.decode(body) do
      {:ok, parsed} when is_map(parsed) -> parsed
      {:ok, parsed} -> %{"_json" => parsed}
      {:error, _} -> %{"_body" => body}
    end
  end

  defp parse_body(body, _) when byte_size(body) > 0 do
    %{"_body" => body}
  end

  defp parse_body(_, _), do: %{}
end

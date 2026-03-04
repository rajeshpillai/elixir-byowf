defmodule Ignite.Adapters.Cowboy do
  @moduledoc """
  Bridges Cowboy's request format with Ignite's %Conn{} struct.

  Cowboy calls `init/2` for every HTTP request. We convert the Cowboy
  request into an %Ignite.Conn{}, run it through the router, and send
  the response back through Cowboy.
  """

  @behaviour :cowboy_handler

  @impl true
  def init(req, state) do
    # 1. Convert Cowboy request → Ignite.Conn
    conn = cowboy_to_conn(req)

    # 2. Route through our framework
    conn = MyApp.Router.call(conn)

    # 3. Send response back through Cowboy
    req =
      :cowboy_req.reply(
        conn.status,
        conn.resp_headers,
        conn.resp_body,
        req
      )

    {:ok, req, state}
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

  defp parse_body(body, _) when byte_size(body) > 0 do
    %{"_body" => body}
  end

  defp parse_body(_, _), do: %{}
end

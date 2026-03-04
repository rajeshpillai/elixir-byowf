defmodule Ignite.Parser do
  @moduledoc """
  Parses raw HTTP data from a TCP socket into an %Ignite.Conn{} struct.

  Handles both GET and POST requests. For POST requests, reads and parses
  the request body based on the Content-Type header.
  """

  alias Ignite.Conn

  @doc """
  Reads an HTTP request from a client socket and returns an %Ignite.Conn{}.

  Uses Erlang's built-in HTTP parser (via `packet: :http` on the socket)
  to read the request line and headers. For POST requests, also reads
  the body and parses form data into params.
  """
  def parse(client_socket) do
    {method, path} = read_request_line(client_socket)
    headers = read_headers(client_socket)

    # Parse body for POST/PUT/PATCH requests
    body_params = read_body(client_socket, headers)

    %Conn{
      method: to_string(method),
      path: path,
      headers: headers,
      params: body_params
    }
  end

  defp read_request_line(socket) do
    {:ok, {:http_request, method, {:abs_path, path}, _version}} =
      :gen_tcp.recv(socket, 0)

    {method, path}
  end

  defp read_headers(socket, acc \\ %{}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        key = name |> to_string() |> String.downcase()
        read_headers(socket, Map.put(acc, key, value))
    end
  end

  # Reads the request body if Content-Length is present.
  # After reading headers, Erlang's HTTP parser is done, so we switch
  # the socket back to raw binary mode to read the body bytes.
  defp read_body(socket, headers) do
    case Map.get(headers, "content-length") do
      nil ->
        %{}

      length_str ->
        content_length = String.to_integer(length_str)

        # Switch from :http packet mode to raw binary mode
        :inet.setopts(socket, packet: :raw)

        case :gen_tcp.recv(socket, content_length) do
          {:ok, body} ->
            parse_body(body, Map.get(headers, "content-type", ""))

          _ ->
            %{}
        end
    end
  end

  # Parses "username=jose&password=secret" into %{"username" => "jose", ...}
  defp parse_body(body, "application/x-www-form-urlencoded" <> _) do
    URI.decode_query(body)
  end

  # Unknown content type — return body as-is under "_body" key
  defp parse_body(body, _content_type) do
    %{"_body" => body}
  end
end

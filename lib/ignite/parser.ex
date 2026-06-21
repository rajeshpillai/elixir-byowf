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
    with {:ok, {method, raw_path}} <- read_request_line(client_socket) do
      headers = read_headers(client_socket)

      # Separate the path from the query string. The router matches on the path
      # alone, so "/users?page=2" must become path "/users" + query %{"page" => "2"}.
      {path, query_params} = split_query(raw_path)

      # Parse body for POST/PUT/PATCH requests
      body_params = read_body(client_socket, headers)

      # Body params win over query params on key collisions (same as Phoenix).
      params = Map.merge(query_params, body_params)

      {:ok,
       %Conn{
         method: to_string(method),
         path: path,
         headers: headers,
         params: params,
         query_params: query_params
       }}
    end
  end

  # Splits "/users?page=2&sort=asc" into {"/users", %{"page" => "2", "sort" => "asc"}}.
  # A path with no "?" yields an empty query map.
  defp split_query(raw_path) do
    case String.split(to_string(raw_path), "?", parts: 2) do
      [path, query] -> {path, URI.decode_query(query)}
      [path] -> {path, %{}}
    end
  end

  defp read_request_line(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, {:http_request, method, {:abs_path, path}, _version}} ->
        {:ok, {method, path}}

      # Anything else — an unsupported request target (e.g. CONNECT or an
      # absolute URI), an {:http_error, _} from a malformed request, or a
      # closed/erroring socket — is rejected as a bad request rather than
      # crashing the connection process.
      _ ->
        {:error, :bad_request}
    end
  end

  defp read_headers(socket, acc \\ %{}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        key = name |> to_string() |> String.downcase()
        # Under `packet: :http`, header values arrive as charlists. Normalize
        # to binaries so they match binary patterns (e.g. the content-type
        # check in parse_body) and so consumers like String.split work — the
        # Cowboy adapter already supplies binary header values.
        read_headers(socket, Map.put(acc, key, to_string(value)))

      # Malformed header line or socket error — stop reading and use what we
      # have so far instead of crashing.
      _ ->
        acc
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
        # Content-Length is client-supplied — a non-numeric value must not
        # crash the parser (String.to_integer/1 would raise). Treat anything
        # invalid as "no body".
        case Integer.parse(to_string(length_str)) do
          {content_length, _rest} when content_length >= 0 ->
            # Switch from :http packet mode to raw binary mode
            :inet.setopts(socket, packet: :raw)

            case :gen_tcp.recv(socket, content_length) do
              {:ok, body} ->
                parse_body(body, Map.get(headers, "content-type", ""))

              _ ->
                %{}
            end

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

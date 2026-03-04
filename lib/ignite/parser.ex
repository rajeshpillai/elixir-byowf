defmodule Ignite.Parser do
  @moduledoc """
  Parses raw HTTP data from a TCP socket into an %Ignite.Conn{} struct.

  This module bridges the gap between raw network data and structured
  Elixir data that the rest of our framework can work with.
  """

  alias Ignite.Conn

  @doc """
  Reads an HTTP request from a client socket and returns an %Ignite.Conn{}.

  Uses Erlang's built-in HTTP parser (via `packet: :http` on the socket)
  to read the request line and headers one at a time.
  """
  def parse(client_socket) do
    {method, path} = read_request_line(client_socket)
    headers = read_headers(client_socket)

    %Conn{
      method: to_string(method),
      path: path,
      headers: headers
    }
  end

  # Reads the first line of the HTTP request.
  # Example: "GET /hello HTTP/1.1" becomes {:GET, "/hello"}
  defp read_request_line(socket) do
    {:ok, {:http_request, method, {:abs_path, path}, _version}} =
      :gen_tcp.recv(socket, 0)

    {method, path}
  end

  # Reads headers one at a time until we hit the blank line
  # that marks the end of headers (:http_eoh = "end of headers").
  # Returns a map like %{"host" => "localhost:4000", "user-agent" => "..."}
  defp read_headers(socket, acc \\ %{}) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        # Normalize header names to lowercase strings
        key = name |> to_string() |> String.downcase()
        read_headers(socket, Map.put(acc, key, value))
    end
  end
end

defmodule Ignite.Server do
  @moduledoc """
  A basic TCP server that listens for HTTP requests.

  This is the foundation of our web framework. Every web framework
  is just a program that listens on a TCP port, reads the request,
  and sends back a response.
  """

  require Logger

  @doc """
  Starts the server on the given port (default 4000).

  ## Example

      iex> Ignite.Server.start(4000)

  Then visit http://localhost:4000 in your browser.
  """
  def start(port \\ 4000) do
    # Open a TCP socket that listens on the given port.
    #
    # Options:
    #   :binary       - receive data as binary strings (not charlists)
    #   packet: :http - let Erlang parse HTTP for us (request line + headers)
    #   active: false - we manually control when to read data (pull mode)
    #   reuseaddr: true - allows restarting the server immediately after stopping
    {:ok, listen_socket} = :gen_tcp.listen(port, [
      :binary,
      packet: :http,
      active: false,
      reuseaddr: true
    ])

    Logger.info("Ignite is heating up on http://localhost:#{port}")

    # Start accepting connections in an infinite loop
    loop_acceptor(listen_socket)
  end

  # This function runs forever, waiting for the next client to connect.
  # When a client connects, it spawns a new process to handle the request
  # and immediately loops back to wait for the next one.
  defp loop_acceptor(listen_socket) do
    # Block until a client (browser) connects
    {:ok, client_socket} = :gen_tcp.accept(listen_socket)

    # Handle this request in a separate BEAM process.
    # This way, one slow request doesn't block others.
    spawn(fn -> serve(client_socket) end)

    # Immediately go back to waiting for the next connection
    loop_acceptor(listen_socket)
  end

  # Read the HTTP request from the client and send back a response.
  defp serve(client_socket) do
    # Read the HTTP request line (e.g., "GET /hello HTTP/1.1")
    request_line = read_request_line(client_socket)

    # Read and discard the headers (we'll parse them in Step 2)
    read_headers(client_socket)

    Logger.info("Received: #{inspect(request_line)}")

    # Build and send the HTTP response
    body = "Hello, Ignite!"
    response = build_response(200, body)
    :gen_tcp.send(client_socket, response)
    :gen_tcp.close(client_socket)
  end

  # Reads the HTTP request line using Erlang's built-in HTTP parsing.
  # With `packet: :http`, Erlang parses each part of the HTTP request
  # into tagged tuples for us.
  defp read_request_line(socket) do
    {:ok, {:http_request, method, {:abs_path, path}, _version}} = :gen_tcp.recv(socket, 0)
    {method, path}
  end

  # Reads headers one at a time until we hit the end-of-headers marker.
  # We don't use the headers yet, but we must read them to consume
  # the full request from the socket.
  defp read_headers(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        # End of headers — we're done
        :ok

      {:ok, {:http_header, _, _name, _, _value}} ->
        # Got a header, keep reading
        read_headers(socket)
    end
  end

  # Builds a raw HTTP/1.1 response string.
  # HTTP responses have this format:
  #
  #   HTTP/1.1 200 OK\r\n
  #   Content-Type: text/plain\r\n
  #   Content-Length: 14\r\n
  #   \r\n
  #   Hello, Ignite!
  #
  # The blank line (\r\n\r\n) separates headers from the body.
  defp build_response(status_code, body) do
    status_text = status_text(status_code)

    "HTTP/1.1 #{status_code} #{status_text}\r\n" <>
      "Content-Type: text/plain\r\n" <>
      "Content-Length: #{byte_size(body)}\r\n" <>
      "Connection: close\r\n" <>
      "\r\n" <>
      body
  end

  defp status_text(200), do: "OK"
  defp status_text(404), do: "Not Found"
  defp status_text(_), do: "OK"
end

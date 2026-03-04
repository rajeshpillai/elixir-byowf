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

  # Parse → Route → Respond. The three-step lifecycle of every request.
  defp serve(client_socket) do
    # 1. Parse: turn raw HTTP into a structured %Ignite.Conn{}
    conn = Ignite.Parser.parse(client_socket)

    Logger.info("#{conn.method} #{conn.path}")

    # 2. Route: hand the conn to the router, which finds the right controller
    conn = MyApp.Router.call(conn)

    # 3. Respond: convert the conn into raw HTTP and send it
    response = Ignite.Controller.send_resp(conn)
    :gen_tcp.send(client_socket, response)
    :gen_tcp.close(client_socket)
  end
end

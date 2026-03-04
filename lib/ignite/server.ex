defmodule Ignite.Server do
  @moduledoc """
  A supervised TCP server using GenServer.

  This server is managed by an OTP Supervisor. If it crashes,
  the supervisor automatically restarts it — no manual intervention needed.
  """

  use GenServer
  require Logger

  # --- Client API ---
  # These functions are called from outside (e.g., the supervisor).

  @doc """
  Starts the server as a supervised GenServer process.

  Called by the supervisor in `Ignite.Application`.
  """
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  # --- GenServer Callbacks ---
  # These functions are called by the GenServer behavior.

  @impl true
  def init(port) do
    # We use {:continue, :listen} so the supervisor doesn't block
    # waiting for us to open the socket. The init returns immediately,
    # and handle_continue runs right after.
    {:ok, %{port: port}, {:continue, :listen}}
  end

  @impl true
  def handle_continue(:listen, %{port: port} = state) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [
      :binary,
      packet: :http,
      active: false,
      reuseaddr: true
    ])

    Logger.info("Ignite is heating up on http://localhost:#{port}")

    # Start the accept loop in a linked process.
    # If this process crashes, the GenServer crashes too,
    # and the supervisor restarts both.
    spawn_link(fn -> loop_acceptor(listen_socket) end)

    {:noreply, Map.put(state, :listen_socket, listen_socket)}
  end

  # --- Private Functions ---

  defp loop_acceptor(listen_socket) do
    {:ok, client_socket} = :gen_tcp.accept(listen_socket)

    # Task.start creates a monitored process — better error reporting
    # than raw spawn, and integrates with OTP tooling.
    Task.start(fn -> serve(client_socket) end)

    loop_acceptor(listen_socket)
  end

  # Parse → Route → Respond
  defp serve(client_socket) do
    conn = Ignite.Parser.parse(client_socket)
    Logger.info("#{conn.method} #{conn.path}")

    conn = MyApp.Router.call(conn)

    response = Ignite.Controller.send_resp(conn)
    :gen_tcp.send(client_socket, response)
    :gen_tcp.close(client_socket)
  end
end

defmodule Ignite.Application do
  @moduledoc """
  The OTP Application for Ignite.

  This module starts the supervision tree. The supervisor watches
  the server process and restarts it if it crashes.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the server on port 4000, supervised
      {Ignite.Server, 4000}
    ]

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule Ignite.Reloader do
  @moduledoc """
  Hot code reloader for development.

  Watches `lib/` for file changes and recompiles them on the fly
  without restarting the server or dropping connections.

  This works because the BEAM VM supports hot code swapping — you can
  replace a module's code while processes are running.
  """

  use GenServer
  require Logger

  @check_interval 1_000

  def start_link(opts \\ []) do
    path = Keyword.get(opts, :path, "lib")
    GenServer.start_link(__MODULE__, path, name: __MODULE__)
  end

  @impl true
  def init(path) do
    state = %{
      path: path,
      mtimes: get_mtimes(path)
    }

    schedule_check()
    Logger.info("[Reloader] Watching #{path}/ for changes...")
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    new_mtimes = get_mtimes(state.path)

    if new_mtimes != state.mtimes do
      reload_changed(state.mtimes, new_mtimes)
    end

    schedule_check()
    {:noreply, %{state | mtimes: new_mtimes}}
  end

  # Scan lib/ for all .ex files and record their modification times.
  defp get_mtimes(path) do
    Path.join(path, "**/*.ex")
    |> Path.wildcard()
    |> Enum.into(%{}, fn file ->
      case File.stat(file) do
        {:ok, stat} -> {file, stat.mtime}
        _ -> {file, nil}
      end
    end)
  end

  # Find files that changed and recompile them.
  defp reload_changed(old_mtimes, new_mtimes) do
    Enum.each(new_mtimes, fn {file, mtime} ->
      old_mtime = Map.get(old_mtimes, file)

      if mtime != old_mtime do
        Logger.info("[Reloader] Recompiling: #{file}")

        try do
          Code.compile_file(file)
        rescue
          error ->
            Logger.error("[Reloader] Compile error in #{file}: #{Exception.message(error)}")
        end
      end
    end)
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end
end

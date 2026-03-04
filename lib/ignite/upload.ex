defmodule Ignite.Upload do
  @moduledoc """
  Represents an uploaded file.

  When a multipart form is submitted, file parts are streamed to disk
  and represented as `%Ignite.Upload{}` structs in `conn.params`.

  ## Fields

    - `:path` — path to the temp file on disk
    - `:filename` — original filename from the client
    - `:content_type` — MIME type from the client

  **Security note:** `:filename` and `:content_type` are client-controlled.
  Always validate file contents before trusting these values.
  """

  defstruct [:path, :filename, :content_type]

  @type t :: %__MODULE__{
          path: String.t(),
          filename: String.t(),
          content_type: String.t() | nil
        }

  @upload_dir "/tmp/ignite-uploads"

  @doc """
  Returns the base upload directory, creating it if needed.
  """
  def upload_dir do
    File.mkdir_p!(@upload_dir)
    @upload_dir
  end

  @doc """
  Generates a unique temp file path and creates the empty file.
  """
  def random_file(prefix \\ "upload") do
    dir = upload_dir()
    random = :rand.uniform(999_999_999) |> Integer.to_string()
    timestamp = System.system_time(:millisecond) |> Integer.to_string()
    filename = "#{prefix}-#{timestamp}-#{random}"
    path = Path.join(dir, filename)
    File.write!(path, "")
    {:ok, path}
  end

  @doc """
  Schedules cleanup of a temp file when the calling process exits.

  Spawns a lightweight process that monitors the caller. When the
  caller dies (request finished, WebSocket closed), the temp file
  is deleted automatically.
  """
  def schedule_cleanup(path) do
    parent = self()

    spawn(fn ->
      ref = Process.monitor(parent)

      receive do
        {:DOWN, ^ref, :process, ^parent, _reason} ->
          File.rm(path)
      end
    end)

    :ok
  end
end

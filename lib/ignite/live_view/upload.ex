defmodule Ignite.LiveView.Upload do
  @moduledoc """
  Configuration struct for a LiveView upload field.

  Each `allow_upload/3` call creates one of these, stored in
  `assigns.__uploads__[name]`.
  """

  defstruct [
    :name,
    :accept,
    :max_entries,
    :max_file_size,
    :chunk_size,
    :auto_upload,
    entries: [],
    errors: []
  ]
end

defmodule Ignite.LiveView.UploadEntry do
  @moduledoc """
  Represents a single file being uploaded within a LiveView upload.
  """

  defstruct [
    :ref,
    :upload_name,
    :client_name,
    :client_type,
    :client_size,
    :tmp_path,
    progress: 0,
    done?: false,
    valid?: true,
    errors: []
  ]
end

defmodule Ignite.LiveView.UploadHelpers do
  @moduledoc """
  Functions imported into LiveViews for managing file uploads.

  Upload state is stored in `assigns.__uploads__` as
  `%{name => %Upload{}}`. The handler coordinates between the
  client-side JS and these helpers.

  ## Lifecycle

  1. `allow_upload/3` — configure an upload field in `mount/2`
  2. Client selects files → handler calls `validate_entries/3`
  3. Client sends binary chunks → handler calls `receive_chunk/3`
  4. Client signals done → handler calls `mark_complete/3`
  5. `consume_uploaded_entries/3` — process completed uploads

  ## Example

      def mount(_params, _session) do
        assigns = allow_upload(%{}, :avatar,
          accept: ["image/*"],
          max_file_size: 5_000_000
        )
        {:ok, assigns}
      end

      def handle_event("save", _params, assigns) do
        {assigns, results} = consume_uploaded_entries(assigns, :avatar, fn entry ->
          dest = Path.join("uploads", entry.client_name)
          File.cp!(entry.tmp_path, dest)
          {:ok, dest}
        end)
        {:noreply, %{assigns | saved_files: results}}
      end
  """

  alias Ignite.LiveView.{Upload, UploadEntry}

  @doc """
  Configures an upload field in the LiveView assigns.

  ## Options

    - `:accept` — list of accepted types (e.g., `[".jpg", ".png", "image/*"]`)
    - `:max_entries` — max number of files (default: `1`)
    - `:max_file_size` — max size in bytes (default: `8_000_000`)
    - `:chunk_size` — bytes per chunk sent over WebSocket (default: `64_000`)
    - `:auto_upload` — start uploading immediately on file select (default: `false`)
  """
  def allow_upload(assigns, name, opts \\ []) do
    upload = %Upload{
      name: name,
      accept: Keyword.get(opts, :accept, []),
      max_entries: Keyword.get(opts, :max_entries, 1),
      max_file_size: Keyword.get(opts, :max_file_size, 8_000_000),
      chunk_size: Keyword.get(opts, :chunk_size, 64_000),
      auto_upload: Keyword.get(opts, :auto_upload, false)
    }

    uploads = Map.get(assigns, :__uploads__, %{})
    Map.put(assigns, :__uploads__, Map.put(uploads, name, upload))
  end

  @doc """
  Returns `{completed_entries, in_progress_entries}` for the given upload.
  """
  def uploaded_entries(assigns, name) do
    uploads = Map.get(assigns, :__uploads__, %{})

    case Map.get(uploads, name) do
      nil -> {[], []}
      upload ->
        {done, pending} = Enum.split_with(upload.entries, & &1.done?)
        {done, pending}
    end
  end

  @doc """
  Processes completed uploads.

  The callback receives an `%UploadEntry{}` for each completed entry
  and should return `{:ok, value}`. The temp file is deleted after
  the callback returns `{:ok, _}`.

  Returns `{updated_assigns, results}`.
  """
  def consume_uploaded_entries(assigns, name, callback) do
    uploads = Map.get(assigns, :__uploads__, %{})

    upload =
      Map.get(uploads, name) ||
        raise ArgumentError, "upload #{inspect(name)} not configured"

    {completed, remaining} = Enum.split_with(upload.entries, & &1.done?)

    {results, kept} =
      Enum.reduce(completed, {[], []}, fn entry, {results_acc, kept_acc} ->
        case callback.(entry) do
          {:ok, value} ->
            if entry.tmp_path, do: File.rm(entry.tmp_path)
            {[value | results_acc], kept_acc}

          {:postpone, _} ->
            {results_acc, [entry | kept_acc]}
        end
      end)

    updated_upload = %{upload | entries: remaining ++ Enum.reverse(kept)}
    updated_uploads = Map.put(uploads, name, updated_upload)
    {Map.put(assigns, :__uploads__, updated_uploads), Enum.reverse(results)}
  end

  @doc """
  Cancels a specific upload entry by ref, cleaning up its temp file.
  """
  def cancel_upload(assigns, name, ref) do
    uploads = Map.get(assigns, :__uploads__, %{})

    upload =
      Map.get(uploads, name) ||
        raise ArgumentError, "upload #{inspect(name)} not configured"

    {cancelled, remaining} = Enum.split_with(upload.entries, &(&1.ref == ref))

    Enum.each(cancelled, fn entry ->
      if entry.tmp_path, do: File.rm(entry.tmp_path)
    end)

    updated = %{upload | entries: remaining}
    Map.put(assigns, :__uploads__, Map.put(uploads, name, updated))
  end

  @doc """
  Generates HTML for a file input connected to this upload.

  The `ignite-upload` attribute tells the JS client to handle
  file selection and chunked upload for this field.
  """
  def live_file_input(assigns, name) do
    uploads = Map.get(assigns, :__uploads__, %{})

    upload =
      Map.get(uploads, name) ||
        raise ArgumentError, "upload #{inspect(name)} not configured"

    accept_attr =
      if upload.accept != [],
        do: ~s( accept="#{Enum.join(upload.accept, ",")}"),
        else: ""

    multiple_attr = if upload.max_entries > 1, do: " multiple", else: ""
    auto_attr = if upload.auto_upload, do: ~s( data-auto-upload="true"), else: ""

    ~s(<input type="file" ignite-upload="#{name}"#{accept_attr}#{multiple_attr}#{auto_attr}) <>
      ~s( data-chunk-size="#{upload.chunk_size}") <>
      ~s( data-max-file-size="#{upload.max_file_size}") <>
      ~s( data-max-entries="#{upload.max_entries}" />)
  end

  # --- Handler-facing functions (called by Ignite.LiveView.Handler) ---

  @doc """
  Called by the handler when the client sends file metadata.
  Validates entries against the upload configuration.
  """
  def validate_entries(assigns, name, client_entries) do
    uploads = Map.get(assigns, :__uploads__, %{})

    upload =
      Map.get(uploads, name) ||
        raise ArgumentError, "upload #{inspect(name)} not configured"

    entries =
      Enum.map(client_entries, fn entry_data ->
        entry = %UploadEntry{
          ref: entry_data["ref"],
          upload_name: name,
          client_name: entry_data["name"],
          client_type: entry_data["type"] || "",
          client_size: entry_data["size"] || 0,
          progress: 0,
          done?: false,
          valid?: true
        }

        errors = []

        errors =
          if entry.client_size > upload.max_file_size,
            do: ["file too large (max #{div(upload.max_file_size, 1_000_000)}MB)" | errors],
            else: errors

        errors =
          if upload.accept != [] and
               not type_allowed?(entry.client_type, entry.client_name, upload.accept),
             do: ["file type not accepted" | errors],
             else: errors

        %{entry | valid?: errors == [], errors: errors}
      end)

    entries =
      if length(entries) > upload.max_entries do
        Enum.map(entries, fn e ->
          %{e | valid?: false, errors: ["too many files (max #{upload.max_entries})" | e.errors]}
        end)
      else
        entries
      end

    upload_errors = Enum.flat_map(entries, & &1.errors) |> Enum.uniq()
    updated = %{upload | entries: entries, errors: upload_errors}
    Map.put(assigns, :__uploads__, Map.put(uploads, name, updated))
  end

  @doc """
  Called by the handler when a binary chunk arrives.
  Appends data to the temp file and updates progress.
  """
  def receive_chunk(assigns, ref, chunk_data) do
    uploads = Map.get(assigns, :__uploads__, %{})
    {upload_name, upload, entry_index} = find_entry_by_ref(uploads, ref)
    entry = Enum.at(upload.entries, entry_index)

    # Create temp file on first chunk
    entry =
      if entry.tmp_path == nil do
        {:ok, path} = Ignite.Upload.random_file("lv-upload")
        Ignite.Upload.schedule_cleanup(path)
        %{entry | tmp_path: path}
      else
        entry
      end

    # Append chunk to file
    File.write!(entry.tmp_path, chunk_data, [:append, :binary, :raw])

    # Update progress
    bytes_received = File.stat!(entry.tmp_path).size
    progress = min(100, div(bytes_received * 100, max(entry.client_size, 1)))
    entry = %{entry | progress: progress}

    updated_entries = List.replace_at(upload.entries, entry_index, entry)
    updated_upload = %{upload | entries: updated_entries}
    updated_uploads = Map.put(uploads, upload_name, updated_upload)
    Map.put(assigns, :__uploads__, updated_uploads)
  end

  @doc """
  Called by the handler when the client signals upload complete for a ref.
  """
  def mark_complete(assigns, name, ref) do
    uploads = Map.get(assigns, :__uploads__, %{})
    upload = Map.get(uploads, name)

    updated_entries =
      Enum.map(upload.entries, fn entry ->
        if entry.ref == ref, do: %{entry | done?: true, progress: 100}, else: entry
      end)

    updated_upload = %{upload | entries: updated_entries}
    Map.put(assigns, :__uploads__, Map.put(uploads, name, updated_upload))
  end

  @doc """
  Builds the upload config payload to send to the client after validation.
  Returns nil if no uploads are configured.
  """
  def build_upload_config(assigns, upload_name) do
    uploads = Map.get(assigns, :__uploads__, %{})

    case Map.get(uploads, upload_name) do
      nil ->
        nil

      upload ->
        %{
          "name" => to_string(upload_name),
          "chunk_size" => upload.chunk_size,
          "max_file_size" => upload.max_file_size,
          "max_entries" => upload.max_entries,
          "auto_upload" => upload.auto_upload,
          "entries" =>
            Enum.map(upload.entries, fn e ->
              %{"ref" => e.ref, "valid" => e.valid?, "errors" => e.errors}
            end)
        }
    end
  end

  # --- Private helpers ---

  defp type_allowed?(client_type, client_name, accept_list) do
    Enum.any?(accept_list, fn pattern ->
      cond do
        String.starts_with?(pattern, ".") ->
          String.ends_with?(String.downcase(client_name), String.downcase(pattern))

        String.ends_with?(pattern, "/*") ->
          [category | _] = String.split(pattern, "/")
          String.starts_with?(client_type, category <> "/")

        true ->
          client_type == pattern
      end
    end)
  end

  defp find_entry_by_ref(uploads, ref) do
    Enum.find_value(uploads, fn {name, upload} ->
      case Enum.find_index(upload.entries, &(&1.ref == ref)) do
        nil -> nil
        idx -> {name, upload, idx}
      end
    end) || raise ArgumentError, "upload entry with ref #{inspect(ref)} not found"
  end
end

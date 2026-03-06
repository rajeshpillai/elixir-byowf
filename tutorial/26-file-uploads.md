# Step 26: File Uploads

## What We're Building

File upload support for Ignite, implemented in two parts:
- **Part A**: Traditional multipart HTTP POST for controller routes
- **Part B**: LiveView uploads over WebSocket with chunked binary frames and real-time progress

## The Problem

Ignite's body parser only handles `application/x-www-form-urlencoded` and `application/json`. A browser form with `enctype="multipart/form-data"` sends a completely different format — binary boundaries separating parts — that our parser can't read.

For LiveView, the problem is worse: the WebSocket connection only speaks JSON text frames. Files are binary data that can't be meaningfully JSON-encoded without massive overhead (Base64 doubles the size).

## Part A: Multipart HTTP POST

### How Multipart Works

When a browser submits `<form enctype="multipart/form-data">`, it sends:

```
POST /upload HTTP/1.1
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="description"

My photo
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="file"; filename="photo.jpg"
Content-Type: image/jpeg

<binary file data>
------WebKitFormBoundary7MA4YWxkTrZu0gW--
```

Each "part" is separated by a boundary string. Parts can be regular fields (just a value) or files (with a filename and binary content).

### Cowboy's Multipart API

Instead of parsing multipart ourselves, we use Cowboy's streaming API.

**Update `lib/ignite/adapters/cowboy.ex`** — add multipart parsing to handle `multipart/form-data` requests. In the existing body-reading code, detect `multipart/form-data` and branch to a new parser:

```elixir
content_type = :cowboy_req.header("content-type", req, "")

if String.starts_with?(content_type, "multipart/form-data") do
  read_multipart(req, %{})
else
  {:ok, body, req} = :cowboy_req.read_body(req)
  {parse_body(body, content_type), req}
end
```

Then add the multipart functions:

```elixir
# Loops through all parts of a multipart/form-data request.
# File parts are streamed to disk as %Ignite.Upload{} structs.
# Regular fields are stored as strings.
defp read_multipart(req, params) do
  case :cowboy_req.read_part(req) do
    {:ok, headers, req} ->
      {name, filename} = parse_disposition(headers)

      if filename do
        # File part — stream to temp file
        {:ok, tmp_path} = Ignite.Upload.random_file("multipart")
        Ignite.Upload.schedule_cleanup(tmp_path)
        {:ok, file} = File.open(tmp_path, [:write, :binary, :raw])
        {:ok, req} = read_part_body_to_file(req, file)
        File.close(file)

        upload_content_type =
          case Map.get(headers, "content-type") do
            nil -> "application/octet-stream"
            ct -> ct
          end

        upload = %Ignite.Upload{
          path: tmp_path,
          filename: filename,
          content_type: upload_content_type
        }

        read_multipart(req, Map.put(params, name, upload))
      else
        # Regular field — read body as string
        {:ok, body, req} = :cowboy_req.read_part_body(req)
        read_multipart(req, Map.put(params, name, body))
      end

    {:done, req} ->
      {params, req}
  end
end

# Streams part body chunks to a file handle.
# Cowboy returns {:more, data, req} for large bodies.
defp read_part_body_to_file(req, file) do
  case :cowboy_req.read_part_body(req) do
    {:ok, data, req} ->
      IO.binwrite(file, data)
      {:ok, req}

    {:more, data, req} ->
      IO.binwrite(file, data)
      read_part_body_to_file(req, file)
  end
end

# Extracts "name" and "filename" from the content-disposition header.
defp parse_disposition(headers) do
  case Map.get(headers, "content-disposition") do
    nil ->
      {nil, nil}

    disposition ->
      name = extract_header_param(disposition, "name")
      filename = extract_header_param(disposition, "filename")
      {name, filename}
  end
end

defp extract_header_param(header, param_name) do
  header
  |> String.split(";")
  |> Enum.find_value(fn part ->
    trimmed = String.trim(part)

    case String.split(trimmed, "=", parts: 2) do
      [^param_name, value] -> String.trim(value, "\"")
      _ -> nil
    end
  end)
end
```

The `read_part`/`read_part_body` loop reads one part at a time. For large file bodies, Cowboy returns `{:more, data, req}` — the recursive `read_part_body_to_file/2` keeps writing chunks until `{:ok, data, req}` signals the end. No data accumulates in memory.

### The Upload Struct

**Create `lib/ignite/upload.ex`:**

```elixir
defmodule Ignite.Upload do
  defstruct [:path, :filename, :content_type]

  @type t :: %__MODULE__{
          path: String.t(),
          filename: String.t(),
          content_type: String.t() | nil
        }

  @upload_dir "/tmp/ignite-uploads"

  @doc "Returns the base upload directory, creating it if needed."
  def upload_dir do
    File.mkdir_p!(@upload_dir)
    @upload_dir
  end

  @doc "Generates a unique temp file path and creates the empty file."
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
```

When a file part is found, we:
1. Create a temp file in `/tmp/ignite-uploads/`
2. Stream the body chunks to disk
3. Store an `%Ignite.Upload{}` in `conn.params`

```elixir
# In a controller:
def upload(conn) do
  %Ignite.Upload{} = upload = conn.params["file"]
  size = File.stat!(upload.path).size
  text(conn, "Uploaded #{upload.filename}: #{size} bytes")
end
```

When the Cowboy handler process exits (after sending the response), the monitor fires and the temp file is deleted. No manual cleanup needed.

### Testing Part A

```bash
# Upload a file
curl -F "file=@README.md" -F "description=test" http://localhost:4000/upload

# Or visit http://localhost:4000/upload in the browser
```

## Part B: LiveView Uploads

### The Architecture

Files are sent as **binary chunks over the existing WebSocket connection**. The protocol has 5 steps:

1. User selects files → JS sends metadata as JSON text frame
2. Server validates entries → sends config back (chunk size, validity)
3. JS chunks files → sends binary WebSocket frames
4. Server appends chunks to temp file → sends progress updates
5. JS signals completion → LiveView consumes the uploaded files

### Upload Configuration

**Create `lib/ignite/live_view/upload.ex`** — this file defines the structs and all helper functions. The key functions that LiveViews call directly are `allow_upload/3` and `consume_uploaded_entries/3`, defined in `Ignite.LiveView.UploadHelpers`:

```elixir
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
```

```elixir
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
```

In `mount/2`, configure what uploads are allowed:

```elixir
def mount(_params, _session) do
  assigns = allow_upload(%{}, :photos,
    accept: ["image/*", ".pdf"],
    max_entries: 5,
    max_file_size: 5_000_000,  # 5MB
    auto_upload: true           # start uploading immediately on file select
  )
  {:ok, assigns}
end
```

Options:
- `:accept` — file type restrictions (MIME types, extensions, wildcards)
- `:max_entries` — maximum number of files
- `:max_file_size` — per-file size limit in bytes
- `:chunk_size` — bytes per WebSocket frame (default: 64KB)
- `:auto_upload` — start uploading as soon as files are selected

### The Upload Structs

These structs are defined at the top of `lib/ignite/live_view/upload.ex`:

```elixir
defmodule Ignite.LiveView.Upload do
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
```

At runtime, an entry looks like:

```elixir
%Ignite.LiveView.UploadEntry{
  ref: "0",               # unique reference from the client
  client_name: "photo.jpg",
  client_type: "image/jpeg",
  client_size: 204800,
  tmp_path: "/tmp/ignite-uploads/lv-upload-...",
  progress: 75,           # 0-100
  done?: false,
  valid?: true,
  errors: []
}
```

### Wire Protocol

**Step 1: File selection → validation (text frame, client → server)**
```json
{
  "event": "__upload_validate__",
  "params": {
    "name": "photos",
    "entries": [
      {"ref": "0", "name": "photo.jpg", "type": "image/jpeg", "size": 204800}
    ]
  }
}
```

**Step 2: Validation response (text frame, server → client)**
```json
{
  "d": {"0": "1 file selected"},
  "upload": {
    "name": "photos",
    "chunk_size": 64000,
    "auto_upload": true,
    "entries": [{"ref": "0", "valid": true, "errors": []}]
  }
}
```

The `upload` field is only present after validation events — it tells the JS client the chunk size and which entries are valid for upload.

**Step 3: Chunk transfer (binary frame, client → server)**
```
[2 bytes: ref_len][ref_len bytes: ref_string][rest: chunk_data]
```

Example for ref "0" with 64KB of data:
- Byte 0-1: `0x0001` (ref is 1 byte long)
- Byte 2: `0x30` (ASCII "0")
- Byte 3+: 64KB of file data

**Step 4: Progress update (text frame, server → client)**
```json
{"d": {"2": "75%"}}
```

Progress is a normal dynamic value — the `render/1` function includes it, and the diffing engine sends only the changed value.

**Step 5: Upload complete (text frame, client → server)**
```json
{
  "event": "__upload_complete__",
  "params": {"name": "photos", "ref": "0"}
}
```

### Template Integration

The `live_file_input/2` helper generates a configured file input:

```elixir
def render(assigns) do
  # ...
  """
  <div ignite-drop-target="photos">
    #{live_file_input(assigns, :photos)}
  </div>
  """
end
```

This generates:
```html
<input type="file" ignite-upload="photos"
       accept="image/*,.pdf" multiple
       data-auto-upload="true"
       data-chunk-size="64000"
       data-max-file-size="5000000"
       data-max-entries="5" />
```

The JS client reads `ignite-upload` to attach event listeners and reads `data-*` attributes for configuration.

### Consuming Uploads

After all files are uploaded (`done?: true`), consume them in a `handle_event`:

```elixir
def handle_event("save", _params, assigns) do
  {assigns, results} = consume_uploaded_entries(assigns, :photos, fn entry ->
    # entry.tmp_path contains the uploaded file
    # entry.client_name is the original filename
    dest = Path.join("uploads", entry.client_name)
    File.cp!(entry.tmp_path, dest)
    {:ok, %{name: entry.client_name, path: dest}}
  end)

  {:noreply, %{assigns | saved_files: results}}
end
```

`consume_uploaded_entries/3` calls your function for each completed entry, deletes the temp file after `{:ok, _}`, and removes the entry from the upload.

### Frontend Changes

The JavaScript client adds three capabilities:

1. **File input handler** — on `change`, sends metadata via `__upload_validate__`
2. **Binary chunker** — reads files in 64KB slices using `FileReader`, sends as binary WebSocket frames with a ref prefix
3. **Drag-and-drop** — `ignite-drop-target="name"` attribute enables drop zones with visual feedback

The chunker uses `setTimeout(sendNextChunk, 10)` between chunks to avoid flooding the WebSocket. Since WebSocket guarantees message ordering, chunks always arrive in the correct order.

## Using It

### HTTP Upload (`/upload`)

**Create `lib/my_app/controllers/upload_controller.ex`:**

```elixir
defmodule MyApp.UploadController do
  import Ignite.Controller

  def upload_form(conn) do
    html(conn, """
    <h1>File Upload</h1>
    <form action="/upload" method="post" enctype="multipart/form-data"
          style="max-width:500px;margin:20px auto;text-align:left;">
      #{csrf_token_tag(conn)}
      <div style="margin-bottom:15px;">
        <label style="display:block;margin-bottom:4px;font-weight:bold;">Select a file</label>
        <input type="file" name="file" required />
      </div>
      <div style="margin-bottom:15px;">
        <label style="display:block;margin-bottom:4px;font-weight:bold;">Description</label>
        <input type="text" name="description" placeholder="Optional description"
               style="width:100%;padding:8px;box-sizing:border-box;" />
      </div>
      <button type="submit" style="padding:10px 20px;background:#3498db;color:white;
              border:none;border-radius:4px;cursor:pointer;">Upload</button>
    </form>
    """)
  end

  def upload(conn) do
    case conn.params["file"] do
      %Ignite.Upload{} = upload ->
        size = File.stat!(upload.path).size
        File.mkdir_p!("uploads")
        safe_name = sanitize_filename(upload.filename)
        dest = Path.join("uploads", safe_name)
        File.cp!(upload.path, dest)

        html(conn, """
        <h1>Upload Successful</h1>
        <p><strong>#{escape(upload.filename)}</strong> — #{size} bytes
           (#{escape(upload.content_type)})</p>
        <p><a href="/uploads/#{safe_name}" target="_blank">View File</a></p>
        <p><a href="/upload">Upload another</a> &middot; <a href="/">Home</a></p>
        """)

      _ ->
        text(conn, "No file uploaded", 400)
    end
  end

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape(nil), do: ""

  defp sanitize_filename(name) do
    timestamp = System.system_time(:millisecond) |> Integer.to_string()
    safe = name |> Path.basename() |> String.replace(~r/[^\w.\-]/, "_")
    "#{timestamp}-#{safe}"
  end
end
```

### LiveView Upload (`/upload-demo`)

**Create `lib/my_app/live/upload_demo_live.ex`:**

```elixir
defmodule MyApp.UploadDemoLive do
  use Ignite.LiveView

  @impl true
  def mount(_params, _session) do
    assigns = %{uploaded_files: [], message: nil}

    assigns =
      allow_upload(assigns, :photos,
        accept: ["image/*", ".pdf", ".txt", ".md"],
        max_entries: 5,
        max_file_size: 5_000_000,
        auto_upload: true
      )

    {:ok, assigns}
  end

  @impl true
  def handle_event("validate", _params, assigns) do
    {:noreply, assigns}
  end

  @impl true
  def handle_event("save", _params, assigns) do
    File.mkdir_p!("uploads")

    {assigns, results} =
      consume_uploaded_entries(assigns, :photos, fn entry ->
        safe_name = sanitize_filename(entry.client_name)
        dest = Path.join("uploads", safe_name)
        File.cp!(entry.tmp_path, dest)

        {:ok, %{name: entry.client_name, size: entry.client_size,
                 type: entry.client_type, url: "/uploads/#{safe_name}"}}
      end)

    message = "#{length(results)} file(s) uploaded successfully!"
    {:noreply, %{assigns | uploaded_files: assigns.uploaded_files ++ results, message: message}}
  end

  @impl true
  def handle_event("clear", _params, assigns) do
    assigns =
      allow_upload(assigns, :photos,
        accept: ["image/*", ".pdf", ".txt", ".md"],
        max_entries: 5, max_file_size: 5_000_000, auto_upload: true
      )

    {:noreply, %{assigns | uploaded_files: [], message: nil}}
  end

  @impl true
  def render(assigns) do
    uploads = Map.get(assigns, :__uploads__, %{})
    photo_upload = Map.get(uploads, :photos, %{entries: [], errors: []})

    entries_html =
      photo_upload.entries
      |> Enum.map(fn entry ->
        bar_color = if entry.done?, do: "#27ae60", else: "#3498db"
        status = if entry.done?, do: "Done", else: "#{entry.progress}%"

        """
        <div style="display:flex;align-items:center;gap:12px;padding:8px;
                    background:#f8f9fa;border-radius:6px;margin:4px 0;">
          <span style="flex:1;">#{escape(entry.client_name)}</span>
          <span style="color:#888;font-size:12px;">#{format_size(entry.client_size)}</span>
          <div style="width:100px;height:8px;background:#eee;border-radius:4px;overflow:hidden;">
            <div style="width:#{entry.progress}%;height:100%;background:#{bar_color};
                        transition:width 0.3s;"></div>
          </div>
          <span style="font-size:12px;min-width:40px;">#{status}</span>
        </div>
        """
      end)
      |> Enum.join("")

    all_done = Enum.all?(photo_upload.entries, & &1.done?)
    has_entries = photo_upload.entries != []
    save_disabled = if has_entries and all_done, do: "", else: " disabled"

    """
    <div style="max-width:600px;margin:0 auto;">
      <h1>LiveView Upload Demo</h1>
      <form ignite-submit="save">
        <div ignite-drop-target="photos"
             style="border:2px dashed #ccc;border-radius:8px;padding:40px;text-align:center;">
          <p>Drag &amp; drop files here, or click to select</p>
          #{live_file_input(assigns, :photos)}
        </div>
        #{entries_html}
        <button type="submit"#{save_disabled}>Save Files</button>
        <button type="button" ignite-click="clear">Clear</button>
      </form>
    </div>
    """
  end

  defp escape(text) when is_binary(text) do
    text |> String.replace("&", "&amp;") |> String.replace("<", "&lt;")
        |> String.replace(">", "&gt;")
  end

  defp escape(nil), do: ""

  defp sanitize_filename(name) do
    timestamp = System.system_time(:millisecond) |> Integer.to_string()
    safe = name |> Path.basename() |> String.replace(~r/[^\w.\-]/, "_")
    "#{timestamp}-#{safe}"
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
```

### Router Routes

**Update `lib/my_app/router.ex`:**

```elixir
get "/upload", to: MyApp.UploadController, action: :upload_form
post "/upload", to: MyApp.UploadController, action: :upload
get "/upload-demo", to: MyApp.WelcomeController, action: :upload_demo
```

The `upload_demo` action in `WelcomeController` serves the LiveView-connected page (same pattern as the counter and streams demos).

### Handler: Binary Frame Handling

**Update `lib/ignite/live_view/handler.ex`** — add upload protocol events to the text frame handler and a new binary frame handler:

```elixir
# In websocket_handle({:text, json}, state), add before the generic event handler:

{:ok, %{"event" => "__upload_validate__", "params" => %{"name" => name, "entries" => entries}}} ->
  upload_name = String.to_atom(name)
  new_assigns = Ignite.LiveView.UploadHelpers.validate_entries(state.assigns, upload_name, entries)

  # Let the view handle validation if it defines handle_event("validate", ...)
  new_assigns =
    if function_exported?(state.view, :handle_event, 3) do
      case apply(state.view, :handle_event, ["validate", %{"name" => name}, new_assigns]) do
        {:noreply, a} -> a
        _ -> new_assigns
      end
    else
      new_assigns
    end

  send_render_update_with_upload_config(state, new_assigns, upload_name)

{:ok, %{"event" => "__upload_complete__", "params" => %{"name" => name, "ref" => ref}}} ->
  upload_name = String.to_atom(name)
  new_assigns = Ignite.LiveView.UploadHelpers.mark_complete(state.assigns, upload_name, ref)
  send_render_update(state, new_assigns)
```

```elixir
# Binary frames carry file upload chunks
# Protocol: [2 bytes: ref_len][ref_len bytes: ref_string][rest: chunk_data]
@impl true
def websocket_handle({:binary, data}, state) do
  case data do
    <<ref_len::16, ref::binary-size(ref_len), chunk_data::binary>> ->
      new_assigns = Ignite.LiveView.UploadHelpers.receive_chunk(state.assigns, ref, chunk_data)
      send_render_update(state, new_assigns)

    _ ->
      Logger.warning("[LiveView] Malformed binary upload frame")
      {:ok, state}
  end
end
```

The `send_render_update_with_upload_config/3` helper is like `send_render_update/2` but also includes the upload config in the JSON payload so the JS client knows the chunk size and which entries are valid:

```elixir
defp send_render_update_with_upload_config(state, assigns, upload_name) do
  # ... render + diff as usual ...
  upload_config = Ignite.LiveView.UploadHelpers.build_upload_config(assigns, upload_name)
  payload_map = %{d: diff_payload}
  payload_map = if upload_config, do: Map.put(payload_map, :upload, upload_config), else: payload_map
  payload = Jason.encode!(payload_map)
  {:reply, {:text, payload}, new_state}
end
```

See `lib/ignite/live_view/handler.ex` for the complete implementation including component routing and redirect handling.

## Testing

### Part A: HTTP Upload

```bash
# Upload a file
curl -F "file=@README.md" http://localhost:4000/upload

# Upload with description
curl -F "file=@photo.jpg" -F "description=My photo" http://localhost:4000/upload
```

### Part B: LiveView Upload

1. Visit `http://localhost:4000/upload-demo`
2. Select files or drag-and-drop onto the drop zone
3. Watch progress bars fill in real-time
4. Click "Save Files" to consume the uploads
5. Open DevTools → Network → WS to see the binary frames

**What you'll see in the WS tab:**
- Text frame: `__upload_validate__` with file metadata
- Text frame: server response with `upload` config
- Binary frames: file chunks (one per 64KB)
- Text frame: `__upload_complete__` per file
- Text frames: progress diff updates (`{"d": {...}}`)

## Key Elixir Concepts

- **Streaming with recursion**: The `read_part_body_to_file` function uses recursion to handle Cowboy's `{:more, data, req}` continuation. Each call writes one chunk and recurses — no data accumulates in memory.

- **Process monitoring for cleanup**: Instead of explicit cleanup code, we use `Process.monitor/1` to watch the request process. When it dies, the temp file is automatically deleted. This is the Erlang "let it crash" philosophy applied to resource management.

- **Binary pattern matching**: The WebSocket handler uses Elixir's binary pattern matching to parse upload frames:
  ```elixir
  <<ref_len::16, ref::binary-size(ref_len), chunk_data::binary>> = data
  ```
  This extracts a 2-byte integer, a variable-length string, and the remaining bytes — all in one expression.

- **State accumulation in assigns**: Like Streams, upload state lives in `assigns.__uploads__`. Each `receive_chunk` call returns new assigns with updated progress. The handler coordinates between binary frames and render cycles.

## File Checklist

| File | Status |
|------|--------|
| `lib/ignite/upload.ex` | **New** — `%Ignite.Upload{}` struct for HTTP uploads |
| `lib/ignite/live_view/upload.ex` | **New** — `%Upload{}` and `%UploadEntry{}` structs for LiveView uploads |
| `lib/my_app/controllers/upload_controller.ex` | **New** — HTTP upload form and handler |
| `lib/my_app/live/upload_demo_live.ex` | **New** — LiveView upload demo with progress |
| `uploads/.gitkeep` | **New** — directory for saved uploads |
| `lib/ignite/adapters/cowboy.ex` | **Modified** — multipart form-data parsing |
| `lib/ignite/application.ex` | **Modified** — register upload routes |
| `lib/ignite/live_view.ex` | **Modified** — added `allow_upload`, `consume_uploaded_entries` |
| `lib/ignite/live_view/handler.ex` | **Modified** — handle binary upload frames and upload events |
| `lib/my_app/router.ex` | **Modified** — added `/upload` and `/upload-demo` routes |
| `lib/my_app/controllers/welcome_controller.ex` | **Modified** — added upload links |
| `assets/ignite.js` | **Modified** — file input handling, chunked upload, drag-and-drop |

## How Phoenix Does It

Phoenix LiveView's upload system is more sophisticated:

- **`allow_upload/3`** works on the socket struct, not plain assigns
- **Change tracking** means only affected template expressions re-evaluate on progress updates
- **External uploads** can go directly to S3/cloud storage, bypassing the server
- **`stream_configure/3`** allows custom writers for processing chunks in-flight
- **Presigned URLs** for direct cloud uploads without server bandwidth
- **Progress callbacks** via `handle_progress/3` for custom progress tracking
- **File validation** can inspect actual file content (magic bytes), not just MIME type

Our implementation covers the core: chunked binary transfer, progress tracking, validation, drag-and-drop, and temp file management — enough for medium-scale apps.

---

[← Previous: Step 25 - LiveView Streams](25-streams.md) | [Next: Step 27 - Path Helpers & Resource Routes →](27-path-helpers.md)

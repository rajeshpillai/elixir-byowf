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

**Update `lib/ignite/adapters/cowboy.ex`** — add multipart parsing to handle `multipart/form-data` requests:

```elixir
# Read the next part's headers
{:ok, headers, req} = :cowboy_req.read_part(req)
# headers = %{"content-disposition" => "form-data; name=\"file\"; filename=\"photo.jpg\"", ...}

# Read the part's body (streaming for large files)
{:ok, body, req} = :cowboy_req.read_part_body(req)
# or {:more, partial_body, req} for large bodies — call again to get the rest
```

The `read_part`/`read_part_body` loop reads one part at a time without loading the entire request into memory.

### The Upload Struct

**Create `lib/ignite/upload.ex`:**

```elixir
defmodule Ignite.Upload do
  defstruct [:path, :filename, :content_type]
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

### Temp File Cleanup

Each temp file gets an automatic cleanup process:

```elixir
def schedule_cleanup(path) do
  parent = self()
  spawn(fn ->
    ref = Process.monitor(parent)
    receive do
      {:DOWN, ^ref, :process, ^parent, _reason} ->
        File.rm(path)
    end
  end)
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

**Update `lib/ignite/live_view.ex`** — add the `allow_upload` and `consume_uploaded_entries` functions.

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

**Create `lib/ignite/live_view/upload.ex`:**

```elixir
# Stored in assigns.__uploads__[name]
%Ignite.LiveView.Upload{
  name: :photos,
  accept: ["image/*", ".pdf"],
  max_entries: 5,
  max_file_size: 5_000_000,
  chunk_size: 64_000,
  auto_upload: true,
  entries: [%UploadEntry{}, ...],
  errors: []
}

# Each file being uploaded
%Ignite.LiveView.UploadEntry{
  ref: "0",               # unique reference
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
def upload_form(conn) do
  html(conn, """
  <form action="/upload" method="post" enctype="multipart/form-data">
    <input type="file" name="file" />
    <button type="submit">Upload</button>
  </form>
  """)
end

def upload(conn) do
  upload = conn.params["file"]
  text(conn, "Got #{upload.filename}, #{File.stat!(upload.path).size} bytes")
end
```

### LiveView Upload (`/upload-demo`)

**Create `lib/my_app/live/upload_demo_live.ex`:**

```elixir
defmodule MyApp.UploadDemoLive do
  use Ignite.LiveView

  def mount(_params, _session) do
    assigns = allow_upload(%{uploaded_files: []}, :photos,
      accept: ["image/*"], max_entries: 5, max_file_size: 5_000_000,
      auto_upload: true
    )
    {:ok, assigns}
  end

  def handle_event("save", _params, assigns) do
    {assigns, results} = consume_uploaded_entries(assigns, :photos, fn entry ->
      {:ok, %{name: entry.client_name, size: entry.client_size}}
    end)
    {:noreply, %{assigns | uploaded_files: results}}
  end

  def render(assigns) do
    uploads = Map.get(assigns, :__uploads__, %{})
    photo_upload = Map.get(uploads, :photos, %{entries: []})
    # ... render entries with progress bars, drop zone, etc.
  end
end
```

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

defmodule MyApp.UploadDemoLive do
  @moduledoc """
  Demo LiveView showcasing file uploads over WebSocket.

  Files are chunked on the client (64KB default), sent as binary
  WebSocket frames, and streamed to temp files on the server.
  Progress bars update in real-time via LiveView re-render.
  """

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
        # Copy to persistent uploads/ directory so files can be viewed
        safe_name = sanitize_filename(entry.client_name)
        dest = Path.join("uploads", safe_name)
        File.cp!(entry.tmp_path, dest)

        {:ok,
         %{
           name: entry.client_name,
           size: entry.client_size,
           type: entry.client_type,
           url: "/uploads/#{safe_name}"
         }}
      end)

    message = "#{length(results)} file(s) uploaded successfully!"
    {:noreply, %{assigns | uploaded_files: assigns.uploaded_files ++ results, message: message}}
  end

  @impl true
  def handle_event("clear", _params, assigns) do
    assigns =
      allow_upload(assigns, :photos,
        accept: ["image/*", ".pdf", ".txt", ".md"],
        max_entries: 5,
        max_file_size: 5_000_000,
        auto_upload: true
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

        error_html =
          if entry.errors != [] do
            errs = Enum.map(entry.errors, &"<span style='color:#e74c3c;font-size:12px;'>#{&1}</span>") |> Enum.join(", ")
            "<div>#{errs}</div>"
          else
            ""
          end

        """
        <div style="display:flex;align-items:center;gap:12px;padding:8px;
                    background:#f8f9fa;border-radius:6px;margin:4px 0;">
          <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">
            #{escape(entry.client_name)}</span>
          <span style="color:#888;font-size:12px;">#{format_size(entry.client_size)}</span>
          <div style="width:100px;height:8px;background:#eee;border-radius:4px;overflow:hidden;">
            <div style="width:#{entry.progress}%;height:100%;background:#{bar_color};
                        transition:width 0.3s;"></div>
          </div>
          <span style="font-size:12px;min-width:40px;">#{status}</span>
        </div>
        #{error_html}
        """
      end)
      |> Enum.join("")

    errors_html =
      if photo_upload.errors != [] do
        errs =
          Enum.map(photo_upload.errors, &"<li style='color:#e74c3c;'>#{&1}</li>")
          |> Enum.join()

        "<ul style='text-align:left;list-style:none;padding:0;'>#{errs}</ul>"
      else
        ""
      end

    files_html =
      assigns.uploaded_files
      |> Enum.map(fn file ->
        "<li><a href=\"#{file.url}\" target=\"_blank\">#{escape(file.name)}</a> (#{file.type}, #{format_size(file.size)})</li>"
      end)
      |> Enum.join("")

    message_html =
      if assigns.message do
        "<div style='background:#d4edda;padding:12px;border-radius:6px;color:#155724;margin:12px 0;'>#{assigns.message}</div>"
      else
        ""
      end

    all_done = Enum.all?(photo_upload.entries, & &1.done?)
    has_entries = photo_upload.entries != []
    save_disabled = if has_entries and all_done, do: "", else: " disabled"

    """
    <div style="max-width:600px;margin:0 auto;">
      <h1>LiveView Upload Demo</h1>
      <p style="color:#888;">Files are chunked and sent as binary WebSocket frames with real-time progress.</p>

      #{message_html}

      <form ignite-submit="save" style="text-align:left;">
        <div ignite-drop-target="photos"
             style="border:2px dashed #ccc;border-radius:8px;padding:40px;
                    text-align:center;margin:16px 0;transition:all 0.2s;">
          <p style="color:#888;margin:0 0 12px 0;">Drag &amp; drop files here, or click to select</p>
          #{live_file_input(assigns, :photos)}
          <p style="color:#aaa;font-size:12px;margin:12px 0 0 0;">
            Images, PDFs, and text files &middot; max 5MB each &middot; up to 5 files</p>
        </div>

        #{errors_html}
        #{entries_html}

        <div style="margin-top:12px;">
          <button type="submit"#{save_disabled}
                  style="padding:10px 24px;background:#3498db;color:white;
                         border:none;border-radius:6px;cursor:pointer;">
            Save Files
          </button>
          <button type="button" ignite-click="clear"
                  style="padding:10px 24px;background:#e74c3c;color:white;
                         border:none;border-radius:6px;cursor:pointer;margin-left:8px;">
            Clear
          </button>
        </div>
      </form>

      #{if length(assigns.uploaded_files) > 0 do
        "<h2>Saved Files</h2><ul style='text-align:left;'>#{files_html}</ul>"
      else
        ""
      end}

      <div style="margin-top:24px;padding:16px;background:#f0fff4;border-radius:8px;text-align:left;">
        <strong>How it works:</strong>
        <ul style="margin:8px 0;padding-left:20px;">
          <li>Files are sent as <strong>binary chunks (64KB)</strong> over the WebSocket</li>
          <li>Each chunk is streamed to a temp file — no full file in memory</li>
          <li>Progress bars update in real-time via LiveView re-render</li>
          <li>Open DevTools &rarr; Network &rarr; WS to see binary frames</li>
          <li>Files are validated on the server (type + size) before uploading</li>
        </ul>
      </div>

      <div style="margin-top:20px;padding-top:16px;border-top:1px solid #eee;text-align:center;">
        <a href="/">Home</a> &middot;
        <a href="/upload">HTTP Upload</a> &middot;
        <a href="/counter" ignite-navigate="/counter">Counter</a> &middot;
        <a href="/streams" ignite-navigate="/streams">Streams</a>
      </div>
    </div>
    """
  end

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
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

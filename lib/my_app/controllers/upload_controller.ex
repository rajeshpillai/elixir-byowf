defmodule MyApp.UploadController do
  @moduledoc """
  Handles traditional multipart file uploads via HTTP POST.
  """

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
    <p style="margin-top:20px;text-align:center;">
      <a href="/upload-demo">Try LiveView uploads</a> &middot;
      <a href="/">Back to Home</a>
    </p>
    """)
  end

  def upload(conn) do
    case conn.params["file"] do
      %Ignite.Upload{} = upload ->
        size = File.stat!(upload.path).size

        # Copy to persistent uploads/ directory so the file can be viewed
        File.mkdir_p!("uploads")
        safe_name = sanitize_filename(upload.filename)
        dest = Path.join("uploads", safe_name)
        File.cp!(upload.path, dest)
        view_url = "/uploads/#{safe_name}"

        html(conn, """
        <h1>Upload Successful</h1>
        <table style="margin:20px auto;text-align:left;border-collapse:collapse;">
          <tr><td style="padding:6px 12px;"><strong>Filename:</strong></td>
              <td style="padding:6px 12px;">#{escape(upload.filename)}</td></tr>
          <tr><td style="padding:6px 12px;"><strong>Content-Type:</strong></td>
              <td style="padding:6px 12px;">#{escape(upload.content_type)}</td></tr>
          <tr><td style="padding:6px 12px;"><strong>Size:</strong></td>
              <td style="padding:6px 12px;">#{size} bytes</td></tr>
          <tr><td style="padding:6px 12px;"><strong>Description:</strong></td>
              <td style="padding:6px 12px;">#{escape(conn.params["description"] || "(none)")}</td></tr>
        </table>
        <p style="margin-top:20px;text-align:center;">
          <a href="#{view_url}" target="_blank" style="padding:8px 16px;background:#27ae60;color:white;
             text-decoration:none;border-radius:4px;">View File</a>
        </p>
        <p style="margin-top:12px;text-align:center;">
          <a href="/upload">Upload another</a> &middot;
          <a href="/">Back to Home</a>
        </p>
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
    |> String.replace("\"", "&quot;")
  end

  defp escape(nil), do: ""

  defp sanitize_filename(name) do
    # Add timestamp prefix to avoid collisions, strip path traversal
    timestamp = System.system_time(:millisecond) |> Integer.to_string()
    safe = name |> Path.basename() |> String.replace(~r/[^\w.\-]/, "_")
    "#{timestamp}-#{safe}"
  end
end

defmodule Ignite.DebugPage do
  @moduledoc """
  Renders a rich debug error page in development.

  When a controller or plug raises an exception, the Cowboy adapter
  catches it and calls `render/3` to build an informative HTML page
  showing the exception, stacktrace, and request context.

  In production (`env: :prod` config), a generic error page is shown
  instead — no exception details, stacktrace, or request data are leaked.
  """

  @doc """
  Renders the error page HTML.

  In dev: shows exception type, message, formatted stacktrace with
  file:line, and request details (method, path, headers, params, session).

  In prod: shows a generic "Something went wrong" page.
  """
  def render(exception, stacktrace, conn) do
    if Application.get_env(:ignite, :env) == :prod do
      render_prod()
    else
      render_dev(exception, stacktrace, conn)
    end
  end

  # --- Production: generic error page ---

  defp render_prod do
    """
    <!DOCTYPE html>
    <html>
    <head><title>500 — Internal Server Error</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 600px; margin: 80px auto; text-align: center; color: #333; }
      h1 { color: #e74c3c; font-size: 2em; }
    </style>
    </head>
    <body>
      <h1>500 — Internal Server Error</h1>
      <p>Something went wrong. Please try again later.</p>
      <p><a href="/">Back to Home</a></p>
    </body>
    </html>
    """
  end

  # --- Development: rich debug page ---

  defp render_dev(exception, stacktrace, conn) do
    exception_type = exception.__struct__ |> inspect()
    message = Exception.message(exception) |> html_escape()
    trace_html = format_stacktrace(stacktrace)
    request_html = format_request(conn)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{exception_type} — Ignite Debug</title>
      <style>#{css()}</style>
    </head>
    <body>
      <header>
        <h1>#{html_escape(exception_type)}</h1>
        <pre class="message">#{message}</pre>
      </header>

      <nav>
        <button class="tab active" onclick="showTab('stacktrace')">Stacktrace</button>
        <button class="tab" onclick="showTab('request')">Request</button>
        <button class="tab" onclick="showTab('session')">Session</button>
      </nav>

      <section id="stacktrace" class="panel active">
        <table>
          <thead><tr><th>Module.function/arity</th><th>File</th></tr></thead>
          <tbody>#{trace_html}</tbody>
        </table>
      </section>

      <section id="request" class="panel">
        #{request_html}
      </section>

      <section id="session" class="panel">
        #{format_session(conn)}
      </section>

      <script>#{js()}</script>
    </body>
    </html>
    """
  end

  # --- Stacktrace formatting ---

  defp format_stacktrace(stacktrace) do
    Enum.map_join(stacktrace, "\n", &format_entry/1)
  end

  defp format_entry({mod, fun, arity, location}) do
    arity_val = if is_list(arity), do: length(arity), else: arity
    func = "#{inspect(mod)}.#{fun}/#{arity_val}"
    file = Keyword.get(location, :file, ~c"") |> to_string()
    line = Keyword.get(location, :line, "?")
    app_class = if app_frame?(file), do: "app", else: "dep"

    """
    <tr class="#{app_class}">
      <td>#{html_escape(func)}</td>
      <td>#{html_escape(file)}:#{line}</td>
    </tr>
    """
  end

  defp app_frame?(file) do
    String.starts_with?(file, "lib/my_app") or String.starts_with?(file, "lib/ignite")
  end

  # --- Request formatting ---

  defp format_request(nil) do
    "<p>Request context not available.</p>"
  end

  defp format_request(conn) do
    headers_html =
      conn.headers
      |> Enum.map_join("\n", fn {k, v} ->
        "<tr><td>#{html_escape(k)}</td><td>#{html_escape(v)}</td></tr>"
      end)

    params_html =
      if conn.params == %{} do
        "<p class=\"empty\">No parameters</p>"
      else
        rows =
          Enum.map_join(conn.params, "\n", fn {k, v} ->
            "<tr><td>#{html_escape(to_string(k))}</td><td>#{html_escape(inspect(v))}</td></tr>"
          end)

        "<table><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>#{rows}</tbody></table>"
      end

    """
    <h3>Request</h3>
    <table>
      <tbody>
        <tr><td><strong>Method</strong></td><td>#{html_escape(conn.method)}</td></tr>
        <tr><td><strong>Path</strong></td><td>#{html_escape(conn.path)}</td></tr>
      </tbody>
    </table>

    <h3>Parameters</h3>
    #{params_html}

    <h3>Headers</h3>
    <table>
      <thead><tr><th>Header</th><th>Value</th></tr></thead>
      <tbody>#{headers_html}</tbody>
    </table>
    """
  end

  # --- Session formatting ---

  defp format_session(nil), do: "<p>Session not available.</p>"

  defp format_session(conn) do
    if conn.session == %{} do
      "<p class=\"empty\">Empty session</p>"
    else
      rows =
        Enum.map_join(conn.session, "\n", fn {k, v} ->
          "<tr><td>#{html_escape(to_string(k))}</td><td>#{html_escape(inspect(v))}</td></tr>"
        end)

      """
      <table>
        <thead><tr><th>Key</th><th>Value</th></tr></thead>
        <tbody>#{rows}</tbody>
      </table>
      """
    end
  end

  # --- HTML escaping ---

  defp html_escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp html_escape(other), do: html_escape(inspect(other))

  # --- Inline CSS ---

  defp css do
    """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: system-ui, -apple-system, sans-serif; background: #f5f5f5; color: #333; }
    header { background: #e74c3c; color: #fff; padding: 24px 32px; }
    header h1 { font-size: 1.4em; margin-bottom: 12px; font-weight: 600; }
    header .message { background: rgba(0,0,0,0.2); padding: 12px 16px; border-radius: 6px;
                      font-size: 0.95em; white-space: pre-wrap; word-break: break-word;
                      font-family: 'SF Mono', Menlo, monospace; }
    nav { background: #fff; border-bottom: 2px solid #e0e0e0; padding: 0 32px; display: flex; gap: 0; }
    .tab { background: none; border: none; padding: 12px 20px; cursor: pointer;
           font-size: 0.9em; color: #666; border-bottom: 3px solid transparent; }
    .tab:hover { color: #333; }
    .tab.active { color: #e74c3c; border-bottom-color: #e74c3c; font-weight: 600; }
    .panel { display: none; padding: 24px 32px; }
    .panel.active { display: block; }
    table { width: 100%; border-collapse: collapse; font-size: 0.9em; }
    th { text-align: left; padding: 8px 12px; background: #eee; font-weight: 600; border-bottom: 2px solid #ddd; }
    td { padding: 6px 12px; border-bottom: 1px solid #eee; font-family: 'SF Mono', Menlo, monospace;
         font-size: 0.85em; word-break: break-all; }
    tr.app td { font-weight: 600; color: #222; }
    tr.dep td { color: #999; }
    h3 { margin: 20px 0 10px; font-size: 1em; color: #555; }
    h3:first-child { margin-top: 0; }
    .empty { color: #999; font-style: italic; }
    """
  end

  # --- Inline JS for tab switching ---

  defp js do
    """
    function showTab(id) {
      document.querySelectorAll('.panel').forEach(function(p) { p.classList.remove('active'); });
      document.querySelectorAll('.tab').forEach(function(t) { t.classList.remove('active'); });
      document.getElementById(id).classList.add('active');
      event.target.classList.add('active');
    }
    """
  end
end

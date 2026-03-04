defmodule Ignite.Controller do
  @moduledoc """
  Response helpers for controllers.

  Instead of manually building HTTP strings, controllers use these
  helpers to set the response on the conn:

      def index(conn) do
        text(conn, "Welcome!")
      end
  """

  @doc """
  Sets a plain text response on the conn.

  ## Examples

      text(conn, "Hello!")          # 200 OK
      text(conn, "Oops", 500)      # 500 Internal Server Error
  """
  def text(conn, body, status \\ 200) do
    %Ignite.Conn{
      conn
      | status: status,
        resp_body: body,
        resp_headers: Map.put(conn.resp_headers, "content-type", "text/plain"),
        halted: true
    }
  end

  @doc """
  Sets an HTML response on the conn.

  ## Examples

      html(conn, "<h1>Hello</h1>")
  """
  def html(conn, body, status \\ 200) do
    %Ignite.Conn{
      conn
      | status: status,
        resp_body: body,
        resp_headers: Map.put(conn.resp_headers, "content-type", "text/html"),
        halted: true
    }
  end

  @doc """
  Renders an EEx template and sets it as the HTML response.

  Templates are loaded from the `templates/` directory.

  ## Examples

      render(conn, "profile", name: "Rajesh", id: 42)
      # Renders templates/profile.html.eex with @name and @id available
  """
  def render(conn, template_name, assigns \\ []) do
    template_path = Path.join("templates", "#{template_name}.html.eex")
    content = EEx.eval_file(template_path, assigns: Enum.into(assigns, %{}))
    html(conn, content)
  end

  @doc """
  Converts a conn into a raw HTTP response string for sending over TCP.
  """
  def send_resp(conn) do
    status_line = "HTTP/1.1 #{conn.status} #{status_text(conn.status)}\r\n"

    headers =
      conn.resp_headers
      |> Map.put("content-length", Integer.to_string(byte_size(conn.resp_body)))
      |> Map.put("connection", "close")
      |> Enum.map(fn {k, v} -> "#{k}: #{v}\r\n" end)
      |> Enum.join()

    status_line <> headers <> "\r\n" <> conn.resp_body
  end

  defp status_text(200), do: "OK"
  defp status_text(201), do: "Created"
  defp status_text(301), do: "Moved Permanently"
  defp status_text(302), do: "Found"
  defp status_text(400), do: "Bad Request"
  defp status_text(404), do: "Not Found"
  defp status_text(500), do: "Internal Server Error"
  defp status_text(_), do: "OK"
end

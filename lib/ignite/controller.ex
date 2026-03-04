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
        resp_headers: Map.put(conn.resp_headers, "content-type", "text/html; charset=utf-8"),
        halted: true
    }
  end

  @doc """
  Sets a JSON response on the conn.

  Encodes the given data (map, list, etc.) as JSON using `Jason.encode!/1`
  and sets the content-type to `application/json`.

  ## Examples

      json(conn, %{status: "ok", count: 42})
      json(conn, [1, 2, 3])
      json(conn, %{error: "not found"}, 404)
  """
  def json(conn, data, status \\ 200) do
    %Ignite.Conn{
      conn
      | status: status,
        resp_body: Jason.encode!(data),
        resp_headers: Map.put(conn.resp_headers, "content-type", "application/json"),
        halted: true
    }
  end

  @doc """
  Redirects the client to a different URL.

  Sets a 302 status, the `location` header, and halts the pipeline.

  ## Examples

      redirect(conn, to: "/")
      redirect(conn, to: "/users/42")
  """
  def redirect(conn, to: path) do
    %Ignite.Conn{
      conn
      | status: 302,
        resp_body: "",
        resp_headers:
          conn.resp_headers
          |> Map.put("location", path)
          |> Map.put("content-type", "text/html; charset=utf-8"),
        halted: true
    }
  end

  @doc """
  Stores a flash message in the session.

  Flash messages survive one redirect — they're read on the next
  request and then cleared automatically.

  ## Examples

      conn |> put_flash(:info, "User created!") |> redirect(to: "/")
      conn |> put_flash(:error, "Something went wrong")
  """
  def put_flash(conn, key, message) do
    flash = Map.get(conn.session, "_flash", %{})
    new_flash = Map.put(flash, to_string(key), message)
    new_session = Map.put(conn.session, "_flash", new_flash)
    %Ignite.Conn{conn | session: new_session}
  end

  @doc """
  Reads flash messages from the conn.

  With no key argument, returns the entire flash map.
  With a key, returns that specific message (or nil).

  ## Examples

      get_flash(conn)           #=> %{"info" => "Created!"}
      get_flash(conn, :info)    #=> "Created!"
      get_flash(conn, :error)   #=> nil
  """
  def get_flash(conn) do
    get_in(conn.private, [:flash]) || %{}
  end

  def get_flash(conn, key) do
    conn |> get_flash() |> Map.get(to_string(key))
  end

  @doc """
  Returns an HTML hidden input containing a masked CSRF token.

  Use this in forms to protect against Cross-Site Request Forgery:

      <form action="/users" method="POST">
        \#{csrf_token_tag(conn)}
        <input type="text" name="username">
        <button type="submit">Create</button>
      </form>
  """
  def csrf_token_tag(conn) do
    Ignite.CSRF.csrf_token_tag(conn)
  end

  @doc """
  Returns the CSP nonce for this request.

  Use this to add `nonce="..."` to inline `<script>` tags so they
  pass the Content Security Policy check.

  ## Example

      <script nonce="\#{csp_nonce(conn)}">
        console.log("allowed by CSP");
      </script>
  """
  def csp_nonce(conn) do
    Ignite.CSP.csp_nonce(conn)
  end

  @doc """
  Wraps JavaScript code in a `<script>` tag with the CSP nonce.

  ## Example

      csp_script_tag(conn, "alert('hello');")
      #=> ~s(<script nonce="abc123">alert('hello');</script>)
  """
  def csp_script_tag(conn, js_code) do
    Ignite.CSP.csp_script_tag(conn, js_code)
  end

  @doc """
  Returns a cache-busted path for a static asset file.

  Delegates to `Ignite.Static.static_path/1`. The hash is computed from
  the file's content at boot time and cached in ETS.

  ## Examples

      static_path("ignite.js")   #=> "/assets/ignite.js?v=a1b2c3d4"
  """
  def static_path(filename) do
    Ignite.Static.static_path(filename)
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
  defp status_text(403), do: "Forbidden"
  defp status_text(404), do: "Not Found"
  defp status_text(422), do: "Unprocessable Entity"
  defp status_text(429), do: "Too Many Requests"
  defp status_text(500), do: "Internal Server Error"
  defp status_text(_), do: "OK"
end

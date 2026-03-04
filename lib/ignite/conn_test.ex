defmodule Ignite.ConnTest do
  @moduledoc """
  Test helpers for Ignite controllers and routes.

  Provides convenience functions for building test connections,
  dispatching requests through the router, and asserting responses —
  without starting Cowboy or making real HTTP requests.

  ## Usage

      defmodule MyApp.WelcomeControllerTest do
        use ExUnit.Case
        import Ignite.ConnTest

        @router MyApp.Router

        test "GET / returns 200" do
          conn = get(@router, "/")
          assert html_response(conn, 200) =~ "Ignite Framework"
        end
      end

  ## How It Works

  Tests call `Router.call(conn)` directly, bypassing Cowboy entirely.
  The conn flows through the same plug pipeline and route dispatch
  that a real HTTP request would — middleware, CSRF checks, and all.

  For POST/PUT/PATCH/DELETE requests that need CSRF protection,
  use `init_test_session/2` + `with_csrf/1` to set up a valid token
  pair. JSON API requests can use `put_content_type/2` with
  `"application/json"` to bypass CSRF (just like real JSON clients).
  """

  @doc """
  Builds a bare `%Ignite.Conn{}` with the given method, path, and params.

  The conn has no session, cookies, or headers — use `init_test_session/2`
  or `put_req_header/3` to add those.

  ## Examples

      build_conn(:get, "/")
      build_conn(:post, "/users", %{"username" => "jose"})
  """
  def build_conn(method, path, params \\ %{}) do
    %Ignite.Conn{
      method: method |> to_string() |> String.upcase(),
      path: path,
      params: params
    }
  end

  @doc """
  Dispatches a conn through the given router module.

  Calls `router.call(conn)`, which runs the full plug pipeline
  and route dispatch.

  ## Examples

      conn = build_conn(:get, "/")
      conn = dispatch(conn, MyApp.Router)
  """
  def dispatch(conn, router) do
    router.call(conn)
  end

  @doc """
  Builds a GET request and dispatches it through the router.

  ## Examples

      conn = get(MyApp.Router, "/")
      conn = get(MyApp.Router, "/users/42")
  """
  def get(router, path, params \\ %{}) do
    build_conn(:get, path, params) |> dispatch(router)
  end

  @doc """
  Builds a POST request and dispatches it through the router.

  For form submissions, use `init_test_session/2` + `with_csrf/1`
  to pass CSRF validation. For JSON APIs, use `put_content_type/2`.

  ## Examples

      conn =
        build_conn(:post, "/users", %{"username" => "jose"})
        |> init_test_session()
        |> with_csrf()
        |> dispatch(MyApp.Router)
  """
  def post(router, path, params \\ %{}) do
    build_conn(:post, path, params) |> dispatch(router)
  end

  @doc """
  Builds a PUT request and dispatches it through the router.
  """
  def put(router, path, params \\ %{}) do
    build_conn(:put, path, params) |> dispatch(router)
  end

  @doc """
  Builds a PATCH request and dispatches it through the router.
  """
  def patch(router, path, params \\ %{}) do
    build_conn(:patch, path, params) |> dispatch(router)
  end

  @doc """
  Builds a DELETE request and dispatches it through the router.
  """
  def delete(router, path, params \\ %{}) do
    build_conn(:delete, path, params) |> dispatch(router)
  end

  @doc """
  Asserts the response has the given status and a `text/plain` content type.
  Returns the response body.

  Raises if the status doesn't match or the content type is wrong.

  ## Examples

      body = text_response(conn, 200)
      assert body =~ "Hello"
  """
  def text_response(conn, status) do
    assert_status!(conn, status)
    assert_content_type!(conn, "text/plain")
    conn.resp_body
  end

  @doc """
  Asserts the response has the given status and an `text/html` content type.
  Returns the response body.

  ## Examples

      body = html_response(conn, 200)
      assert body =~ "<h1>"
  """
  def html_response(conn, status) do
    assert_status!(conn, status)
    assert_content_type!(conn, "text/html")
    conn.resp_body
  end

  @doc """
  Asserts the response has the given status and an `application/json` content type.
  Returns the decoded JSON body as a map.

  ## Examples

      data = json_response(conn, 200)
      assert data["status"] == "ok"
  """
  def json_response(conn, status) do
    assert_status!(conn, status)
    assert_content_type!(conn, "application/json")

    case Jason.decode(conn.resp_body) do
      {:ok, decoded} ->
        decoded

      {:error, reason} ->
        raise "Expected valid JSON body, got decode error: #{inspect(reason)}\n\nBody: #{conn.resp_body}"
    end
  end

  @doc """
  Returns the path from the `location` response header.

  Raises if no `location` header is set.

  ## Examples

      conn =
        build_conn(:post, "/users", %{"username" => "jose"})
        |> init_test_session()
        |> with_csrf()
        |> dispatch(MyApp.Router)

      assert redirected_to(conn) == "/"
  """
  def redirected_to(conn) do
    case Map.get(conn.resp_headers, "location") do
      nil ->
        raise "Expected response to have a location header (redirect), but none was set.\n" <>
                "Response status: #{conn.status}"

      location ->
        location
    end
  end

  @doc """
  Initializes a test session on the conn.

  Generates a CSRF token and merges any extra session data. This is
  required for POST/PUT/PATCH/DELETE requests that go through CSRF
  validation (non-JSON requests).

  ## Examples

      conn = build_conn(:post, "/users") |> init_test_session()
      conn = build_conn(:post, "/users") |> init_test_session(%{"user_id" => 1})
  """
  def init_test_session(conn, extra \\ %{}) do
    csrf_token = Ignite.CSRF.generate_token()

    session =
      Map.merge(%{"_csrf_token" => csrf_token}, extra)

    %Ignite.Conn{conn | session: session}
  end

  @doc """
  Adds a valid masked CSRF token to the conn's params.

  Must be called after `init_test_session/2` (which sets the session
  token). The masked token will pass the router's `verify_csrf_token`
  plug.

  ## Examples

      conn =
        build_conn(:post, "/users", %{"username" => "jose"})
        |> init_test_session()
        |> with_csrf()
        |> dispatch(MyApp.Router)
  """
  def with_csrf(conn) do
    session_token = conn.session["_csrf_token"]

    unless session_token do
      raise "No CSRF token in session. Call init_test_session/2 before with_csrf/1."
    end

    masked = Ignite.CSRF.mask_token(session_token)
    %Ignite.Conn{conn | params: Map.put(conn.params, "_csrf_token", masked)}
  end

  @doc """
  Sets the `content-type` request header on the conn.

  Useful for JSON API tests where CSRF is bypassed:

  ## Examples

      conn =
        build_conn(:post, "/api/echo", %{"msg" => "hi"})
        |> put_content_type("application/json")
        |> dispatch(MyApp.Router)
  """
  def put_content_type(conn, content_type) do
    %Ignite.Conn{conn | headers: Map.put(conn.headers, "content-type", content_type)}
  end

  @doc """
  Sets a request header on the conn.

  ## Examples

      conn = build_conn(:get, "/") |> put_req_header("accept", "application/json")
  """
  def put_req_header(conn, key, value) do
    %Ignite.Conn{conn | headers: Map.put(conn.headers, key, value)}
  end

  # --- Private Assertion Helpers ---

  defp assert_status!(conn, expected) do
    actual = conn.status

    if actual != expected do
      raise "Expected response status #{expected}, got #{actual}.\n\nBody: #{String.slice(conn.resp_body, 0, 500)}"
    end
  end

  defp assert_content_type!(conn, expected) do
    actual = Map.get(conn.resp_headers, "content-type", "")

    unless String.starts_with?(actual, expected) do
      raise "Expected content-type starting with #{inspect(expected)}, got #{inspect(actual)}."
    end
  end
end

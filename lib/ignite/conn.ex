defmodule Ignite.Conn do
  @moduledoc """
  The connection struct — the heart of every request/response in Ignite.

  This struct tracks the entire lifecycle of an HTTP request:
  - What came in (method, path, headers)
  - What's going out (status, response body, response headers)

  Every function in our framework receives a conn and returns a conn.
  This is the same pattern Phoenix uses with %Plug.Conn{}.
  """

  defstruct [
    # Request fields (filled by the parser)
    method: nil,
    path: nil,
    headers: %{},
    params: %{},

    # Session & cookies (filled by Cowboy adapter from request cookies)
    cookies: %{},
    session: %{},
    resp_cookies: [],

    # Internal framework state (not user-facing).
    # Used by flash messages: adapter stores inherited flash here on request,
    # get_flash reads from here. put_flash writes to session for next request.
    private: %{},

    # Response fields (filled by controllers)
    status: 200,
    resp_headers: %{"content-type" => "text/plain"},
    resp_body: "",

    # Control flow
    halted: false
  ]
end

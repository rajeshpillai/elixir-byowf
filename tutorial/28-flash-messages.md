# Step 28: Flash Messages

## What We're Building

Flash messages — one-time notifications that survive a redirect. When a user creates a resource, the controller sets a flash message, redirects, and the next page displays the message once, then it disappears.

## The Problem

Right now, `POST /users` returns `"User 'Jose' created!"` as a plain text 201 response. There's no way to:
- Redirect the user back to the home page after creation
- Show a "success" banner on the landing page
- Auto-clear the message after one page view

Every real web app needs this pattern: **action → flash → redirect → display → clear**.

## How Phoenix Does It

Phoenix stores flash messages in the session cookie. The lifecycle:
1. Controller calls `put_flash(conn, :info, "Created!")` — stores in `conn.session["_flash"]`
2. Controller calls `redirect(conn, to: "/")` — sends 302 + signed session cookie
3. Browser follows redirect, sends the cookie back
4. Next request decodes session, reads flash, renders it
5. Flash is cleared from the session cookie on the response

The key insight: **flash is just session data with auto-clear semantics**.

## Design Decisions

### Signed Cookie Sessions (Zero New Dependencies)

We need somewhere to store the flash across requests. Options:
- **Server-side session store** (ETS/Redis) — requires session IDs, cleanup, shared state
- **Signed cookie** — session data lives in the cookie itself, verified with a secret key

We chose signed cookies because `Plug.Crypto.MessageVerifier` is already available as a transitive dependency of `plug_cowboy`. No new deps needed.

The session is serialized with `:erlang.term_to_binary/1`, signed with `Plug.Crypto.MessageVerifier.sign/2`, and stored in a `_ignite_session` cookie. Tampering is detected by signature verification.

### One-Time Read Semantics

Flash messages must disappear after being read. We achieve this by:
1. On **request**: decode the session cookie (flash is still in the session)
2. Controller reads flash via `get_flash(conn)` and uses it in the response
3. On **response**: clear `_flash` from the session before encoding the cookie

This means: set flash → redirect → show flash → next request has no flash.

## Implementation

### 1. Conn Gets Session Fields

We add four fields to `%Ignite.Conn{}`:

```elixir
# lib/ignite/conn.ex
defstruct [
  # ... existing fields ...
  cookies: %{},       # Parsed request cookies (from "cookie" header)
  session: %{},       # Deserialized session data (from signed cookie)
  resp_cookies: [],   # Reserved for future use
  private: %{},       # Internal framework state (flash storage)
]
```

The `private` map stores framework-internal state. The adapter uses `private.flash` to hold the inherited flash from the previous request — this is what `get_flash` reads from.

### 2. The Session Module

`Ignite.Session` handles encoding, decoding, and cookie operations:

```elixir
# lib/ignite/session.ex
defmodule Ignite.Session do
  @default_secret "ignite-secret-key-change-in-prod-min-64-bytes-long-for-security!!"
  @cookie_name "_ignite_session"

  # In production, set via config: config :ignite, :secret_key_base, "..."
  defp secret do
    Application.get_env(:ignite, :secret_key_base, @default_secret)
  end

  def cookie_name, do: @cookie_name

  def encode(session) when is_map(session) do
    session
    |> :erlang.term_to_binary()
    |> Plug.Crypto.MessageVerifier.sign(secret())
  end

  def decode(nil), do: :error
  def decode(""), do: :error

  def decode(cookie_value) when is_binary(cookie_value) do
    case Plug.Crypto.MessageVerifier.verify(cookie_value, secret()) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary, [:safe])}
      :error ->
        :error
    end
  end

  def parse_cookies(cookie_header) do
    cookie_header
    |> String.split(";")
    |> Enum.into(%{}, fn pair ->
      case String.split(String.trim(pair), "=", parts: 2) do
        [key, value] -> {key, value}
        [key] -> {key, ""}
      end
    end)
  end

  def build_cookie_header(session) do
    value = encode(session)
    "#{@cookie_name}=#{value}; Path=/; HttpOnly; SameSite=Lax"
  end
end
```

Key details:
- **`:safe` flag** on `binary_to_term` prevents atom table DoS attacks — only existing atoms are allowed
- **`HttpOnly`** cookie flag prevents JavaScript from reading the session
- **`SameSite=Lax`** provides basic CSRF protection

### 3. Controller Helpers

Three new helpers in `Ignite.Controller`:

```elixir
# lib/ignite/controller.ex

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

def put_flash(conn, key, message) do
  flash = Map.get(conn.session, "_flash", %{})
  new_flash = Map.put(flash, to_string(key), message)
  new_session = Map.put(conn.session, "_flash", new_flash)
  %Ignite.Conn{conn | session: new_session}
end

def get_flash(conn) do
  get_in(conn.private, [:flash]) || %{}
end

def get_flash(conn, key) do
  conn |> get_flash() |> Map.get(to_string(key))
end
```

`put_flash` writes to `conn.session["_flash"]` (for the NEXT request's cookie), while `get_flash` reads from `conn.private.flash` (the CURRENT request's inherited flash). This separation is what gives flash messages their one-time semantics.

### 4. Cowboy Adapter Wiring

The adapter handles cookies on both sides of the request. The key insight: flash is **popped from the session on request** (moved to `private.flash`), so it won't be echoed back unless `put_flash` explicitly adds new flash.

**On request** (`cowboy_to_conn/1`):
```elixir
cookies = Ignite.Session.parse_cookies(Map.get(headers, "cookie"))

raw_session =
  case Ignite.Session.decode(Map.get(cookies, Ignite.Session.cookie_name())) do
    {:ok, data} -> data
    :error -> %{}
  end

# Pop flash from session → store in private for get_flash to read.
{flash, session} = Map.pop(raw_session, "_flash", %{})

%Ignite.Conn{
  # ... existing fields ...
  cookies: cookies,
  session: session,
  private: %{flash: flash}
}
```

**On response** (`init/2`) — uses Cowboy's cookie API:
```elixir
# Encode conn.session as-is (has new flash only if put_flash was called)
cookie_value = Ignite.Session.encode(conn.session)

req =
  :cowboy_req.set_resp_cookie(
    Ignite.Session.cookie_name(),
    cookie_value,
    req,
    %{path: "/", http_only: true, same_site: :lax}
  )

:cowboy_req.reply(conn.status, conn.resp_headers, conn.resp_body, req)
```

Note: Cowboy requires cookies to be set via `:cowboy_req.set_resp_cookie/4` — you cannot put `set-cookie` directly in the headers map.

### 5. LiveView Gets Session Access

The WebSocket handshake carries cookies, so LiveViews can read the session too:

```elixir
# lib/ignite/live_view/handler.ex
def init(req, state) do
  cookie_header = :cowboy_req.header("cookie", req, "")
  cookies = Ignite.Session.parse_cookies(cookie_header)

  session =
    case Ignite.Session.decode(Map.get(cookies, Ignite.Session.cookie_name())) do
      {:ok, data} -> data
      :error -> %{}
    end

  {:cowboy_websocket, req, Map.put(state, :session, session)}
end

def websocket_init(state) do
  view_module = state.view
  session = Map.get(state, :session, %{})

  case apply(view_module, :mount, [%{}, session]) do
    # session is now available to LiveViews
  end
end
```

### 6. Demo: Flash on User Creation

**UserController** — set flash and redirect:
```elixir
def create(conn) do
  username = conn.params["username"] || "anonymous"

  conn
  |> put_flash(:info, "User '#{username}' created!")
  |> redirect(to: "/")
end
```

**WelcomeController** — display flash on index:
```elixir
def index(conn) do
  flash_html =
    case get_flash(conn) do
      flash when flash == %{} -> ""
      flash ->
        Enum.map_join(flash, "\n", fn {type, msg} ->
          {bg, border, color} = case type do
            "info"  -> {"#d4edda", "#c3e6cb", "#155724"}
            "error" -> {"#f8d7da", "#f5c6cb", "#721c24"}
            _       -> {"#e2e3e5", "#d6d8db", "#383d41"}
          end
          "<div style=\"background:#{bg};color:#{color};...\">#{msg}</div>"
        end)
    end

  html(conn, "#{flash_html}<h1>Ignite Framework</h1>...")
end
```

## The Flash Lifecycle (Complete)

```
POST /users (username=Jose)
  → UserController.create/1
  → put_flash(:info, "User 'Jose' created!")  — stores in conn.session["_flash"]
  → redirect(to: "/")                         — 302 status + location header
  ↓
Response: 302 Found
  set-cookie: _ignite_session=<signed{_flash: %{info: "User 'Jose' created!"}}>
  location: /
  ↓
Browser follows redirect → GET /
  cookie: _ignite_session=<signed{_flash: %{info: "User 'Jose' created!"}}>
  ↓
Cowboy adapter parses cookie → decodes session → conn.session has _flash
  → WelcomeController.index/1
  → get_flash(conn, :info)  → "User 'Jose' created!"
  → Renders green banner
  ↓
Response: 200 OK
  set-cookie: _ignite_session=<signed{}>  ← flash CLEARED
  ↓
Browser refresh → GET /
  cookie: _ignite_session=<signed{}>
  → No flash in session → no banner shown
```

## Testing

```bash
# 1. Create a user — should redirect with flash cookie
curl -v -X POST -d "username=Jose" http://localhost:4000/users
# Look for: HTTP/1.1 302 Found, location: /, set-cookie: _ignite_session=...

# 2. Follow the redirect with the cookie
curl -v -b "_ignite_session=<value from above>" http://localhost:4000/
# Look for: green "User 'Jose' created!" banner in HTML

# 3. Visit again with the NEW cookie (flash cleared)
curl -v -b "_ignite_session=<value from step 2>" http://localhost:4000/
# Look for: no flash banner
```

Or just use a browser: `curl -X POST -d "username=Jose" http://localhost:4000/users` and open http://localhost:4000 — you'll see the flash if cookies are enabled.

## Security Notes

- **Signed, not encrypted**: Session data is tamper-proof but readable. Don't store secrets in the session.
- **HttpOnly**: JavaScript cannot read the session cookie (XSS protection).
- **SameSite=Lax**: The cookie is sent on same-site requests and top-level navigations only (basic CSRF protection).
- **`:safe` deserialization**: `binary_to_term(data, [:safe])` prevents atom table exhaustion attacks.
- **Secret key**: In production, use a strong random key from an environment variable.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Session storage | Signed cookie | Signed cookie (default) |
| Session library | `Plug.Crypto.MessageVerifier` | `Plug.Crypto.MessageVerifier` |
| Flash storage | `session["_flash"]` | `session["phoenix_flash"]` |
| Flash clear | Adapter clears on response | `Plug.Session` + `Phoenix.Controller.fetch_flash` |
| Cookie flags | HttpOnly, SameSite=Lax | HttpOnly, SameSite=Lax, Secure |

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/conn.ex` | Added `cookies`, `session`, `resp_cookies` fields |
| `lib/ignite/session.ex` | **New** — signed cookie encode/decode |
| `lib/ignite/controller.ex` | Added `redirect/2`, `put_flash/3`, `get_flash/1,2` |
| `lib/ignite/adapters/cowboy.ex` | Cookie parsing on request, session cookie on response |
| `lib/ignite/live_view/handler.ex` | Pass session to LiveView mount |
| `lib/my_app/controllers/user_controller.ex` | Flash + redirect on create |
| `lib/my_app/controllers/welcome_controller.ex` | Flash display on index |

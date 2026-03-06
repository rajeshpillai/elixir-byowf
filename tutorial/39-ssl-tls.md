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
  @moduledoc """
  SSL/TLS configuration for Ignite.

  Reads the `:ssl` key from application config and determines whether
  to start Cowboy in clear (HTTP) or TLS (HTTPS) mode.
  """

  def child_spec(port, dispatch) do
    case Application.get_env(:ignite, :ssl) do
      nil ->
        # Plain HTTP (dev/test)
        %{
          id: :cowboy_listener,
          start:
            {:cowboy, :start_clear,
             [
               :ignite_http,
               [port: port],
               %{env: %{dispatch: dispatch}}
             ]}
        }

      ssl_opts when is_list(ssl_opts) ->
        # HTTPS (prod)
        certfile = Keyword.fetch!(ssl_opts, :certfile)
        keyfile = Keyword.fetch!(ssl_opts, :keyfile)

        validate_file!(certfile, "SSL certificate")
        validate_file!(keyfile, "SSL private key")

        # Erlang :ssl expects charlists for file paths
        tls_opts =
          [
            port: port,
            certfile: String.to_charlist(certfile),
            keyfile: String.to_charlist(keyfile)
          ]
          |> maybe_add(:cacertfile, ssl_opts)

        %{
          id: :cowboy_listener,
          start:
            {:cowboy, :start_tls,
             [
               :ignite_https,
               tls_opts,
               %{env: %{dispatch: dispatch}}
             ]}
        }
    end
  end

  def redirect_child_spec(http_port, https_port) do
    redirect_dispatch =
      :cowboy_router.compile([
        {:_, [{"/[...]", Ignite.SSL.RedirectHandler, %{https_port: https_port}}]}
      ])

    %{
      id: :cowboy_redirect_listener,
      start:
        {:cowboy, :start_clear,
         [
           :ignite_http_redirect,
           [port: http_port],
           %{env: %{dispatch: redirect_dispatch}}
         ]}
    }
  end

  def ssl_configured? do
    Application.get_env(:ignite, :ssl) != nil
  end

  # Adds an optional SSL option (like :cacertfile) if present in config.
  defp maybe_add(tls_opts, key, ssl_opts) do
    case Keyword.get(ssl_opts, key) do
      nil -> tls_opts
      value -> Keyword.put(tls_opts, key, String.to_charlist(value))
    end
  end

  defp validate_file!(path, label) do
    unless File.exists?(path) do
      raise """
      #{label} not found: #{path}

      To generate self-signed certificates for testing:

          mix ignite.gen.cert

      For production, use certificates from Let's Encrypt or your CA.
      """
    end
  end
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
# lib/ignite/ssl/redirect_handler.ex
defmodule Ignite.SSL.RedirectHandler do
  @moduledoc """
  Cowboy handler that 301-redirects all HTTP requests to HTTPS.

  Preserves the original path and query string. The target HTTPS port
  is passed in via init state.
  """

  @behaviour :cowboy_handler

  @impl true
  def init(req, state) do
    https_port = state.https_port
    host = :cowboy_req.host(req)
    path = :cowboy_req.path(req)
    qs = :cowboy_req.qs(req)

    location = build_https_url(host, https_port, path, qs)

    req =
      :cowboy_req.reply(
        301,
        %{"location" => location},
        "Moved permanently to #{location}",
        req
      )

    {:ok, req, state}
  end

  defp build_https_url(host, 443, path, ""), do: "https://#{host}#{path}"
  defp build_https_url(host, 443, path, qs), do: "https://#{host}#{path}?#{qs}"
  defp build_https_url(host, port, path, ""), do: "https://#{host}:#{port}#{path}"
  defp build_https_url(host, port, path, qs), do: "https://#{host}:#{port}#{path}?#{qs}"
end
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

**Create `lib/ignite/hsts.ex`:**

```elixir
# lib/ignite/hsts.ex
defmodule Ignite.HSTS do
  @moduledoc """
  HTTP Strict Transport Security (HSTS) plug for Ignite.

  When enabled, adds the `strict-transport-security` response header
  to tell browsers: "Only connect to this site over HTTPS for the next
  N seconds."
  """

  @default_max_age 31_536_000

  def put_hsts_header(conn) do
    if Application.get_env(:ignite, :hsts, false) do
      max_age = Application.get_env(:ignite, :hsts_max_age, @default_max_age)
      value = "max-age=#{max_age}; includeSubDomains"

      new_headers = Map.put(conn.resp_headers, "strict-transport-security", value)
      %Ignite.Conn{conn | resp_headers: new_headers}
    else
      conn
    end
  end
end
```

The module adds the header:

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

**Create `lib/mix/tasks/ignite.gen.cert.ex`:**

```elixir
# lib/mix/tasks/ignite.gen.cert.ex
defmodule Mix.Tasks.Ignite.Gen.Cert do
  @moduledoc """
  Generates self-signed SSL certificates for local development.

      $ mix ignite.gen.cert

  Creates `priv/ssl/cert.pem` and `priv/ssl/key.pem` using `openssl`.
  These are **not** suitable for production.
  """

  use Mix.Task

  @shortdoc "Generate self-signed SSL certificates for development"

  @output_dir "priv/ssl"
  @certfile "cert.pem"
  @keyfile "key.pem"

  @impl true
  def run(args) do
    hostname = parse_hostname(args)

    File.mkdir_p!(@output_dir)

    certpath = Path.join(@output_dir, @certfile)
    keypath = Path.join(@output_dir, @keyfile)

    if File.exists?(certpath) do
      Mix.shell().info("""
      Certificate already exists at #{certpath}.
      Delete it first if you want to regenerate:

          rm -rf #{@output_dir}
          mix ignite.gen.cert
      """)
    else
      generate_cert(hostname, certpath, keypath)
    end
  end

  defp generate_cert(hostname, certpath, keypath) do
    Mix.shell().info("Generating self-signed certificate for #{hostname}...")

    {output, exit_code} =
      System.cmd("openssl", [
        "req",
        "-x509",
        "-newkey", "rsa:2048",
        "-nodes",
        "-keyout", keypath,
        "-out", certpath,
        "-days", "365",
        "-subj", "/CN=#{hostname}/O=Ignite Dev"
      ], stderr_to_stdout: true)

    if exit_code == 0 do
      Mix.shell().info("""

      Self-signed certificate generated successfully!

        Certificate: #{certpath}
        Private key: #{keypath}
        Valid for:   365 days
        Hostname:    #{hostname}

      Add this to your config/prod.exs:

          config :ignite,
            port: 4443,
            ssl: [
              certfile: "#{certpath}",
              keyfile: "#{keypath}"
            ]

      Then start with: MIX_ENV=prod iex -S mix

      Note: Browsers will show a warning for self-signed certs.
      Use `curl -k` to skip verification when testing.
      """)
    else
      Mix.shell().error("Failed to generate certificate:\n#{output}")
      Mix.shell().error("Make sure `openssl` is installed and in your PATH.")
    end
  end

  defp parse_hostname(args) do
    case OptionParser.parse(args, strict: [hostname: :string]) do
      {opts, _, _} -> Keyword.get(opts, :hostname, "localhost")
      _ -> "localhost"
    end
  end
end
```

For local HTTPS testing, run:

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

The full updated `start/2` and helper functions in `application.ex`:

```elixir
# lib/ignite/application.ex (relevant changes)
@impl true
def start(_type, _args) do
  port = Application.get_env(:ignite, :port, 4000)
  Ignite.Static.init()

  dispatch = :cowboy_router.compile([{:_, [
    # ... existing routes ...
    {"/[...]", Ignite.Adapters.Cowboy, []}
  ]}])

  children =
    [
      MyApp.Repo,
      Ignite.PubSub,
      Ignite.Presence,
      Ignite.RateLimiter,

      # Start Cowboy — HTTP or HTTPS depending on :ssl config
      Ignite.SSL.child_spec(port, dispatch)
    ] ++ redirect_children(port) ++ dev_children()

  scheme = if Ignite.SSL.ssl_configured?(), do: "https", else: "http"
  Logger.info("Ignite is heating up on #{scheme}://localhost:#{port}")

  opts = [strategy: :one_for_one, name: Ignite.Supervisor]
  Supervisor.start_link(children, opts)
end

# Optional HTTP→HTTPS redirect listener (only when SSL is configured).
# Set `config :ignite, http_redirect_port: 4080` to enable.
defp redirect_children(https_port) do
  http_port = Application.get_env(:ignite, :http_redirect_port)

  if http_port && Ignite.SSL.ssl_configured?() do
    Logger.info("HTTP→HTTPS redirect on port #{http_port}")
    [Ignite.SSL.redirect_child_spec(http_port, https_port)]
  else
    []
  end
end
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

---

[← Previous: Step 38 - Test Helpers (ConnTest)](38-test-helpers.md) | [Next: Step 40 - Deployment with `mix release` + Rate Limiting →](40-release-and-rate-limit.md)

# Step 37: Static Asset Pipeline

## What We're Building

A cache-busting static asset system. Instead of hardcoding `<script src="/assets/ignite.js">`, templates now use a `static_path/1` helper that appends a content hash:

```html
<script src="/assets/ignite.js?v=a1b2c3d4"></script>
```

When the file contents change, the hash changes, forcing browsers to fetch the new version. When the contents haven't changed, browsers serve from cache — zero unnecessary downloads.

## The Problem

Before this step, templates hardcoded asset paths:

```html
<script src="/assets/morphdom.min.js"></script>
<script src="/assets/hooks.js"></script>
<script src="/assets/ignite.js"></script>
```

After deploying a code change:
- The URL `/assets/ignite.js` stays the same
- Browsers cache the old version (sometimes for hours or days)
- Users see stale JavaScript until they hard-refresh
- No way to force cache invalidation without changing the filename

## How Phoenix Does It

Phoenix uses a multi-layered approach:

1. **esbuild** bundles and minifies JavaScript
2. **Tailwind** compiles CSS
3. **`mix assets.deploy`** generates fingerprinted filenames (`app-ABC123.js`)
4. **`Plug.Static`** serves files with proper `cache-control`, `etag`, and gzip headers
5. **`cache_manifest.json`** maps original names to fingerprinted names
6. **`Routes.static_path/2`** reads the manifest to generate correct URLs

## Design Decision: Query String vs Filename Fingerprinting

| Approach | Pros | Cons |
|----------|------|------|
| Filename fingerprinting (`app-abc123.js`) | CDN-friendly, optimal caching | Requires a build step, manifest file |
| **Query string (`app.js?v=abc123`)** | No build step, works with any file server | Some CDNs ignore query strings (rare) |

We use **query string versioning** because:
- No build tools needed — hashes are computed from file contents at boot time
- Works immediately with Cowboy's existing `:cowboy_static` handler
- Simple to understand and implement
- Suitable for medium-scale apps behind a reverse proxy

## Implementation

### 1. The Static Module

**Create `lib/ignite/static.ex`:**

```elixir
# lib/ignite/static.ex
defmodule Ignite.Static do
  @table :ignite_static_manifest
  @default_dir "assets"

  def init(dir \\ @default_dir) do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    else
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    build_manifest(dir)
  end

  def rebuild(dir \\ @default_dir) do
    :ets.delete_all_objects(@table)
    build_manifest(dir)
  end

  def static_path(filename) do
    case :ets.lookup(@table, filename) do
      [{^filename, hash}] -> "/assets/#{filename}?v=#{hash}"
      [] -> "/assets/#{filename}"
    end
  end

  defp build_manifest(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn path ->
      filename = Path.relative_to(path, dir)
      hash = hash_file(path)
      :ets.insert(@table, {filename, hash})
    end)
  end
end
```

`build_manifest/1` walks the directory, computes MD5 hashes, and inserts
`{filename, hash}` pairs into ETS. `rebuild/1` clears and re-scans —
called by the reloader when assets change during development.

### 2. ETS for the Manifest

**Why ETS?** The manifest is read on every template render — potentially thousands of times per second. ETS (Erlang Term Storage) is an in-memory table optimized for concurrent reads:

- **`read_concurrency: true`** — tells the BEAM to optimize for multiple readers, reducing lock contention
- **`:named_table`** — allows lookup by table name (`:ignite_static_manifest`) instead of a PID reference
- **`:set`** — each key (filename) maps to exactly one value (hash)
- **`:public`** — any process can read (needed since template rendering happens in different processes than the one that created the table)

The alternative would be a GenServer, but that serializes all lookups through a single process — a bottleneck under load.

### 3. Content Hashing

```elixir
defp hash_file(path) do
  path
  |> File.read!()
  |> :erlang.md5()
  |> Base.encode16(case: :lower)
  |> binary_part(0, 8)
end
```

**`:erlang.md5/1`** — Computes an MD5 digest of the file contents. MD5 is not secure for cryptography (collision attacks exist), but it's perfect for cache busting: fast, deterministic, and changes when even one byte of content changes.

**8 hex characters** — We take only the first 8 characters (32 bits) of the 32-character hex digest. This gives 4 billion possible hashes — more than enough to distinguish file versions. Shorter hashes keep URLs clean.

**Content-based, not time-based** — We hash file contents, not modification times. If you revert a file to a previous version, the hash reverts too, correctly serving the cached version. Timestamp-based approaches would generate a new version even when content is identical.

### 4. Boot-Time Initialization

**Update `lib/ignite/application.ex`** — call `Ignite.Static.init()` at the top of `start/2`:

```elixir
# lib/ignite/application.ex
def start(_type, _args) do
  port = 4000

  # Build static asset manifest before Cowboy starts
  Ignite.Static.init()

  # ... Cowboy dispatch and children ...
end
```

`init/1` must run before Cowboy accepts any requests. Since it's called at the top of `start/2`, before `Supervisor.start_link/2`, this is guaranteed.

### 5. Template Usage

**Update `templates/live.html.eex`** — replace hardcoded asset paths with `static_path/1` calls:

```html
<!-- Before: hardcoded, no cache busting -->
<script src="/assets/ignite.js"></script>

<!-- After: content-hashed, cache-busted -->
<script src="<%= Ignite.Static.static_path("ignite.js") %>"></script>
```

The rendered HTML becomes:

```html
<script src="/assets/ignite.js?v=a1b2c3d4"></script>
```

Cowboy's `:cowboy_static` handler ignores query parameters — it serves the file based on the path (`/assets/ignite.js`). The browser treats `?v=a1b2c3d4` and `?v=e5f6g7h8` as different URLs, forcing a fresh download when the hash changes.

### 6. Controller Convenience

**Update `lib/ignite/controller.ex`** — add a `static_path/1` convenience delegate:

```elixir
# lib/ignite/controller.ex
def static_path(filename) do
  Ignite.Static.static_path(filename)
end
```

Controllers that `import Ignite.Controller` can call `static_path("app.css")` directly, just like Phoenix's `Routes.static_path(@conn, "/assets/app.css")`.

### 7. Hot Reloader Integration

**Update `lib/ignite/reloader.ex`** — watch `assets/` directory and rebuild manifest on changes:

```elixir
# lib/ignite/reloader.ex — in handle_info(:check, state)
new_asset_mtimes = get_asset_mtimes()

if new_asset_mtimes != state.asset_mtimes do
  Logger.info("[Reloader] Asset changes detected — rebuilding static manifest...")
  Ignite.Static.rebuild()
end
```

In development, the reloader already watches `lib/` for code changes. We extend it to also watch `assets/` — when a JS or CSS file changes, the manifest is rebuilt, and the next template render gets the new hash. No server restart needed.

## How Caching Works

```
First visit:
  Browser requests /assets/ignite.js?v=a1b2c3d4
  Server responds with file contents
  Browser caches the response

Second visit (same version):
  Browser has /assets/ignite.js?v=a1b2c3d4 in cache
  Serves from cache → no network request

After code deploy (file changed):
  Template renders /assets/ignite.js?v=NEW_HASH
  Browser doesn't have this URL cached
  Fetches fresh copy from server
```

### Production: Adding Cache-Control Headers

For maximum caching efficiency, configure your reverse proxy to add long-lived cache headers for versioned assets:

```nginx
# nginx config
location /assets/ {
    # Files with ?v= are immutable — cache for 1 year
    if ($args ~* "v=") {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
}
```

The `immutable` directive tells the browser to never even check if the file has changed — it trusts the URL completely. Since the hash changes when the content changes, this is safe.

## Testing

```bash
mix compile
iex -S mix

# 1. Check that static_path returns hashed URLs
Ignite.Static.static_path("ignite.js")
#=> "/assets/ignite.js?v=a1b2c3d4"

Ignite.Static.static_path("hooks.js")
#=> "/assets/hooks.js?v=e5f6g7h8"

# 2. Visit a LiveView page and view source
# http://localhost:4000/counter → View Source
# Script tags should show ?v= parameters

# 3. Test cache busting — modify an asset file
# Add a comment to assets/hooks.js
# Wait 1 second for the reloader
# Check: Ignite.Static.static_path("hooks.js") → different hash

# 4. Missing files return unhashed path
Ignite.Static.static_path("nonexistent.js")
#=> "/assets/nonexistent.js"
```

## Key Concepts

- **ETS (Erlang Term Storage)** — In-memory key-value store optimized for concurrent reads. Used here as a boot-time cache for file hashes. Tables survive until the creating process dies or the table is explicitly deleted.
- **Content-based hashing** — Deriving cache keys from file contents, not timestamps. Ensures identical content always produces the same hash, even across deploys.
- **Cache busting via query string** — Appending `?v=HASH` makes each version a unique URL. Browsers treat different URLs as different resources, forcing fresh downloads when needed.
- **`:erlang.md5/1`** — Fast hash function from the Erlang standard library. Not suitable for security, but perfect for fingerprinting file contents.
- **`read_concurrency: true`** — ETS option that trades slightly slower writes for significantly faster concurrent reads. Ideal for data that's written once and read many times.
- **`binary_part/3`** — Extracts a substring from a binary, starting at the given offset for the given length. We use it to take the first 8 hex characters of an MD5 hash — enough for cache busting without long URLs:
  ```elixir
  binary_part("abcdefghij", 0, 8)  #=> "abcdefgh"
  ```

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| File serving | `:cowboy_static` (Cowboy native) | `Plug.Static` middleware |
| Hash computation | MD5 at boot, stored in ETS | SHA at build time, stored in manifest JSON |
| URL format | `/assets/file.js?v=hash` | `/assets/file-hash.js` |
| Cache busting | Query string | Filename fingerprinting |
| Build tools | None | esbuild, Tailwind |
| Dev reload | Reloader rebuilds manifest | File watcher triggers rebuild |
| Helper | `static_path("file.js")` | `Routes.static_path(conn, "/assets/file.js")` |

Phoenix's approach is more production-optimized (filename fingerprinting works with all CDNs), but requires a build step. Ignite's approach is zero-config — just drop files in `assets/` and they're automatically versioned.

## Files Changed

| File | Change |
|------|--------|
| `lib/ignite/static.ex` | **New** — ETS manifest, `init/1`, `rebuild/1`, `static_path/1` |
| `lib/ignite/application.ex` | Call `Ignite.Static.init()` at boot |
| `lib/ignite/controller.ex` | Added `static_path/1` convenience delegate |
| `templates/live.html.eex` | Use `Ignite.Static.static_path/1` in script tags |
| `lib/ignite/reloader.ex` | Watch `assets/` directory, rebuild manifest on changes |

## File Checklist

- **New** `lib/ignite/static.ex` — ETS manifest with `init/1`, `rebuild/1`, `static_path/1`
- **Modified** `lib/ignite/application.ex` — Call `Ignite.Static.init()` at boot
- **Modified** `lib/ignite/controller.ex` — Added `static_path/1` convenience delegate
- **Modified** `lib/ignite/reloader.ex` — Watch `assets/` directory, rebuild manifest on changes
- **Modified** `templates/live.html.eex` — Use `Ignite.Static.static_path/1` in script tags

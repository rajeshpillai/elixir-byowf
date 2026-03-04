defmodule Ignite.Static do
  @moduledoc """
  Static asset helpers for cache-busted URLs.

  At boot time, scans the configured static directory (default: `assets/`),
  computes an MD5 hash of each file's content, and stores the mapping in an
  ETS table. The `static_path/1` helper appends a `?v=HASH` query string
  so browsers cache-bust correctly when file contents change.

  In development, the `Ignite.Reloader` calls `rebuild/1` whenever asset
  files change on disk, updating the hashes without a server restart.
  """

  @table :ignite_static_manifest
  @default_dir "assets"

  @doc """
  Builds the static asset manifest.

  Creates an ETS table and populates it with `{filename, hash}` entries
  for every file in the given directory. Called once at application start.
  """
  def init(dir \\ @default_dir) do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    else
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    build_manifest(dir)
  end

  @doc """
  Rebuilds the manifest by rescanning the directory.

  Called by `Ignite.Reloader` when asset files change in development.
  """
  def rebuild(dir \\ @default_dir) do
    :ets.delete_all_objects(@table)
    build_manifest(dir)
  end

  @doc """
  Returns a cache-busted path for a static asset.

  Looks up the file's content hash from the ETS manifest and appends it
  as a `?v=` query parameter. If the file isn't in the manifest (doesn't
  exist), returns the path without a version string.

  ## Examples

      Ignite.Static.static_path("ignite.js")
      #=> "/assets/ignite.js?v=a1b2c3d4"

      Ignite.Static.static_path("missing.js")
      #=> "/assets/missing.js"
  """
  def static_path(filename) do
    case :ets.lookup(@table, filename) do
      [{^filename, hash}] ->
        "/assets/#{filename}?v=#{hash}"

      [] ->
        "/assets/#{filename}"
    end
  end

  # Walks the directory, computes MD5 for each file, stores in ETS.
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

  # First 8 hex chars of the MD5 digest — sufficient for cache busting.
  # MD5 is fine here (not used for security, just content fingerprinting).
  defp hash_file(path) do
    path
    |> File.read!()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end
end

defmodule Ignite.HTML do
  @moduledoc """
  HTML helpers shared across the framework.

  The most important one is `escape/1`, the single source of truth for
  HTML-entity escaping. The `~F` engine (`Ignite.LiveView.FEExEngine`) uses it
  to auto-escape template values, and application code that builds HTML strings
  by hand should call it on any user- or client-supplied value before
  interpolating it — otherwise an attacker can inject `<script>` (XSS).
  """

  @doc """
  Escapes the five HTML-significant characters (`& < > " '`) so a value can be
  safely interpolated into HTML text or a double-quoted attribute.

  Non-binaries are converted with `to_string/1` first. `nil` becomes an empty
  string, and a `{:safe, value}` tuple (produced by `Ignite.LiveView.raw/1`)
  is passed through unescaped.

  ## Examples

      iex> Ignite.HTML.escape(~s(<script>"x" & 'y'))
      "&lt;script&gt;&quot;x&quot; &amp; &#39;y&#39;"

      iex> Ignite.HTML.escape(nil)
      ""

      iex> Ignite.HTML.escape({:safe, "<b>trusted</b>"})
      "<b>trusted</b>"
  """
  def escape({:safe, value}), do: to_string(value)
  def escape(nil), do: ""

  def escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def escape(value), do: escape(to_string(value))
end

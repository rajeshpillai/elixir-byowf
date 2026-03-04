defmodule Ignite.LiveView.Engine do
  @moduledoc """
  Splits rendered HTML into statics (unchanging parts) and dynamics
  (variable values) for efficient over-the-wire updates.

  Instead of sending full HTML on every update, we:
  1. On mount: send both statics and dynamics → {s: [...], d: [...]}
  2. On event: send only dynamics → {d: [...]}

  The frontend zips statics + dynamics to reconstruct the full HTML.

  ## Example

      Template: "<h1>Count: \#{count}</h1><p>Hello</p>"

      Statics:  ["<h1>Count: ", "</h1><p>Hello</p>"]
      Dynamics: ["42"]

      Reconstructed: "<h1>Count: 42</h1><p>Hello</p>"
  """

  @doc """
  Renders a LiveView module and returns {statics, dynamics}.

  Statics are extracted once (they never change between renders).
  Dynamics are the interpolated values that change on each render.
  """
  def render(view_module, assigns) do
    # Get the full rendered HTML
    html = apply(view_module, :render, [assigns])

    # Split into statics and dynamics using a simple regex approach.
    # We look for our marker pattern to identify dynamic parts.
    # For our simplified version, we use the render function that
    # returns HTML with special markers.
    {statics, dynamics} = split_template(html)

    {statics, dynamics}
  end

  @doc """
  Renders and returns only the dynamic values (for updates).
  """
  def render_dynamics(view_module, assigns) do
    html = apply(view_module, :render, [assigns])
    {_statics, dynamics} = split_template(html)
    dynamics
  end

  # Splits an HTML string by extracting interpolated values.
  #
  # Since Elixir string interpolation happens before we see the result,
  # we use a convention: LiveView render functions return a tagged
  # format that we can split.
  #
  # For our simplified engine, we treat the entire rendered HTML as
  # a single dynamic value. A production engine would compile the EEx
  # template at compile-time to track static vs dynamic parts.
  defp split_template(html) do
    # Simple approach: the entire rendered output is one dynamic chunk
    # wrapped in empty statics.
    {["", ""], [html]}
  end
end

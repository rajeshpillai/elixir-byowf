defmodule Ignite.LiveView.Engine do
  @moduledoc """
  Splits rendered HTML into statics (unchanging parts) and dynamics
  (variable values) for efficient over-the-wire updates.

  Supports two render return types:

  - `%Rendered{}` (from `~L` sigil): real per-expression statics/dynamics.
    Each `<%= expr %>` becomes its own indexed dynamic.

  - `String` (legacy): the entire HTML is treated as a single dynamic,
    wrapped in empty statics `["", ""]`. Backward compatible.

  ## Wire Protocol

  On mount, sends both statics and dynamics:

      {s: ["<h1>Count: ", "</h1>"], d: ["42"]}

  On update, sends only changed dynamics as a sparse map:

      {d: {"0": "43"}}

  Or as a full array when all dynamics changed:

      {d: ["43"]}
  """

  alias Ignite.LiveView.Rendered

  @doc """
  Renders a LiveView module and returns `{statics, dynamics}`.

  Used on mount to send the full initial payload.
  """
  def render(view_module, assigns) do
    result = apply(view_module, :render, [assigns])
    normalize(result)
  end

  @doc """
  Renders and returns only the dynamics list.

  Used when no previous dynamics are available for diffing.
  """
  def render_dynamics(view_module, assigns) do
    result = apply(view_module, :render, [assigns])
    {_statics, dynamics} = normalize(result)
    dynamics
  end

  @doc """
  Computes a sparse diff between old and new dynamics.

  Returns either:
  - A map of `%{"index" => new_value}` for changed indices only (sparse)
  - A list when all dynamics changed (more compact than a full map)
  - An empty map when nothing changed
  """
  def diff(old_dynamics, new_dynamics)
      when is_list(old_dynamics) and is_list(new_dynamics) do
    if length(old_dynamics) != length(new_dynamics) do
      # Structure changed — send full list
      new_dynamics
    else
      changes =
        old_dynamics
        |> Enum.zip(new_dynamics)
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {{old_val, new_val}, idx}, acc ->
          if old_val == new_val do
            acc
          else
            Map.put(acc, Integer.to_string(idx), new_val)
          end
        end)

      if map_size(changes) == length(new_dynamics) do
        # All changed — send as array (more compact)
        new_dynamics
      else
        # Sparse — send as map with only changed indices
        changes
      end
    end
  end

  # --- Normalization ---

  # %Rendered{} from ~L sigil: use statics/dynamics directly
  defp normalize(%Rendered{statics: statics, dynamics: dynamics}) do
    {statics, dynamics}
  end

  # Legacy string: entire HTML is one dynamic
  defp normalize(html) when is_binary(html) do
    {["", ""], [html]}
  end
end

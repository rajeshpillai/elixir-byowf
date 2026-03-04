defmodule Ignite.LiveView.Rendered do
  @moduledoc """
  Holds a pre-split template: static HTML fragments and dynamic values.

  When a LiveView's `render/1` returns a `%Rendered{}`, the engine can
  diff individual dynamics instead of re-sending the full HTML.

  ## Structure

  - `statics` — list of static HTML strings (length N+1, never changes)
  - `dynamics` — list of dynamic string values (length N, changes each render)

  Statics are always one element longer than dynamics. The full HTML is
  reconstructed by interleaving them:

      s[0] ++ d[0] ++ s[1] ++ d[1] ++ ... ++ s[N]

  ## Example

      %Rendered{
        statics: ["<h1>Count: ", "</h1><button>+1</button>"],
        dynamics: ["42"]
      }

      # Reconstructs to: "<h1>Count: 42</h1><button>+1</button>"
  """

  defstruct statics: [], dynamics: []
end

defmodule Ignite.LiveView.EExEngine do
  @moduledoc """
  Custom EEx engine that compiles templates into `%Rendered{}` structs.

  Instead of producing a concatenated string (like the default EEx engine),
  this engine separates the template into compile-time **statics** and
  runtime **dynamics**.

  ## How It Works

  EEx parses a template like `<h1>Count: <%= assigns.count %></h1>` into
  a series of callbacks:

  1. `handle_text` receives `"<h1>Count: "` (static text)
  2. `handle_expr("=", ast)` receives the AST for `assigns.count`
  3. `handle_text` receives `"</h1>"` (more static text)
  4. `handle_body` is called to produce the final compiled code

  We accumulate static text in a buffer and flush it each time we see a
  `<%= %>` expression. The final `handle_body` returns AST that builds
  a `%Rendered{}` struct at runtime — statics are literal strings baked
  into the compiled module, dynamics are evaluated fresh on each render.

  ## Limitations

  Only `<%= expr %>` (output expressions) are supported. Control flow
  like `<% if ... do %>` is not — use inline conditionals instead:

      <%= if assigns.show, do: "visible", else: "hidden" %>
  """

  @behaviour EEx.Engine

  @impl true
  def init(_opts) do
    # State: {reversed_statics, reversed_dynamics, pending_text_buffer}
    {[], [], ""}
  end

  @impl true
  def handle_begin(state), do: state

  @impl true
  def handle_end(state), do: state

  # Elixir >= 1.14 uses handle_text/3 with metadata
  @impl true
  def handle_text(state, _meta, text) do
    {statics, dynamics, pending} = state
    {statics, dynamics, pending <> text}
  end

  @impl true
  def handle_expr(state, "=", expr) do
    {statics, dynamics, pending} = state

    # Flush the pending text buffer as a new static
    # Wrap the expression in to_string/1 so dynamics are always strings
    wrapped = quote do: to_string(unquote(expr))

    {[pending | statics], [wrapped | dynamics], ""}
  end

  def handle_expr(state, _marker, _expr) do
    # Non-output expressions (<% ... %>) are not supported in ~L.
    # Silently pass through — the expression is ignored.
    state
  end

  @impl true
  def handle_body(state) do
    {statics_rev, dynamics_rev, trailing_text} = state

    # Build final lists: statics has one more element than dynamics
    statics = Enum.reverse([trailing_text | statics_rev])
    dynamics_ast = Enum.reverse(dynamics_rev)

    # Return AST that constructs %Rendered{} at runtime
    quote do
      %Ignite.LiveView.Rendered{
        statics: unquote(statics),
        dynamics: unquote(dynamics_ast)
      }
    end
  end
end

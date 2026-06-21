defmodule Security.EscapingTest do
  @moduledoc """
  Regression tests for the ~F migration (security review item A2).

  The sample LiveViews must escape user- and client-supplied values so a
  payload like <script> can never be injected into the rendered HTML.
  """
  use ExUnit.Case, async: true

  alias Ignite.LiveView.Engine

  @xss "<script>alert('xss')</script>"

  # Reconstruct full HTML from {statics, dynamics} the way the client does.
  defp render_html(view, assigns) do
    {statics, dynamics} = Engine.render(view, assigns)

    statics
    |> Enum.zip(dynamics ++ [""])
    |> Enum.map_join("", fn {s, d} -> s <> flatten(d) end)
  end

  defp flatten(d) when is_list(d), do: Enum.map_join(d, "", &flatten/1)
  defp flatten(d), do: to_string(d)

  test "PresenceDemoLive escapes the current username" do
    html = render_html(MyApp.PresenceDemoLive, %{username: @xss, online: %{}})

    refute html =~ @xss
    assert html =~ "&lt;script&gt;"
  end

  test "PresenceDemoLive escapes other users' names in the online list" do
    online = %{@xss => %{joined_at: "2026-01-01 00:00:00"}}
    html = render_html(MyApp.PresenceDemoLive, %{username: "me", online: online})

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "HooksDemoLive escapes client-pushed hook events" do
    assigns = %{server_clicks: 0, copy_text: "hello", hook_events: [@xss]}
    html = render_html(MyApp.HooksDemoLive, assigns)

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "HooksDemoLive escapes copy_text rendered into an attribute" do
    assigns = %{server_clicks: 0, copy_text: ~s|" onmouseover="alert(1)|, hook_events: []}
    html = render_html(MyApp.HooksDemoLive, assigns)

    refute html =~ ~s|onmouseover="alert(1)|
    assert html =~ "&quot;"
  end
end

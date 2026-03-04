defmodule MyApp.PresenceDemoLive do
  @moduledoc """
  "Who's Online" demo using Ignite.Presence.

  Each tab gets a random username, tracks itself, and displays all
  connected users in real time. Close a tab and it disappears from
  every other tab instantly.
  """

  use Ignite.LiveView

  @topic "presence:demo"

  @impl true
  def mount(_params, _session) do
    # Generate a random username for this tab
    username = "user_#{:rand.uniform(9999)}"
    joined_at = DateTime.utc_now() |> DateTime.to_string()

    # Subscribe to presence diffs
    Ignite.PubSub.subscribe(@topic)

    # Track this process
    Ignite.Presence.track(@topic, username, %{joined_at: joined_at})

    # Get the current online list
    online = Ignite.Presence.list(@topic)

    {:ok, %{username: username, online: online}}
  end

  @impl true
  def handle_event(_event, _params, assigns) do
    {:noreply, assigns}
  end

  @impl true
  def handle_info({:presence_diff, _diff}, assigns) do
    # On any join/leave, refresh the full list
    online = Ignite.Presence.list(@topic)
    {:noreply, %{assigns | online: online}}
  end

  @impl true
  def render(assigns) do
    user_count = map_size(assigns.online)

    users_html =
      assigns.online
      |> Enum.sort_by(fn {_k, meta} -> meta.joined_at end)
      |> Enum.map(fn {name, meta} ->
        is_me = name == assigns.username
        badge = if is_me, do: " <span style=\"color:#27ae60;font-weight:bold;\">(you)</span>", else: ""

        """
        <li style="padding:8px 12px;border-bottom:1px solid #eee;display:flex;justify-content:space-between;align-items:center;">
          <span>#{name}#{badge}</span>
          <span style="color:#888;font-size:12px;">joined #{meta.joined_at}</span>
        </li>
        """
      end)
      |> Enum.join("\n")

    ~L"""
    <div id="presence-demo" style="max-width:550px;margin:0 auto;">
      <h1>Who's Online</h1>
      <p style="color:#888;font-size:14px;">
        Open this page in multiple tabs — users appear/disappear in real time
      </p>

      <div style="background:#f0f4ff;padding:12px 16px;border-radius:8px;margin-bottom:16px;">
        You are: <strong><%= assigns.username %></strong>
        &nbsp;|&nbsp;
        Online: <strong><%= user_count %></strong>
      </div>

      <ul style="list-style:none;padding:0;margin:0;background:#fff;border:1px solid #ddd;border-radius:8px;">
        <%= users_html %>
      </ul>

      <div style="margin-top:24px;padding:16px;background:#f9f9f9;border-radius:8px;text-align:left;">
        <strong>How it works:</strong>
        <ul style="margin:8px 0;padding-left:20px;">
          <li>Each tab calls <code>Ignite.Presence.track/3</code> on mount</li>
          <li>Presence uses <code>Process.monitor/1</code> to watch for disconnects</li>
          <li>On join/leave, a <code>{:presence_diff, %{joins, leaves}}</code> is broadcast via PubSub</li>
          <li>When a tab closes, the monitored process dies → auto-untrack → broadcast leave</li>
        </ul>
      </div>

      <div style="margin-top:20px;padding-top:16px;border-top:1px solid #eee;text-align:center;">
        <a href="/" style="margin:0 8px;">Home</a>
        <a href="/shared-counter" ignite-navigate="/shared-counter" style="margin:0 8px;">Shared Counter</a>
      </div>
    </div>
    """
  end
end

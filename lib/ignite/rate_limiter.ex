defmodule Ignite.RateLimiter do
  @moduledoc """
  ETS-based rate limiter with sliding window counters.

  Tracks requests per client IP using an ETS `:bag` table. Each request
  inserts a `{ip, timestamp}` entry. To check the rate, we count entries
  within the current window using `:ets.select_count/2`.

  A GenServer runs periodic cleanup to remove expired entries, preventing
  unbounded memory growth.

  ## Configuration

      config :ignite,
        rate_limit: [
          max_requests: 100,   # requests per window
          window_ms: 60_000    # window size in milliseconds (1 minute)
        ]

  ## Plug Integration

  In your router:

      plug :rate_limit

      def rate_limit(conn), do: Ignite.RateLimiter.call(conn)

  ## Response Headers

  Every response includes rate limit headers:

  - `x-ratelimit-limit` — max requests per window
  - `x-ratelimit-remaining` — requests left in current window
  - `x-ratelimit-reset` — Unix timestamp when the window resets

  When the limit is exceeded, returns `429 Too Many Requests` with a
  `retry-after` header (in seconds).
  """

  use GenServer
  require Logger

  @table :ignite_rate_limiter
  @default_max 100
  @default_window_ms 60_000

  # --- Public API ---

  @doc "Starts the rate limiter GenServer and creates the ETS table."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Rate limit plug entry point.

  Checks the request rate for the client's IP. If within the limit,
  adds rate limit headers and returns the conn (pipeline continues).
  If exceeded, halts the conn with 429.
  """
  def call(conn) do
    config = Application.get_env(:ignite, :rate_limit, [])
    max_requests = Keyword.get(config, :max_requests, @default_max)
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)

    ip = client_ip(conn)
    now = System.monotonic_time(:millisecond)

    # Record this request
    :ets.insert(@table, {ip, now})

    # Count requests in the current window
    cutoff = now - window_ms
    count = count_requests(ip, cutoff)

    remaining = max(max_requests - count, 0)
    retry_after_secs = div(window_ms, 1000)
    reset_unix = System.os_time(:second) + retry_after_secs

    conn = add_rate_limit_headers(conn, max_requests, remaining, reset_unix)

    if count > max_requests do
      Logger.warning(
        "[RateLimiter] Rate limit exceeded for #{ip} " <>
          "(#{count}/#{max_requests} in #{window_ms}ms)"
      )

      conn
      |> add_resp_header("retry-after", Integer.to_string(retry_after_secs))
      |> Ignite.Controller.json(
        %{
          error: "Too Many Requests",
          message: "Rate limit exceeded. Try again in #{retry_after_secs} seconds.",
          retry_after: retry_after_secs
        },
        429
      )
    else
      conn
    end
  end

  @doc """
  Returns the current request count for the given IP within the window.
  Useful for testing and monitoring.
  """
  def get_count(ip) do
    config = Application.get_env(:ignite, :rate_limit, [])
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    cutoff = System.monotonic_time(:millisecond) - window_ms
    count_requests(ip, cutoff)
  end

  @doc """
  Resets the rate limit for a given IP. Useful for testing.
  """
  def reset(ip) do
    :ets.delete(@table, ip)
    :ok
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # :bag allows multiple {ip, timestamp} entries per key
    :ets.new(@table, [
      :named_table,
      :bag,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    config = Application.get_env(:ignite, :rate_limit, [])
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    cutoff = System.monotonic_time(:millisecond) - window_ms

    # Delete all entries older than the window.
    # Match spec: for any {ip, timestamp} where timestamp < cutoff, delete it.
    match_spec = [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}]
    deleted = :ets.select_delete(@table, match_spec)

    if deleted > 0 do
      Logger.debug("[RateLimiter] Cleaned up #{deleted} expired entries")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp count_requests(ip, cutoff) do
    # Count entries for this IP where timestamp >= cutoff (within window)
    match_spec = [{{ip, :"$1"}, [{:>=, :"$1", cutoff}], [true]}]
    :ets.select_count(@table, match_spec)
  end

  defp client_ip(conn) do
    # Check x-forwarded-for first (behind reverse proxy like nginx/CloudFlare)
    case Map.get(conn.headers, "x-forwarded-for") do
      nil ->
        # Fall back to the peer IP extracted by the Cowboy adapter
        Map.get(conn.private, :peer_ip, "unknown")

      forwarded ->
        # x-forwarded-for can contain multiple IPs: "client, proxy1, proxy2"
        # The first one is the real client IP
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp add_rate_limit_headers(conn, limit, remaining, reset_unix) do
    new_headers =
      conn.resp_headers
      |> Map.put("x-ratelimit-limit", Integer.to_string(limit))
      |> Map.put("x-ratelimit-remaining", Integer.to_string(remaining))
      |> Map.put("x-ratelimit-reset", Integer.to_string(reset_unix))

    %Ignite.Conn{conn | resp_headers: new_headers}
  end

  defp add_resp_header(conn, key, value) do
    new_headers = Map.put(conn.resp_headers, key, value)
    %Ignite.Conn{conn | resp_headers: new_headers}
  end

  defp schedule_cleanup do
    config = Application.get_env(:ignite, :rate_limit, [])
    window_ms = Keyword.get(config, :window_ms, @default_window_ms)
    # Clean up at the window interval, capped at 60s
    interval = min(window_ms, 60_000)
    Process.send_after(self(), :cleanup, interval)
  end
end

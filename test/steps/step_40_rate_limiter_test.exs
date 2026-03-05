defmodule Step40.RateLimiterTest do
  @moduledoc """
  Step 40 — Rate Limiter

  TDD spec: Rate limiting should track requests per IP using
  ETS, enforce a max-per-window limit, return rate limit headers,
  and respond with 429 when exceeded.
  """
  use ExUnit.Case

  alias Ignite.RateLimiter

  # Use a unique IP per test to avoid cross-contamination
  defp test_ip, do: "test-#{System.unique_integer([:positive])}"

  defp new_conn(ip) do
    %Ignite.Conn{
      method: "GET",
      path: "/",
      headers: %{},
      private: %{peer_ip: ip}
    }
  end

  # Small sleep to ensure different monotonic timestamps.
  # ETS :bag deduplicates identical {ip, timestamp} entries,
  # so we need distinct millisecond values.
  defp tick, do: Process.sleep(2)

  setup do
    Application.put_env(:ignite, :rate_limit, max_requests: 3, window_ms: 60_000)
    on_exit(fn -> Application.delete_env(:ignite, :rate_limit) end)
  end

  describe "call/1 within limit" do
    test "allows requests under the limit" do
      ip = test_ip()
      conn = RateLimiter.call(new_conn(ip))

      refute conn.halted
      assert conn.resp_headers["x-ratelimit-limit"] == "3"
    end

    test "sets rate limit headers" do
      ip = test_ip()
      conn = RateLimiter.call(new_conn(ip))

      assert conn.resp_headers["x-ratelimit-limit"] == "3"
      assert is_binary(conn.resp_headers["x-ratelimit-remaining"])
      assert is_binary(conn.resp_headers["x-ratelimit-reset"])
    end

    test "remaining decreases with each request" do
      ip = test_ip()
      conn1 = RateLimiter.call(new_conn(ip))
      tick()
      conn2 = RateLimiter.call(new_conn(ip))

      r1 = String.to_integer(conn1.resp_headers["x-ratelimit-remaining"])
      r2 = String.to_integer(conn2.resp_headers["x-ratelimit-remaining"])
      assert r2 < r1
    end
  end

  describe "call/1 over limit" do
    test "returns 429 when limit exceeded" do
      ip = test_ip()

      # Make 4 requests (limit is 3, trigger is count > 3)
      for _ <- 1..3 do
        RateLimiter.call(new_conn(ip))
        tick()
      end
      conn = RateLimiter.call(new_conn(ip))

      assert conn.status == 429
      assert conn.halted == true
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Too Many Requests"
    end

    test "includes retry-after header" do
      ip = test_ip()
      for _ <- 1..3 do
        RateLimiter.call(new_conn(ip))
        tick()
      end
      conn = RateLimiter.call(new_conn(ip))

      assert is_binary(conn.resp_headers["retry-after"])
    end
  end

  describe "get_count/1" do
    test "returns 0 for unknown IP" do
      assert RateLimiter.get_count(test_ip()) == 0
    end

    test "returns request count" do
      ip = test_ip()
      RateLimiter.call(new_conn(ip))
      tick()
      RateLimiter.call(new_conn(ip))
      assert RateLimiter.get_count(ip) == 2
    end
  end

  describe "reset/1" do
    test "clears rate limit for an IP" do
      ip = test_ip()
      RateLimiter.call(new_conn(ip))
      assert RateLimiter.get_count(ip) > 0

      RateLimiter.reset(ip)
      assert RateLimiter.get_count(ip) == 0
    end
  end

  describe "x-forwarded-for support" do
    test "uses x-forwarded-for header when present" do
      ip = test_ip()
      conn = %Ignite.Conn{
        method: "GET",
        path: "/",
        headers: %{"x-forwarded-for" => ip <> ", proxy1"},
        private: %{peer_ip: "proxy-ip"}
      }

      RateLimiter.call(conn)
      assert RateLimiter.get_count(ip) == 1
      assert RateLimiter.get_count("proxy-ip") == 0
    end
  end
end

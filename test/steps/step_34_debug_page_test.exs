defmodule Step34.DebugPageTest do
  @moduledoc """
  Step 34 — Debug Error Page

  TDD spec: In dev mode, errors should render a rich debug page
  with exception details, stacktrace, and request context.
  In production, only a generic error page should be shown.
  """
  use ExUnit.Case

  alias Ignite.DebugPage

  defp sample_conn do
    %Ignite.Conn{
      method: "GET",
      path: "/crash",
      headers: %{"host" => "localhost:4000", "accept" => "text/html"},
      params: %{"id" => "42"},
      session: %{"user_id" => 1}
    }
  end

  defp sample_error do
    try do
      raise RuntimeError, "something broke"
    rescue
      e -> {e, __STACKTRACE__}
    end
  end

  describe "dev mode rendering" do
    setup do
      # Ensure dev mode (not :prod)
      prev = Application.get_env(:ignite, :env)
      Application.put_env(:ignite, :env, :dev)
      on_exit(fn ->
        if prev, do: Application.put_env(:ignite, :env, prev), else: Application.delete_env(:ignite, :env)
      end)
    end

    test "includes exception type" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      assert html =~ "RuntimeError"
    end

    test "includes exception message" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      assert html =~ "something broke"
    end

    test "includes stacktrace" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      assert html =~ "Stacktrace"
    end

    test "includes request details" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      assert html =~ "GET"
      assert html =~ "/crash"
    end

    test "HTML-escapes exception messages" do
      try do
        raise RuntimeError, "user input: <script>alert('xss')</script>"
      rescue
        e ->
          html = DebugPage.render(e, __STACKTRACE__, sample_conn())
          refute html =~ "<script>alert"
          assert html =~ "&lt;script&gt;"
      end
    end
  end

  describe "production mode rendering" do
    setup do
      prev = Application.get_env(:ignite, :env)
      Application.put_env(:ignite, :env, :prod)
      on_exit(fn ->
        if prev, do: Application.put_env(:ignite, :env, prev), else: Application.delete_env(:ignite, :env)
      end)
    end

    test "shows generic error page" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      assert html =~ "Something went wrong"
    end

    test "does not leak exception details" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      refute html =~ "something broke"
      refute html =~ "RuntimeError"
    end

    test "does not leak request data" do
      {error, trace} = sample_error()
      html = DebugPage.render(error, trace, sample_conn())
      refute html =~ "/crash"
      refute html =~ "user_id"
    end
  end
end

defmodule Ignite.HTMLTest do
  use ExUnit.Case, async: true

  doctest Ignite.HTML

  describe "escape/1" do
    test "escapes the five HTML-significant characters" do
      assert Ignite.HTML.escape(~s(<a href="x">&'</a>)) ==
               "&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;"
    end

    test "neutralizes a script-injection payload" do
      escaped = Ignite.HTML.escape("<script>alert(1)</script>")
      refute escaped =~ "<script>"
      assert escaped =~ "&lt;script&gt;"
    end

    test "nil becomes an empty string" do
      assert Ignite.HTML.escape(nil) == ""
    end

    test "non-binaries are stringified first" do
      assert Ignite.HTML.escape(42) == "42"
    end

    test "raw/{:safe, _} values pass through unescaped" do
      assert Ignite.HTML.escape({:safe, "<b>ok</b>"}) == "<b>ok</b>"
    end
  end
end

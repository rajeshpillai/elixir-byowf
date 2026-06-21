defmodule Ignite.UploadSecurityTest do
  @moduledoc """
  Regression test for the upload-name atom-exhaustion DoS (review item A1).

  The LiveView WebSocket handler must never call String.to_atom/1 on the
  client-supplied upload name. An unregistered name must be ignored without
  creating a new atom (atoms are never garbage-collected).
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ignite.LiveView.Handler

  test "an unknown upload name is ignored and creates no new atom" do
    # No uploads configured, so any client name is unknown.
    state = %{view: __MODULE__, assigns: %{__uploads__: %{}}, prev_dynamics: []}

    # A name that is overwhelmingly unlikely to already exist as an atom.
    bogus = "nm_atom_dos_probe_zzx_4f9a1c"

    json =
      Jason.encode!(%{
        "event" => "__upload_validate__",
        "params" => %{"name" => bogus, "entries" => []}
      })

    result =
      capture_log(fn ->
        assert {:ok, ^state} = Handler.websocket_handle({:text, json}, state)
      end)

    assert result =~ "unknown upload"

    # The precise invariant: the client-supplied name never became an atom.
    # (An absolute atom-count delta is unreliable here — unrelated first-run
    # module loading creates atoms — so we assert directly on the name.)
    assert_raise ArgumentError, fn -> String.to_existing_atom(bogus) end
  end

  test "an unknown upload complete event is also ignored without crashing" do
    state = %{view: __MODULE__, assigns: %{__uploads__: %{}}, prev_dynamics: []}

    json =
      Jason.encode!(%{
        "event" => "__upload_complete__",
        "params" => %{"name" => "still_not_registered_atom_qq", "ref" => "0"}
      })

    capture_log(fn ->
      assert {:ok, ^state} = Handler.websocket_handle({:text, json}, state)
    end)
  end
end

defmodule GnomeGarden.Agents.RunFailureTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.RunFailure

  test "classifies runtime timeouts as retryable" do
    details = RunFailure.details("request timed out", phase: :runtime)

    assert details["category"] == "timeout"
    assert details["phase"] == "runtime"
    assert details["retryable"] == true
    assert RunFailure.label(details["category"]) == "Timed Out"
  end

  test "classifies startup failures separately" do
    details = RunFailure.details("runtime service unavailable", phase: :startup)

    assert details["category"] == "runtime_start"
    assert details["retryable"] == true
    assert RunFailure.recovery_hint(details["category"]) =~ "runtime can start"
  end

  test "keeps validation failures non-retryable until repaired" do
    details = RunFailure.details("invalid deployment configuration", phase: :runtime)

    assert details["category"] == "validation"
    assert details["retryable"] == false
  end
end

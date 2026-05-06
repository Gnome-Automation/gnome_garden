defmodule GnomeGarden.Finance.FinanceSequenceTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Finance

  test "next_sequence_value increments sequentially" do
    v1 = Finance.next_sequence_value("credit_notes")
    v2 = Finance.next_sequence_value("credit_notes")
    assert v2 == v1 + 1
  end

  test "format_credit_note_number pads to 4 digits" do
    assert Finance.format_credit_note_number(1) == "CN-0001"
    assert Finance.format_credit_note_number(42) == "CN-0042"
    assert Finance.format_credit_note_number(1000) == "CN-1000"
  end
end

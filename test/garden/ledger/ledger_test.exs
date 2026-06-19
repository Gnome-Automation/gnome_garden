defmodule GnomeGarden.LedgerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Ledger

  defp account!(number) do
    {:ok, account} = Ledger.get_account_by_number(number)
    account
  end

  defp balanced_lines do
    [
      %{account_id: account!("1000").id, debit: Money.new!(:USD, "100")},
      %{account_id: account!("1100").id, credit: Money.new!(:USD, "100")}
    ]
  end

  describe "chart of accounts" do
    test "is seeded with system accounts" do
      assert %{} = account!("1100")
      assert account!("1100").name == "Accounts Receivable"
      assert account!("4000").type == :revenue
    end

    test "system accounts cannot be destroyed" do
      assert {:error, _} = Ledger.destroy_account(account!("1100"))
    end
  end

  describe "posting journal entries" do
    test "a balanced entry posts and is numbered" do
      {:ok, entry} =
        Ledger.post_journal_entry(%{
          date: Date.utc_today(),
          description: "Test",
          entry_type: :manual,
          lines: balanced_lines()
        })

      assert entry.status == :posted
      assert entry.entry_number =~ ~r/^JE-\d+$/

      entry = Ash.load!(entry, [:total_debits, :total_credits])
      assert Money.equal?(entry.total_debits, Money.new!(:USD, "100"))
      assert Money.equal?(entry.total_credits, Money.new!(:USD, "100"))
    end

    test "an unbalanced entry is rejected" do
      lines = [
        %{account_id: account!("1000").id, debit: Money.new!(:USD, "100")},
        %{account_id: account!("1100").id, credit: Money.new!(:USD, "50")}
      ]

      assert {:error, _} =
               Ledger.post_journal_entry(%{
                 date: Date.utc_today(),
                 description: "Unbalanced",
                 entry_type: :manual,
                 lines: lines
               })
    end

    test "an empty entry is rejected" do
      assert {:error, _} =
               Ledger.post_journal_entry(%{
                 date: Date.utc_today(),
                 description: "Empty",
                 entry_type: :manual,
                 lines: []
               })
    end

    test "a line carrying both a debit and a credit is rejected" do
      lines = [
        %{account_id: account!("1000").id, debit: Money.new!(:USD, "100"), credit: Money.new!(:USD, "100")},
        %{account_id: account!("1100").id, credit: Money.new!(:USD, "100")}
      ]

      assert {:error, _} =
               Ledger.post_journal_entry(%{date: Date.utc_today(), description: "Two-sided", entry_type: :manual, lines: lines})
    end

    test "a negative line amount is rejected" do
      lines = [
        %{account_id: account!("1000").id, debit: Money.new!(:USD, "-100")},
        %{account_id: account!("1100").id, credit: Money.new!(:USD, "-100")}
      ]

      assert {:error, _} =
               Ledger.post_journal_entry(%{date: Date.utc_today(), description: "Negative", entry_type: :manual, lines: lines})
    end

    test "a line with neither a debit nor a credit is rejected" do
      lines = [
        %{account_id: account!("1000").id},
        %{account_id: account!("1100").id, credit: Money.new!(:USD, "100")}
      ]

      assert {:error, _} =
               Ledger.post_journal_entry(%{date: Date.utc_today(), description: "Empty line", entry_type: :manual, lines: lines})
    end
  end

  describe "immutability of posted entries" do
    test "a posted journal entry exposes no update or destroy action" do
      actions = Ash.Resource.Info.actions(GnomeGarden.Ledger.JournalEntry)
      names = Enum.map(actions, & &1.name)

      # The only update is :post (draft -> posted, accepting no field changes);
      # there is no destroy and no action that edits a posted entry's content.
      refute :destroy in names
      assert Enum.filter(actions, &(&1.type == :update)) |> Enum.map(& &1.name) == [:post]
      assert Ash.Resource.Info.action(GnomeGarden.Ledger.JournalEntry, :post).accept == []
    end

    test "journal lines expose no update or destroy action" do
      names = GnomeGarden.Ledger.JournalLine |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)
      refute :update in names
      refute :destroy in names
    end
  end

  describe "reversal" do
    test "reverses a posted entry with debit/credit flipped" do
      {:ok, original} =
        Ledger.post_journal_entry(%{
          date: Date.utc_today(),
          description: "Original",
          entry_type: :manual,
          lines: balanced_lines()
        })

      {:ok, reversal} = Ledger.reverse_journal_entry(original.id)
      reversal = Ash.load!(reversal, [:total_debits, :total_credits, journal_lines: [:account]])

      assert reversal.entry_type == :reversal
      assert reversal.reference_id == original.id
      assert Money.equal?(reversal.total_debits, Money.new!(:USD, "100"))

      # The reversal debits 1100 (was credited) and credits 1000 (was debited).
      by_account = Map.new(reversal.journal_lines, &{&1.account.number, &1})
      assert by_account["1100"].debit
      assert by_account["1000"].credit
    end

    test "the same entry cannot be reversed twice" do
      {:ok, original} =
        Ledger.post_journal_entry(%{
          date: Date.utc_today(),
          description: "Original",
          entry_type: :manual,
          lines: balanced_lines()
        })

      assert {:ok, _} = Ledger.reverse_journal_entry(original.id)
      assert {:error, _} = Ledger.reverse_journal_entry(original.id)
    end
  end
end

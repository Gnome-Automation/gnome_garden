defmodule GnomeGarden.Ledger do
  @moduledoc """
  Double-entry general ledger — the immutable accounting core.

  This domain owns the only balance-bearing records in the system: a chart of
  `Account`s and balanced `JournalEntry`/`JournalLine` postings. Every financial
  event in `GnomeGarden.Finance` (invoices, payments, retainers, vendor bills)
  posts INTO this ledger via journal entries; the ledger itself knows nothing
  about those concepts.

  Posted entries are immutable and append-only — corrections are made with new
  reversing entries, never by editing a posted entry.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Ledger.Account do
      define :list_accounts, action: :read
      define :list_active_accounts, action: :active
      define :get_account, action: :read, get_by: [:id]
      define :get_account_by_number, action: :read, get_by: [:number]
      define :create_account, action: :create
      define :update_account, action: :update
      define :destroy_account, action: :destroy

      define :build_trial_balance, action: :trial_balance
      define :build_balance_sheet, action: :balance_sheet
      define :build_income_statement, action: :income_statement, args: [:from, :to]
    end

    resource GnomeGarden.Ledger.JournalEntry do
      define :list_journal_entries, action: :read
      define :list_posted_journal_entries, action: :posted
      define :get_journal_entry, action: :read, get_by: [:id]

      define :list_journal_entries_for_reference,
        action: :for_reference,
        args: [:reference_type, :reference_id]

      define :list_posted_journal_entries_through,
        action: :posted_through,
        args: [:as_of]

      define :list_posted_journal_entries_between,
        action: :posted_between,
        args: [:from, :to]

      define :create_journal_entry_draft, action: :create
      define :post_journal_entry, action: :post_entry
      define :post_draft_journal_entry, action: :post
      define :reverse_journal_entry, action: :reverse, args: [:original_entry_id]
    end

    resource GnomeGarden.Ledger.JournalLine do
      define :list_journal_lines, action: :read

      define :list_journal_lines_for_entry,
        action: :for_entry,
        args: [:journal_entry_id]
    end
  end
end

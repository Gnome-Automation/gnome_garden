defmodule GnomeGarden.Finance.GLPoster do
  @moduledoc """
  Auto-posting logic for the General Ledger.

  Called from Ash notifiers on financial events. Each function looks up the
  required system accounts, builds a journal entry + lines, and posts immediately.

  GL posting failures never block the primary transaction — a warning is logged
  and `:ok` is returned so invoicing/payments continue unaffected.
  """

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance

  # --- Public API ---

  def post_invoice_issued(invoice) do
    with {:ok, ar} <- get_account(1100),
         {:ok, revenue} <- get_account(4000) do
      subtotal = invoice.subtotal || invoice.total_amount
      tax_total = invoice.tax_total || Decimal.new("0")
      tax_rate = invoice.tax_rate || Decimal.new("0")

      lines =
        if Decimal.positive?(tax_rate) && Decimal.positive?(tax_total) do
          {:ok, tax_payable} = get_account(2200)

          [
            %{account_id: ar.id, debit: invoice.total_amount, description: "AR — invoice issued"},
            %{account_id: revenue.id, credit: subtotal, description: "Service revenue"},
            %{account_id: tax_payable.id, credit: tax_total, description: "Sales tax payable"}
          ]
        else
          [
            %{account_id: ar.id, debit: invoice.total_amount, description: "AR — invoice issued"},
            %{account_id: revenue.id, credit: invoice.total_amount, description: "Service revenue"}
          ]
        end

      post_entry(%{
        date: invoice.issued_on || Date.utc_today(),
        description: "Invoice issued — #{invoice.invoice_number}",
        entry_type: :invoice_issued,
        reference_id: invoice.id,
        reference_type: "invoice",
        lines: lines
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping invoice_issued GL entry")
        :ok
    end
  end

  def post_payment_received(payment_application) do
    with {:ok, cash} <- get_account(1000),
         {:ok, ar} <- get_account(1100) do
      post_entry(%{
        date: payment_application.applied_on || Date.utc_today(),
        description: "Payment received — matched to invoice",
        entry_type: :payment_received,
        reference_id: payment_application.id,
        reference_type: "payment",
        lines: [
          %{account_id: cash.id, debit: payment_application.amount, description: "Cash received"},
          %{account_id: ar.id, credit: payment_application.amount, description: "AR cleared"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping payment_received GL entry")
        :ok
    end
  end

  def post_credit_note_issued(credit_note, invoice) do
    # Skip if the parent invoice is voided — the void JE already reversed revenue.
    # Issuing the auto-created draft CN from a void should not create a second reversal.
    if invoice.status == :void do
      :ok
    else
      with {:ok, revenue} <- get_account(4000),
           {:ok, ar} <- get_account(1100) do
        subtotal = invoice.subtotal || invoice.total_amount
        tax_total = invoice.tax_total || Decimal.new("0")

        lines =
          if Decimal.positive?(tax_total) do
            {:ok, tax_payable} = get_account(2200)

            [
              %{account_id: revenue.id, debit: subtotal, description: "Revenue reversed"},
              %{
                account_id: tax_payable.id,
                debit: tax_total,
                description: "Tax payable reversed"
              },
              %{
                account_id: ar.id,
                credit: credit_note.total_amount,
                description: "AR credit note"
              }
            ]
          else
            [
              %{
                account_id: revenue.id,
                debit: credit_note.total_amount,
                description: "Revenue reversed"
              },
              %{
                account_id: ar.id,
                credit: credit_note.total_amount,
                description: "AR credit note"
              }
            ]
          end

        post_entry(%{
          date: credit_note.issued_on || Date.utc_today(),
          description: "Credit note issued — #{credit_note.credit_note_number}",
          entry_type: :credit_note_issued,
          reference_id: credit_note.id,
          reference_type: "credit_note",
          lines: lines
        })
      else
        {:missing, number} ->
          Logger.warning(
            "GLPoster: account #{number} not found, skipping credit_note_issued GL entry"
          )

          :ok
      end
    end
  end

  def post_invoice_voided(invoice, prior_status) do
    # Only reverse if the invoice was previously issued (had a GL entry to reverse)
    if prior_status == :draft do
      :ok
    else
      with {:ok, revenue} <- get_account(4000),
           {:ok, ar} <- get_account(1100) do
        subtotal = invoice.subtotal || invoice.total_amount
        tax_total = invoice.tax_total || Decimal.new("0")

        lines =
          if Decimal.positive?(tax_total) do
            {:ok, tax_payable} = get_account(2200)

            [
              %{account_id: revenue.id, debit: subtotal, description: "Revenue reversed — void"},
              %{
                account_id: tax_payable.id,
                debit: tax_total,
                description: "Tax payable reversed — void"
              },
              %{account_id: ar.id, credit: invoice.total_amount, description: "AR reversed — void"}
            ]
          else
            [
              %{
                account_id: revenue.id,
                debit: invoice.total_amount,
                description: "Revenue reversed — void"
              },
              %{account_id: ar.id, credit: invoice.total_amount, description: "AR reversed — void"}
            ]
          end

        post_entry(%{
          date: Date.utc_today(),
          description: "Invoice voided — #{invoice.invoice_number}",
          entry_type: :invoice_voided,
          reference_id: invoice.id,
          reference_type: "invoice",
          lines: lines
        })
      else
        {:missing, number} ->
          Logger.warning(
            "GLPoster: account #{number} not found, skipping invoice_voided GL entry"
          )

          :ok
      end
    end
  end

  def post_invoice_written_off(invoice, write_off_amount) do
    with {:ok, bad_debt} <- get_account(5950),
         {:ok, ar} <- get_account(1100) do
      post_entry(%{
        date: Date.utc_today(),
        description: "Invoice written off — #{invoice.invoice_number}",
        entry_type: :invoice_written_off,
        reference_id: invoice.id,
        reference_type: "invoice",
        lines: [
          %{account_id: bad_debt.id, debit: write_off_amount, description: "Bad debt expense"},
          %{account_id: ar.id, credit: write_off_amount, description: "AR written off"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning(
          "GLPoster: account #{number} not found, skipping invoice_written_off GL entry"
        )

        :ok
    end
  end

  def post_expense_approved(expense) do
    account_number = expense_account_number(expense.category)

    with {:ok, expense_account} <- get_account(account_number),
         {:ok, ap} <- get_account(2000) do
      post_entry(%{
        date: Date.utc_today(),
        description: "Expense approved — #{expense.description || expense.category}",
        entry_type: :expense_approved,
        reference_id: expense.id,
        reference_type: "expense",
        lines: [
          %{
            account_id: expense_account.id,
            debit: expense.amount,
            description: "#{expense.category} expense"
          },
          %{account_id: ap.id, credit: expense.amount, description: "Accounts payable"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning(
          "GLPoster: account #{number} not found, skipping expense_approved GL entry"
        )

        :ok
    end
  end

  def post_retainer_received(retainer) do
    with {:ok, cash} <- get_account(1000),
         {:ok, unearned} <- get_account(2300) do
      post_entry(%{
        date: retainer.received_on || Date.utc_today(),
        description: "Retainer received — #{retainer.retainer_number}",
        entry_type: :retainer_received,
        reference_id: retainer.id,
        reference_type: "retainer",
        lines: [
          %{account_id: cash.id, debit: retainer.amount, description: "Cash received — retainer"},
          %{account_id: unearned.id, credit: retainer.amount, description: "Unearned revenue"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping retainer_received GL entry")
        :ok
    end
  end

  def post_retainer_applied(application) do
    with {:ok, unearned} <- get_account(2300),
         {:ok, ar} <- get_account(1100) do
      post_entry(%{
        date: application.applied_on || Date.utc_today(),
        description: "Retainer applied to invoice",
        entry_type: :retainer_applied,
        reference_id: application.id,
        reference_type: "retainer_application",
        lines: [
          %{account_id: unearned.id, debit: application.amount, description: "Unearned revenue earned"},
          %{account_id: ar.id, credit: application.amount, description: "AR reduced — retainer applied"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping retainer_applied GL entry")
        :ok
    end
  end

  def post_retainer_unapplied(application) do
    with {:ok, ar} <- get_account(1100),
         {:ok, unearned} <- get_account(2300) do
      post_entry(%{
        date: Date.utc_today(),
        description: "Retainer application reversed",
        entry_type: :retainer_unapplied,
        reference_id: application.id,
        reference_type: "retainer_application",
        lines: [
          %{account_id: ar.id, debit: application.amount, description: "AR restored — retainer unapplied"},
          %{account_id: unearned.id, credit: application.amount, description: "Unearned revenue restored"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping retainer_unapplied GL entry")
        :ok
    end
  end

  def post_retainer_voided(retainer) do
    with {:ok, unearned} <- get_account(2300),
         {:ok, cash} <- get_account(1000) do
      post_entry(%{
        date: Date.utc_today(),
        description: "Retainer voided — #{retainer.retainer_number}",
        entry_type: :retainer_voided,
        reference_id: retainer.id,
        reference_type: "retainer",
        lines: [
          %{account_id: unearned.id, debit: retainer.amount, description: "Unearned revenue reversed"},
          %{account_id: cash.id, credit: retainer.amount, description: "Cash returned"}
        ]
      })
    else
      {:missing, number} ->
        Logger.warning("GLPoster: account #{number} not found, skipping retainer_voided GL entry")
        :ok
    end
  end

  # --- Private helpers ---

  defp get_account(number) do
    case Finance.get_account_by_number(number, authorize?: false) do
      {:ok, account} -> {:ok, account}
      _ -> {:missing, number}
    end
  end

  defp post_entry(%{lines: lines} = attrs) do
    entry_attrs = Map.drop(attrs, [:lines])

    try do
      {:ok, entry} = Finance.create_journal_entry(entry_attrs, authorize?: false)

      Enum.each(lines, fn line_attrs ->
        {:ok, _} =
          Finance.create_journal_entry_line(
            Map.put(line_attrs, :journal_entry_id, entry.id),
            authorize?: false
          )
      end)

      # Reload with lines before posting (post action reads lines from loaded data)
      {:ok, entry_with_lines} =
        Finance.get_journal_entry(entry.id, authorize?: false, load: [:lines])

      {:ok, _} = Finance.post_journal_entry(entry_with_lines, authorize?: false)
      :ok
    rescue
      e ->
        Logger.warning("GLPoster: failed to post GL entry: #{inspect(e)}")
        :ok
    end
  end

  defp expense_account_number(:materials), do: 5600
  defp expense_account_number(:equipment), do: 5700
  defp expense_account_number(:travel), do: 5900
  defp expense_account_number(:lodging), do: 5910
  defp expense_account_number(:meals), do: 5910
  defp expense_account_number(:software), do: 5200
  defp expense_account_number(_), do: 5500
end

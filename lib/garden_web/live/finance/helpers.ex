defmodule GnomeGardenWeb.Finance.Helpers do
  @moduledoc false

  def bank_transaction_category_options do
    [
      {"Customer payment", :customer_payment},
      {"Vendor payment", :vendor_payment},
      {"Bank fee", :bank_fee},
      {"Internal transfer", :internal_transfer},
      {"Misc income", :misc_income},
      {"Refund", :refund},
      {"Interest income", :interest_income},
      {"Owner draw", :owner_draw},
      {"Payroll", :payroll},
      {"Tax", :tax},
      {"Unknown", :unknown},
      {"Other", :other}
    ]
  end

  def format_atom(nil), do: "-"

  def format_atom(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_amount(nil), do: "-"

  def format_amount(%Decimal{} = amount),
    do: "$#{Decimal.round(amount, 2) |> Decimal.to_string()}"

  def format_amount(amount) when is_number(amount), do: "$#{amount}"

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  def format_minutes(nil), do: "-"
  def format_minutes(value) when is_integer(value), do: "#{value} min"

  def display_email(value, fallback \\ "-")
  def display_email(nil, fallback), do: fallback
  def display_email(%Ash.NotLoaded{}, fallback), do: fallback
  def display_email(%{email: nil}, fallback), do: fallback
  def display_email(%{email: email}, _fallback), do: to_string(email)

  def display_team_member(value, fallback \\ "-")
  def display_team_member(nil, fallback), do: fallback
  def display_team_member(%Ash.NotLoaded{}, fallback), do: fallback
  def display_team_member(%{display_name: nil}, fallback), do: fallback
  def display_team_member(%{display_name: display_name}, _fallback), do: display_name

  def sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end

  def bank_transaction_counterparty(transaction),
    do: transaction.counterparty_name || transaction.description || "Unknown counterparty"

  def bank_amount_classes(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new(0)) == :gt do
      "font-medium text-success"
    else
      "font-medium text-error"
    end
  end

  def bank_amount_classes(_), do: "font-medium"

  def bank_transaction_status_variant(:posted), do: :success
  def bank_transaction_status_variant(:pending), do: :warning
  def bank_transaction_status_variant(:failed), do: :error
  def bank_transaction_status_variant(_), do: :default

  def bank_review_status_variant(:needs_review), do: :warning
  def bank_review_status_variant(:auto_matched), do: :info
  def bank_review_status_variant(:reviewed), do: :success
  def bank_review_status_variant(:ignored), do: :default
  def bank_review_status_variant(_), do: :default

  def bank_match_status_variant(:matched), do: :success
  def bank_match_status_variant(:suggested), do: :warning
  def bank_match_status_variant(:not_matchable), do: :default
  def bank_match_status_variant(_), do: :error

  def bank_match_status_label(:matched), do: "Matched"
  def bank_match_status_label(:suggested), do: "Suggested"
  def bank_match_status_label(:not_matchable), do: "Not matchable"
  def bank_match_status_label(_), do: "Unmatched"
end

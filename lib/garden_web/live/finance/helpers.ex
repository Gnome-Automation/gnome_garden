defmodule GnomeGardenWeb.Finance.Helpers do
  @moduledoc false

  def format_atom(nil), do: "-"

  def format_atom(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_amount(nil), do: "-"

  def format_amount(%Money{} = amount), do: Money.to_string!(amount)

  def format_amount(%Decimal{} = amount),
    do: "$#{Decimal.round(amount, 2) |> Decimal.to_string()}"

  def format_amount(amount) when is_number(amount), do: "$#{amount}"

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  def format_minutes(nil), do: "-"
  def format_minutes(value) when is_integer(value), do: "#{value} min"

  # Match confidence is stored as a 0..1 decimal probability; show it as a percent.
  def format_confidence(nil), do: "-"

  def format_confidence(%Decimal{} = confidence) do
    pct = confidence |> Decimal.mult(Decimal.new(100)) |> Decimal.round(0) |> Decimal.to_integer()
    "#{pct}% match"
  end

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
    records
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> sum_values()
  end

  defp sum_values([]), do: Decimal.new(0)

  defp sum_values([%Money{} = first | rest]),
    do: Enum.reduce(rest, first, fn money, total -> Money.add!(total, money) end)

  defp sum_values(values),
    do: Enum.reduce(values, Decimal.new(0), fn value, total -> Decimal.add(total, value) end)

  # --- Banking display helpers (adapted to the Banking domain's enums) ---

  def bank_transaction_counterparty(transaction),
    do: transaction.counterparty_name || transaction.description || "Unknown counterparty"

  def bank_amount_classes(%Decimal{} = amount) do
    if Decimal.compare(amount, Decimal.new(0)) == :gt,
      do: "font-medium text-success",
      else: "font-medium text-error"
  end

  def bank_amount_classes(_), do: "font-medium"

  # provider status: pending | sent | cancelled | failed
  def bank_transaction_status_variant(:sent), do: :success
  def bank_transaction_status_variant(:pending), do: :warning
  def bank_transaction_status_variant(:failed), do: :error
  def bank_transaction_status_variant(:cancelled), do: :default
  def bank_transaction_status_variant(_), do: :default

  # review_status: unreviewed | reviewed | ignored | matched
  def bank_review_status_variant(:unreviewed), do: :warning
  def bank_review_status_variant(:matched), do: :info
  def bank_review_status_variant(:reviewed), do: :success
  def bank_review_status_variant(:ignored), do: :default
  def bank_review_status_variant(_), do: :default

  # match status: proposed | accepted | rejected | superseded
  def bank_match_status_variant(:accepted), do: :success
  def bank_match_status_variant(:proposed), do: :warning
  def bank_match_status_variant(:superseded), do: :default
  def bank_match_status_variant(:rejected), do: :error
  def bank_match_status_variant(_), do: :error

  def bank_match_status_label(:accepted), do: "Accepted"
  def bank_match_status_label(:proposed), do: "Proposed"
  def bank_match_status_label(:rejected), do: "Rejected"
  def bank_match_status_label(:superseded), do: "Superseded"
  def bank_match_status_label(_), do: "Unmatched"

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
end

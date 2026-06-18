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
end

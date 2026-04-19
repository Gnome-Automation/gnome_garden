defmodule GnomeGardenWeb.Execution.Helpers do
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
  def display_email(%{email: email}, _fallback), do: email

  def display_name(value, fallback \\ "-")
  def display_name(nil, fallback), do: fallback
  def display_name(%Ash.NotLoaded{}, fallback), do: fallback
  def display_name(%{name: nil}, fallback), do: fallback
  def display_name(%{name: name}, _fallback), do: name

  def display_title(value, fallback \\ "-")
  def display_title(nil, fallback), do: fallback
  def display_title(%Ash.NotLoaded{}, fallback), do: fallback
  def display_title(%{title: nil}, fallback), do: fallback
  def display_title(%{title: title}, _fallback), do: title

  def sum_amounts(records, field) do
    Enum.reduce(records, Decimal.new(0), fn record, total ->
      Decimal.add(total, Map.get(record, field) || Decimal.new(0))
    end)
  end
end

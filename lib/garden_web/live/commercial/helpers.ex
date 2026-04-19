defmodule GnomeGardenWeb.Commercial.Helpers do
  @moduledoc """
  Shared formatting and badge helpers for commercial LiveViews.
  """

  def format_atom(nil), do: "-"

  def format_atom(atom),
    do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
  def format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  def format_amount(nil), do: "-"

  def format_amount(%Decimal{} = amount),
    do: "$#{Decimal.round(amount, 2) |> Decimal.to_string()}"

  def format_amount(amount) when is_number(amount), do: "$#{amount}"
end

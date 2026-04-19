defmodule GnomeGardenWeb.Operations.Helpers do
  @moduledoc false

  def format_atom(nil), do: "-"

  def format_atom(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def format_roles([]), do: "-"

  def format_roles(roles) when is_list(roles) do
    roles
    |> Enum.map(&format_role/1)
    |> Enum.join(", ")
  end

  def format_roles(_roles), do: "-"

  def format_phone(nil), do: "-"
  def format_phone(""), do: "-"
  def format_phone(phone), do: phone

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M")

  def tag_color_for_kind(:internal), do: :sky
  def tag_color_for_kind(:government), do: :amber
  def tag_color_for_kind(:nonprofit), do: :emerald
  def tag_color_for_kind(:individual), do: :rose
  def tag_color_for_kind(_kind), do: :zinc

  defp format_role(role) when is_atom(role), do: format_atom(role)

  defp format_role(role) when is_binary(role) do
    role
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

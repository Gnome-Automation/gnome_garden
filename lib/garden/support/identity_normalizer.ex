defmodule GnomeGarden.Support.IdentityNormalizer do
  @moduledoc """
  Normalization helpers for durable organization and person matching.
  """

  @organization_suffixes ~w(
    co
    company
    corp
    corporation
    inc
    incorporated
    llc
    llp
    lp
    ltd
    limited
    plc
  )

  @spec organization_name_key(term()) :: String.t() | nil
  def organization_name_key(name) when is_binary(name) do
    name
    |> normalize_text()
    |> trim_organization_tokens()
  end

  def organization_name_key(_name), do: nil

  @spec person_name_key(term(), term()) :: String.t() | nil
  def person_name_key(first_name, last_name) do
    [first_name, last_name]
    |> Enum.map(&normalize_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> blank_to_nil()
  end

  @spec email_domain(term()) :: String.t() | nil
  def email_domain(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> String.split("@", parts: 2)
    |> case do
      [_local, ""] -> nil
      [_local, domain] -> domain
      _ -> nil
    end
  end

  def email_domain(_email), do: nil

  defp trim_organization_tokens(nil), do: nil

  defp trim_organization_tokens(text) do
    text
    |> String.split(" ", trim: true)
    |> drop_leading_articles()
    |> drop_trailing_suffixes()
    |> Enum.join(" ")
    |> blank_to_nil()
  end

  defp drop_leading_articles(["the" | rest]), do: rest
  defp drop_leading_articles(tokens), do: tokens

  defp drop_trailing_suffixes(tokens) do
    tokens
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in @organization_suffixes))
    |> Enum.reverse()
  end

  defp normalize_text(nil), do: nil
  defp normalize_text(""), do: nil

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace("&", " and ")
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> blank_to_nil()
  end

  defp normalize_text(_text), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

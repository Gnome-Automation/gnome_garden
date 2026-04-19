defmodule GnomeGarden.Support.WebIdentity do
  @moduledoc """
  Shared website normalization helpers for discovered organizations and targets.
  """

  def normalize_website(nil), do: nil
  def normalize_website(""), do: nil

  def normalize_website(website) when is_binary(website) do
    website
    |> String.trim()
    |> ensure_scheme()
    |> normalize_uri()
  end

  def normalize_website(_website), do: nil

  def website_domain(nil), do: nil

  def website_domain(website) when is_binary(website) do
    website
    |> normalize_website()
    |> case do
      nil ->
        nil

      normalized ->
        normalized
        |> URI.parse()
        |> Map.get(:host)
        |> normalize_host()
    end
  end

  def website_domain(_website), do: nil

  defp ensure_scheme(website) do
    if String.starts_with?(website, ["http://", "https://"]) do
      website
    else
      "https://#{website}"
    end
  end

  defp normalize_uri(website) do
    uri = URI.parse(website)

    case normalize_host(uri.host) do
      nil ->
        nil

      host ->
        path =
          case uri.path do
            nil -> nil
            "/" -> nil
            "" -> nil
            other -> other
          end

        %URI{
          uri
          | scheme: uri.scheme || "https",
            host: host,
            path: path,
            query: nil,
            fragment: nil,
            authority: nil
        }
        |> URI.to_string()
    end
  end

  defp normalize_host(nil), do: nil

  defp normalize_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.trim_leading("www.")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end
end

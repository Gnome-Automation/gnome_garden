defmodule GnomeGarden.Procurement.SourceCredentials do
  @moduledoc """
  Runtime credential checks for external procurement source families.
  """

  @planetbids_username "PLANETBIDS_USERNAME"
  @planetbids_password "PLANETBIDS_PASSWORD"
  @publicpurchase_username "PUBLICPURCHASE_USERNAME"
  @publicpurchase_password "PUBLICPURCHASE_PASSWORD"
  @sam_gov_api_key "SAM_GOV_API_KEY"

  def planetbids_configured? do
    present?(System.get_env(@planetbids_username)) and
      present?(System.get_env(@planetbids_password))
  end

  def planetbids_credentials do
    username = System.get_env(@planetbids_username)
    password = System.get_env(@planetbids_password)

    if present?(username) and present?(password) do
      {:ok, %{username: username, password: password}}
    else
      {:error, missing_credentials_message(:planetbids)}
    end
  end

  def planetbids_env_names, do: [@planetbids_username, @planetbids_password]

  def publicpurchase_configured? do
    present?(System.get_env(@publicpurchase_username)) and
      present?(System.get_env(@publicpurchase_password))
  end

  def publicpurchase_env_names, do: [@publicpurchase_username, @publicpurchase_password]

  def sam_gov_configured?, do: present?(System.get_env(@sam_gov_api_key))
  def sam_gov_env_names, do: [@sam_gov_api_key]

  def credentials_configured?(%{} = source) do
    source
    |> credential_family()
    |> credentials_configured?()
  end

  def credentials_configured?(:planetbids), do: planetbids_configured?()
  def credentials_configured?("planetbids"), do: planetbids_configured?()
  def credentials_configured?(:publicpurchase), do: publicpurchase_configured?()
  def credentials_configured?("publicpurchase"), do: publicpurchase_configured?()
  def credentials_configured?(:sam_gov), do: sam_gov_configured?()
  def credentials_configured?("sam_gov"), do: sam_gov_configured?()
  def credentials_configured?(_source_type), do: false

  def missing_credentials_message(:planetbids) do
    "PlanetBids credentials are missing. Set #{Enum.join(planetbids_env_names(), " and ")} and restart the app."
  end

  def missing_credentials_message("planetbids"), do: missing_credentials_message(:planetbids)

  def missing_credentials_message(:publicpurchase) do
    "PublicPurchase credentials are missing. Set #{Enum.join(publicpurchase_env_names(), " and ")} and restart the app."
  end

  def missing_credentials_message("publicpurchase"),
    do: missing_credentials_message(:publicpurchase)

  def missing_credentials_message(:sam_gov) do
    "SAM.gov API key is missing. Set #{Enum.join(sam_gov_env_names(), " and ")} and restart the app."
  end

  def missing_credentials_message("sam_gov"), do: missing_credentials_message(:sam_gov)

  def missing_credentials_message(_source_type), do: "Required source credentials are missing."

  def credential_family(%{} = source) do
    metadata = Map.get(source, :metadata) || Map.get(source, "metadata") || %{}
    url = Map.get(source, :url) || Map.get(source, "url")

    metadata_value(metadata, "credential_family") ||
      metadata_value(metadata, "procurement_credential_family") ||
      publicpurchase_family(url) ||
      Map.get(source, :source_type) ||
      Map.get(source, "source_type")
  end

  def credential_family(source_type), do: source_type

  defp publicpurchase_family(url) when is_binary(url) do
    if String.contains?(url, "publicpurchase.com"), do: :publicpurchase
  end

  defp publicpurchase_family(_url), do: nil

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

defmodule GnomeGarden.Procurement.SourceCredentials do
  @moduledoc """
  Runtime credential checks for external procurement source families.
  """

  @planetbids_username "PLANETBIDS_USERNAME"
  @planetbids_password "PLANETBIDS_PASSWORD"

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

  def credentials_configured?(:planetbids), do: planetbids_configured?()
  def credentials_configured?("planetbids"), do: planetbids_configured?()
  def credentials_configured?(_source_type), do: true

  def missing_credentials_message(:planetbids) do
    "PlanetBids credentials are missing. Set #{Enum.join(planetbids_env_names(), " and ")} and restart the app."
  end

  def missing_credentials_message("planetbids"), do: missing_credentials_message(:planetbids)

  def missing_credentials_message(_source_type), do: "Required source credentials are missing."

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

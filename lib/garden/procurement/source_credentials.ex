defmodule GnomeGarden.Procurement.SourceCredentials do
  @moduledoc """
  Credential resolution for external procurement source families.

  The database is the primary store. Environment variables remain a deployment
  fallback for existing installs and local repair.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Actions.SourceCredentialResolution
  alias GnomeGarden.Procurement.ProcurementSource

  @planetbids_username "PLANETBIDS_USERNAME"
  @planetbids_password "PLANETBIDS_PASSWORD"
  @publicpurchase_username "PUBLICPURCHASE_USERNAME"
  @publicpurchase_password "PUBLICPURCHASE_PASSWORD"
  @sam_gov_api_key "SAM_GOV_API_KEY"

  def planetbids_configured? do
    credentials_configured?(:planetbids)
  end

  def planetbids_credentials do
    credentials_for(:planetbids)
  end

  def planetbids_env_names, do: [@planetbids_username, @planetbids_password]

  def publicpurchase_configured? do
    credentials_configured?(:publicpurchase)
  end

  def publicpurchase_credentials do
    credentials_for(:publicpurchase)
  end

  def publicpurchase_env_names, do: [@publicpurchase_username, @publicpurchase_password]

  def opengov_configured? do
    credentials_configured?(:opengov)
  end

  def opengov_credentials do
    credentials_for(:opengov)
  end

  def sam_gov_configured?, do: credentials_configured?(:sam_gov)

  def sam_gov_api_key do
    case credential_status(:sam_gov) do
      status when status in [:missing, :env_configured] ->
        env_api_key(:sam_gov, @sam_gov_api_key)

      _stored_status ->
        case Procurement.resolve_source_api_key(family_string(:sam_gov), authorize?: false) do
          {:ok, api_key} -> {:ok, api_key}
          {:error, reason} -> {:error, credential_resolution_error(reason)}
        end
    end
  end

  def sam_gov_env_names, do: [@sam_gov_api_key]

  def credentials_for(source_or_family) do
    family = credential_family(source_or_family)

    case credential_status(source_or_family) do
      status
      when status in [:missing, :env_configured] and family in [:planetbids, "planetbids"] ->
        env_username_password(family, @planetbids_username, @planetbids_password)

      status
      when status in [:missing, :env_configured] and
             family in [:publicpurchase, "publicpurchase"] ->
        env_username_password(family, @publicpurchase_username, @publicpurchase_password)

      status when status in [:missing, :env_configured] ->
        {:error, missing_credentials_message(family)}

      _stored_status ->
        case Procurement.resolve_source_username_password(
               family_string(family),
               procurement_source_id(source_or_family),
               authorize?: false
             ) do
          {:ok, credentials} -> {:ok, credentials}
          {:error, reason} -> {:error, credential_resolution_error(reason)}
        end
    end
  end

  def credentials_configured?(%{} = source) do
    credential_status(source) in [:verified, :env_configured]
  end

  def credentials_configured?(source_type) when source_type in [:planetbids, "planetbids"],
    do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(source_type)
      when source_type in [:publicpurchase, "publicpurchase"],
      do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(source_type) when source_type in [:opengov, "opengov"],
    do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(source_type) when source_type in [:bidnet, "bidnet"],
    do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(source_type) when source_type in [:sam_gov, "sam_gov"],
    do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(_source_type), do: false

  def credential_status(source_or_family) do
    family = credential_family(source_or_family)

    case Procurement.source_credential_status(
           family_string(family),
           procurement_source_id(source_or_family),
           authorize?: false
         ) do
      {:ok, :missing} ->
        if env_configured?(family), do: :env_configured, else: :missing

      {:ok, status} ->
        status

      {:error, _reason} ->
        :missing
    end
  end

  def missing_credentials_message(:planetbids) do
    SourceCredentialResolution.missing_credentials_message("planetbids")
  end

  def missing_credentials_message("planetbids"), do: missing_credentials_message(:planetbids)

  def missing_credentials_message(:publicpurchase) do
    SourceCredentialResolution.missing_credentials_message("publicpurchase")
  end

  def missing_credentials_message("publicpurchase"),
    do: missing_credentials_message(:publicpurchase)

  def missing_credentials_message(:opengov) do
    SourceCredentialResolution.missing_credentials_message("opengov")
  end

  def missing_credentials_message("opengov"), do: missing_credentials_message(:opengov)

  def missing_credentials_message(:bidnet) do
    SourceCredentialResolution.missing_credentials_message("bidnet")
  end

  def missing_credentials_message("bidnet"), do: missing_credentials_message(:bidnet)

  def missing_credentials_message(:sam_gov) do
    SourceCredentialResolution.missing_credentials_message("sam_gov")
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

  defp procurement_source_id(%ProcurementSource{id: id}) when is_binary(id), do: id
  defp procurement_source_id(%{procurement_source_id: id}) when is_binary(id), do: id
  defp procurement_source_id(%{"procurement_source_id" => id}) when is_binary(id), do: id
  defp procurement_source_id(_source), do: nil

  defp env_username_password(family, username_env, password_env) do
    username = System.get_env(username_env)
    password = System.get_env(password_env)

    if present?(username) and present?(password) do
      {:ok, %{username: username, password: password}}
    else
      {:error, missing_credentials_message(family)}
    end
  end

  defp env_username_password_configured?([username_env, password_env]) do
    present?(System.get_env(username_env)) and present?(System.get_env(password_env))
  end

  defp env_configured?(family) when family in [:planetbids, "planetbids"],
    do: env_username_password_configured?(planetbids_env_names())

  defp env_configured?(family) when family in [:publicpurchase, "publicpurchase"],
    do: env_username_password_configured?(publicpurchase_env_names())

  defp env_configured?(family) when family in [:sam_gov, "sam_gov"],
    do: present?(System.get_env(@sam_gov_api_key))

  defp env_configured?(_family), do: false

  defp env_api_key(family, env_name) do
    case System.get_env(env_name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, missing_credentials_message(family)}
    end
  end

  defp family_string(family) when is_atom(family), do: Atom.to_string(family)
  defp family_string(family) when is_binary(family), do: family
  defp family_string(_family), do: nil

  defp credential_resolution_error(%Ash.Error.Unknown{errors: errors}) do
    Enum.find_value(errors, &unknown_error_message/1) || "Credential resolution failed."
  end

  defp credential_resolution_error(reason), do: reason

  defp unknown_error_message(%{error: error}) when is_binary(error), do: error

  defp unknown_error_message(%{value: value}) when is_binary(value), do: value

  defp unknown_error_message(%{value: [missing_credentials: message]}) when is_binary(message),
    do: message

  defp unknown_error_message(_error), do: nil

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

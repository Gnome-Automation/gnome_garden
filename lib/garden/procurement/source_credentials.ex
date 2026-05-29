defmodule GnomeGarden.Procurement.SourceCredentials do
  @moduledoc """
  Credential resolution for external procurement source families.

  The database is the primary store. Environment variables remain a deployment
  fallback for existing installs and local repair.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceCredentialCrypto

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

  def sam_gov_configured?, do: credentials_configured?(:sam_gov)

  def sam_gov_api_key do
    case stored_credential(:sam_gov) do
      %{encrypted_api_key: payload} = credential when is_map(payload) ->
        if verified_credential?(credential) do
          mark_used(credential)
          {:ok, SourceCredentialCrypto.decrypt_secret!(payload)}
        else
          {:error, credential_problem_message(credential, :sam_gov)}
        end

      _ ->
        env_api_key(:sam_gov, @sam_gov_api_key)
    end
  end

  def sam_gov_env_names, do: [@sam_gov_api_key]

  def credentials_for(source_or_family) do
    source_or_family
    |> credential_family()
    |> env_names_for_family()
    |> case do
      {:ok, env_names} -> username_password_credentials(source_or_family, env_names)
      :error -> {:error, missing_credentials_message(credential_family(source_or_family))}
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

  def credentials_configured?(source_type) when source_type in [:sam_gov, "sam_gov"],
    do: credential_status(source_type) in [:verified, :env_configured]

  def credentials_configured?(_source_type), do: false

  def credential_status(source_or_family) do
    family = credential_family(source_or_family)

    case stored_credential(source_or_family) do
      nil ->
        if env_configured?(family), do: :env_configured, else: :missing

      credential ->
        stored_credential_status(credential)
    end
  end

  def missing_credentials_message(:planetbids) do
    "PlanetBids credentials are missing. Add source credentials in the database, or set #{Enum.join(planetbids_env_names(), " and ")} as a fallback."
  end

  def missing_credentials_message("planetbids"), do: missing_credentials_message(:planetbids)

  def missing_credentials_message(:publicpurchase) do
    "PublicPurchase credentials are missing. Add source credentials in the database, or set #{Enum.join(publicpurchase_env_names(), " and ")} as a fallback."
  end

  def missing_credentials_message("publicpurchase"),
    do: missing_credentials_message(:publicpurchase)

  def missing_credentials_message(:sam_gov) do
    "SAM.gov API key is missing. Add a source credential in the database, or set #{Enum.join(sam_gov_env_names(), " and ")} as a fallback."
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

  defp username_password_credentials(source_or_family, [username_env, password_env]) do
    family = credential_family(source_or_family)

    case stored_credential(source_or_family) do
      %{encrypted_password: payload, username: username} = credential
      when is_map(payload) and is_binary(username) ->
        if verified_credential?(credential) do
          mark_used(credential)
          {:ok, %{username: username, password: SourceCredentialCrypto.decrypt_secret!(payload)}}
        else
          {:error, credential_problem_message(credential, family)}
        end

      _ ->
        env_username_password(family, username_env, password_env)
    end
  end

  defp stored_credential_status(%{status: :invalid}), do: :invalid
  defp stored_credential_status(%{test_status: :invalid}), do: :invalid

  defp stored_credential_status(%{test_status: test_status})
       when test_status in [:queued, :testing, :untested],
       do: :pending

  defp stored_credential_status(credential) do
    if verified_credential?(credential), do: :verified, else: :pending
  end

  defp verified_credential?(%{test_status: :verified, encrypted_api_key: payload})
       when is_map(payload),
       do: decryptable?(payload)

  defp verified_credential?(%{
         test_status: :verified,
         encrypted_password: payload,
         username: username
       })
       when is_map(payload),
       do: present?(username) and decryptable?(payload)

  defp verified_credential?(_credential), do: false

  defp stored_credential(source_or_family) do
    stored_source_credential(source_or_family) || stored_family_credential(source_or_family)
  end

  defp stored_source_credential(source_or_family) do
    with id when is_binary(id) <- procurement_source_id(source_or_family),
         {:ok, [credential | _]} <-
           Procurement.list_source_credentials_for_source(id, authorize?: false) do
      credential
    else
      _ -> nil
    end
  end

  defp procurement_source_id(%ProcurementSource{id: id}) when is_binary(id), do: id
  defp procurement_source_id(%{procurement_source_id: id}) when is_binary(id), do: id
  defp procurement_source_id(%{"procurement_source_id" => id}) when is_binary(id), do: id
  defp procurement_source_id(_source), do: nil

  defp stored_family_credential(%{} = source),
    do: source |> credential_family() |> stored_family_credential()

  defp stored_family_credential(family) do
    family = family_string(family)

    if family do
      case Procurement.list_source_credentials_for_family(family, authorize?: false) do
        {:ok, [credential | _]} -> credential
        _ -> nil
      end
    end
  end

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

  defp decryptable?(payload) do
    SourceCredentialCrypto.decrypt_secret!(payload)
    true
  rescue
    _ -> false
  end

  defp mark_used(credential) do
    Procurement.mark_source_credential_used(credential, %{}, authorize?: false)
    :ok
  end

  defp credential_problem_message(%{status: :invalid} = credential, family) do
    invalid_credentials_message(credential, family)
  end

  defp credential_problem_message(%{test_status: :invalid} = credential, family) do
    invalid_credentials_message(credential, family)
  end

  defp credential_problem_message(_credential, family) do
    "#{credential_family_label(family)} credentials are saved, but verification is still pending."
  end

  defp invalid_credentials_message(%{last_failure_reason: reason}, family)
       when is_binary(reason) and reason != "" do
    "#{credential_family_label(family)} credentials are invalid: #{reason}"
  end

  defp invalid_credentials_message(_credential, family) do
    "#{credential_family_label(family)} credentials are invalid. Update credentials and test again."
  end

  defp family_string(family) when is_atom(family), do: Atom.to_string(family)
  defp family_string(family) when is_binary(family), do: family
  defp family_string(_family), do: nil

  defp credential_family_label(:planetbids), do: "PlanetBids"
  defp credential_family_label("planetbids"), do: "PlanetBids"
  defp credential_family_label(:publicpurchase), do: "PublicPurchase"
  defp credential_family_label("publicpurchase"), do: "PublicPurchase"
  defp credential_family_label(:sam_gov), do: "SAM.gov"
  defp credential_family_label("sam_gov"), do: "SAM.gov"
  defp credential_family_label(_family), do: "Source"

  defp env_names_for_family(family) when family in [:planetbids, "planetbids"],
    do: {:ok, planetbids_env_names()}

  defp env_names_for_family(family) when family in [:publicpurchase, "publicpurchase"],
    do: {:ok, publicpurchase_env_names()}

  defp env_names_for_family(_family), do: :error

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

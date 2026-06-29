defmodule GnomeGarden.Procurement.BitwardenCredentialResolver do
  @moduledoc """
  Resolves source credentials from a Bitwarden/Vaultwarden CLI item reference.

  The resolver expects the CLI to already be configured for the intended server
  and unlocked for the service account. It reads a single item into memory and
  returns only the login username/password needed by the caller.
  """

  alias GnomeGarden.Procurement.SourceCredential

  @session_env "GARDEN_BITWARDEN_SESSION"
  @cli_env "GARDEN_BITWARDEN_CLI"
  @config_dir_env "GARDEN_BITWARDEN_CONFIG_DIR"

  @type credentials :: %{username: String.t(), password: String.t(), credential_id: String.t()}

  @spec username_password(SourceCredential.t()) :: {:ok, credentials()} | {:error, String.t()}
  def username_password(%SourceCredential{} = credential) do
    with {:ok, query} <- item_query(credential),
         {:ok, item} <- get_item(query),
         {:ok, credentials} <- login_credentials(item, credential) do
      {:ok, Map.put(credentials, :credential_id, credential.id)}
    end
  end

  def username_password(_credential), do: {:error, "Bitwarden credential reference is invalid."}

  defp get_item(query) do
    with {:ok, command} <- cli_command(),
         {output, 0} <- command_runner().(command, item_args(query), command_opts()),
         {:ok, item} <- Jason.decode(output) do
      {:ok, item}
    else
      {output, status} when is_integer(status) ->
        {:error, "Bitwarden CLI failed with status #{status}: #{sanitize_cli_output(output)}"}

      {:error, %Jason.DecodeError{}} ->
        {:error, "Bitwarden CLI returned invalid JSON."}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Bitwarden CLI failed: #{inspect(reason)}"}
    end
  rescue
    error in ErlangError ->
      {:error, "Bitwarden CLI could not be executed: #{Exception.message(error)}"}
  end

  defp item_args(query) do
    ["get", "item", query]
    |> maybe_add_session()
  end

  defp maybe_add_session(args) do
    case session_key() do
      nil -> args
      session -> args ++ ["--session", session]
    end
  end

  defp command_opts do
    [
      stderr_to_stdout: true,
      env: command_env()
    ]
  end

  defp command_env do
    []
    |> maybe_env("BW_SESSION", session_key())
    |> maybe_env("BITWARDENCLI_APPDATA_DIR", System.get_env(@config_dir_env))
  end

  defp maybe_env(env, _name, nil), do: env
  defp maybe_env(env, _name, ""), do: env
  defp maybe_env(env, name, value), do: [{name, value} | env]

  defp login_credentials(
         %{"login" => %{"username" => username, "password" => password}},
         credential
       )
       when is_binary(password) and password != "" do
    username = first_present(username, credential.username)

    if present?(username) do
      {:ok, %{username: username, password: password}}
    else
      {:error, "Bitwarden item is missing a username."}
    end
  end

  defp login_credentials(_item, _credential) do
    {:error, "Bitwarden item is not a login item with a password."}
  end

  defp item_query(%{bitwarden_item_id: item_id}) when is_binary(item_id) and item_id != "",
    do: {:ok, item_id}

  defp item_query(%{bitwarden_item_name: item_name})
       when is_binary(item_name) and item_name != "",
       do: {:ok, item_name}

  defp item_query(_credential), do: {:error, "Bitwarden item ID or name is required."}

  defp cli_command do
    cond do
      present?(System.get_env(@cli_env)) ->
        {:ok, System.get_env(@cli_env)}

      command = System.find_executable("bitwarden") ->
        {:ok, command}

      command = System.find_executable("bw") ->
        {:ok, command}

      true ->
        {:error, "Bitwarden CLI is not configured. Set #{@cli_env} to the Bitwarden CLI binary."}
    end
  end

  defp command_runner do
    Application.get_env(:gnome_garden, :bitwarden_command_runner, &System.cmd/3)
  end

  defp session_key do
    Application.get_env(:gnome_garden, :bitwarden_session) ||
      System.get_env(@session_env) ||
      System.get_env("BW_SESSION")
  end

  defp sanitize_cli_output(output) when is_binary(output) do
    output
    |> String.replace(~r/[A-Za-z0-9+\/_=.-]{32,}/, "[redacted]")
    |> String.trim()
    |> String.slice(0, 240)
  end

  defp sanitize_cli_output(_output), do: "unknown error"

  defp first_present(value, fallback) do
    cond do
      present?(value) -> value
      present?(fallback) -> fallback
      true -> nil
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

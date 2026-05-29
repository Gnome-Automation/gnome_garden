defmodule GnomeGarden.Procurement.SourceCredentialCrypto do
  @moduledoc """
  Encrypts procurement-source secrets before they are persisted.
  """

  @aad "gnome_garden:procurement_source_credentials:v1"
  @algorithm "AES-256-GCM"

  def encrypt_secret!(secret) when is_binary(secret) do
    secret = String.trim(secret)
    iv = :crypto.strong_rand_bytes(12)
    key = encryption_key!()
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, secret, @aad, true)

    %{
      "v" => 1,
      "alg" => @algorithm,
      "iv" => Base.encode64(iv),
      "tag" => Base.encode64(tag),
      "ciphertext" => Base.encode64(ciphertext)
    }
  end

  def decrypt_secret!(%{"v" => 1, "alg" => @algorithm} = payload) do
    key = encryption_key!()
    iv = Base.decode64!(Map.fetch!(payload, "iv"))
    tag = Base.decode64!(Map.fetch!(payload, "tag"))
    ciphertext = Base.decode64!(Map.fetch!(payload, "ciphertext"))

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      :error -> raise ArgumentError, "source credential secret could not be decrypted"
      plaintext -> plaintext
    end
  end

  def decrypt_secret!(payload) when is_map(payload) do
    raise ArgumentError, "unsupported source credential secret payload"
  end

  def secret_fingerprint(secret) when is_binary(secret) do
    :crypto.mac(:hmac, :sha256, encryption_key!(), String.trim(secret))
    |> Base.encode16(case: :lower)
  end

  defp encryption_key! do
    case System.get_env("GARDEN_CREDENTIAL_ENCRYPTION_KEY") do
      value when is_binary(value) and value != "" ->
        normalize_key(value)

      _ ->
        endpoint_secret_key!()
    end
  end

  defp normalize_key(value) do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == 32 ->
        decoded

      _ ->
        :crypto.hash(:sha256, value)
    end
  end

  defp endpoint_secret_key! do
    :gnome_garden
    |> Application.get_env(GnomeGardenWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base)
    |> case do
      value when is_binary(value) and value != "" ->
        :crypto.hash(:sha256, value)

      _ ->
        raise "GARDEN_CREDENTIAL_ENCRYPTION_KEY or endpoint secret_key_base is required to encrypt source credentials"
    end
  end
end

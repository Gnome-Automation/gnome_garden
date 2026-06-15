defmodule GnomeGarden.SensitiveValueCrypto do
  @moduledoc """
  Small AES-GCM envelope helper for domain-owned sensitive values.

  This mirrors the existing procurement credential storage pattern while letting
  each domain supply its own authenticated-data scope.
  """

  @algorithm "AES-256-GCM"

  def encrypt!(scope, value) when is_binary(scope) and is_binary(value) do
    value = String.trim(value)
    iv = :crypto.strong_rand_bytes(12)
    key = encryption_key!()
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, scope, true)

    %{
      "v" => 1,
      "alg" => @algorithm,
      "iv" => Base.encode64(iv),
      "tag" => Base.encode64(tag),
      "ciphertext" => Base.encode64(ciphertext)
    }
  end

  def decrypt!(scope, %{"v" => 1, "alg" => @algorithm} = payload) when is_binary(scope) do
    key = encryption_key!()
    iv = Base.decode64!(Map.fetch!(payload, "iv"))
    tag = Base.decode64!(Map.fetch!(payload, "tag"))
    ciphertext = Base.decode64!(Map.fetch!(payload, "ciphertext"))

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, scope, tag, false) do
      :error -> raise ArgumentError, "sensitive value could not be decrypted"
      plaintext -> plaintext
    end
  end

  def decrypt!(_scope, payload) when is_map(payload) do
    raise ArgumentError, "unsupported sensitive value payload"
  end

  def fingerprint(value) when is_binary(value) do
    :crypto.mac(:hmac, :sha256, encryption_key!(), String.trim(value))
    |> Base.encode16(case: :lower)
  end

  def last4(value) when is_binary(value) do
    value
    |> String.replace(~r/[^[:alnum:]]/, "")
    |> String.slice(-4, 4)
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
        raise "GARDEN_CREDENTIAL_ENCRYPTION_KEY or endpoint secret_key_base is required to encrypt sensitive values"
    end
  end
end

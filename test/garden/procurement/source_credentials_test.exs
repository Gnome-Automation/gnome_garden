defmodule GnomeGarden.Procurement.SourceCredentialsTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCredentials

  setup do
    env_names =
      SourceCredentials.planetbids_env_names() ++
        SourceCredentials.publicpurchase_env_names() ++ SourceCredentials.sam_gov_env_names()

    original_env = Map.new(env_names, &{&1, System.get_env(&1)})
    Enum.each(env_names, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(original_env, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "resolves family credentials from encrypted database storage before env fallback" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "operator@example.com",
        password: "super-secret"
      })

    assert credential.password_present
    assert credential.last_rotated_at
    refute inspect(credential.encrypted_password) =~ "super-secret"
    refute SourceCredentials.credentials_configured?(:planetbids)

    {:ok, _credential} = Procurement.mark_source_credential_verified(credential, %{})

    assert SourceCredentials.credentials_configured?(:planetbids)

    assert {:ok, %{username: "operator@example.com", password: "super-secret"}} =
             SourceCredentials.planetbids_credentials()

    assert {:ok, [used_credential]} =
             Procurement.list_active_source_credentials_for_family("planetbids")

    assert used_credential.last_used_at
  end

  test "source-specific credentials override family defaults" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Private PlanetBids Source",
        url: "https://vendors.planetbids.com/portal/99999/bo/bo-search",
        source_type: :planetbids,
        portal_id: "99999",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    {:ok, family_credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "family@example.com",
        password: "family-secret"
      })

    {:ok, _family_credential} =
      Procurement.mark_source_credential_verified(family_credential, %{})

    {:ok, source_credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        scope: :source,
        procurement_source_id: source.id,
        username: "source@example.com",
        password: "source-secret"
      })

    refute SourceCredentials.credentials_configured?(source)

    {:ok, _source_credential} =
      Procurement.mark_source_credential_verified(source_credential, %{})

    assert SourceCredentials.credentials_configured?(source)

    assert {:ok, %{username: "source@example.com", password: "source-secret"}} =
             SourceCredentials.credentials_for(source)
  end

  test "disabled database credentials are ignored and env fallback still works" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :publicpurchase,
        credential_family: "publicpurchase",
        username: "disabled@example.com",
        password: "disabled-secret"
      })

    {:ok, _credential} = Procurement.disable_source_credential(credential, %{})

    refute SourceCredentials.credentials_configured?(:publicpurchase)

    System.put_env("PUBLICPURCHASE_USERNAME", "env@example.com")
    System.put_env("PUBLICPURCHASE_PASSWORD", "env-secret")

    assert SourceCredentials.credentials_configured?(:publicpurchase)

    assert {:ok, %{username: "env@example.com", password: "env-secret"}} =
             SourceCredentials.publicpurchase_credentials()
  end

  test "resolves OpenGov credentials from encrypted database storage" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :opengov,
        credential_family: "opengov",
        username: "opengov@example.com",
        password: "opengov-secret"
      })

    refute SourceCredentials.opengov_configured?()

    {:ok, _credential} = Procurement.mark_source_credential_verified(credential, %{})

    assert SourceCredentials.opengov_configured?()

    assert {:ok, %{username: "opengov@example.com", password: "opengov-secret"}} =
             SourceCredentials.opengov_credentials()
  end

  test "resolves SAM.gov API keys from encrypted database storage" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :sam_gov,
        credential_family: "sam_gov",
        api_key: "sam-secret"
      })

    assert credential.api_key_present
    refute inspect(credential.encrypted_api_key) =~ "sam-secret"
    refute SourceCredentials.sam_gov_configured?()

    {:ok, _credential} = Procurement.mark_source_credential_verified(credential, %{})

    assert SourceCredentials.sam_gov_configured?()
    assert {:ok, "sam-secret"} = SourceCredentials.sam_gov_api_key()
  end

  test "stores Bitwarden item references without local secret material" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        credential_storage: :bitwarden,
        username: "pc@gnomeautomation.com",
        bitwarden_server_url: "https://garden.tail6f3b43.ts.net",
        bitwarden_organization: "Gnome Garden",
        bitwarden_collection: "Procurement Sources",
        bitwarden_item_name: "BidNet"
      })

    assert credential.credential_storage == :bitwarden
    assert credential.bitwarden_item_name == "BidNet"
    refute credential.password_present
    refute credential.api_key_present
    assert is_nil(credential.encrypted_password)
    assert is_nil(credential.encrypted_api_key)
    refute SourceCredentials.credentials_configured?(:bidnet)
  end

  test "store in Bitwarden action clears existing local secrets" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        username: "pc@gnomeautomation.com",
        password: "local-secret"
      })

    assert credential.password_present
    assert is_map(credential.encrypted_password)

    {:ok, credential} =
      Procurement.store_source_credential_in_bitwarden(credential, %{
        bitwarden_server_url: "https://garden.tail6f3b43.ts.net",
        bitwarden_organization: "Gnome Garden",
        bitwarden_collection: "Procurement Sources",
        bitwarden_item_name: "BidNet"
      })

    assert credential.credential_storage == :bitwarden
    assert credential.bitwarden_item_name == "BidNet"
    refute credential.password_present
    refute credential.api_key_present
    assert is_nil(credential.encrypted_password)
    assert is_nil(credential.encrypted_api_key)
    assert credential.test_status == :untested
  end

  test "invalid database credentials block env fallback until they are repaired" do
    System.put_env("PLANETBIDS_USERNAME", "env@example.com")
    System.put_env("PLANETBIDS_PASSWORD", "env-secret")

    assert SourceCredentials.credentials_configured?(:planetbids)

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "stored@example.com",
        password: "stored-secret"
      })

    refute SourceCredentials.credentials_configured?(:planetbids)
    assert SourceCredentials.credential_status(:planetbids) == :pending

    {:ok, _credential} =
      Procurement.mark_source_credential_failed(credential, %{
        last_failure_reason: "The portal rejected these credentials."
      })

    refute SourceCredentials.credentials_configured?(:planetbids)
    assert SourceCredentials.credential_status(:planetbids) == :invalid
  end
end

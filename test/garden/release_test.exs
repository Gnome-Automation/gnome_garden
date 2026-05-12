defmodule GnomeGarden.ReleaseTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations
  alias GnomeGarden.Release

  @admin_envs [
    "GARDEN_ADMIN_PC_EMAIL",
    "GARDEN_ADMIN_PC_PASSWORD",
    "GARDEN_ADMIN_PC_DISPLAY_NAME",
    "GARDEN_ADMIN_BHAMMOUD_EMAIL",
    "GARDEN_ADMIN_BHAMMOUD_PASSWORD",
    "GARDEN_ADMIN_BHAMMOUD_DISPLAY_NAME"
  ]

  setup do
    previous_env = Map.new(@admin_envs, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  test "bootstraps the fixed admin accounts idempotently" do
    pc_email = "pc-#{System.unique_integer([:positive])}@example.com"
    bhammoud_email = "bhammoud-#{System.unique_integer([:positive])}@example.com"

    put_admin_env(pc_email, "first-valid-password", bhammoud_email, "second-valid-password")

    assert :ok = Release.bootstrap_admins()

    assert_admin(pc_email, "PC")
    assert_admin(bhammoud_email, "Bhammoud")

    assert {:ok, _user} =
             Accounts.sign_in_user(%{email: pc_email, password: "first-valid-password"})

    put_admin_env(pc_email, "rotated-valid-password", bhammoud_email, "second-valid-password")

    assert :ok = Release.bootstrap_admins()

    assert {:ok, _user} =
             Accounts.sign_in_user(%{email: pc_email, password: "rotated-valid-password"})

    assert {:error, _error} =
             Accounts.sign_in_user(%{email: pc_email, password: "first-valid-password"})
  end

  test "audits bootstrapped admin accounts" do
    pc_email = "pc-audit-#{System.unique_integer([:positive])}@example.com"
    bhammoud_email = "bhammoud-audit-#{System.unique_integer([:positive])}@example.com"

    put_admin_env(pc_email, "first-valid-password", bhammoud_email, "second-valid-password")

    assert :ok = Release.bootstrap_admins()

    assert ExUnit.CaptureIO.capture_io(fn ->
             assert :ok = Release.audit_admins()
           end) =~ "PC: #{pc_email} -> admin, active, PC"
  end

  defp put_admin_env(pc_email, pc_password, bhammoud_email, bhammoud_password) do
    System.put_env("GARDEN_ADMIN_PC_EMAIL", pc_email)
    System.put_env("GARDEN_ADMIN_PC_PASSWORD", pc_password)
    System.put_env("GARDEN_ADMIN_BHAMMOUD_EMAIL", bhammoud_email)
    System.put_env("GARDEN_ADMIN_BHAMMOUD_PASSWORD", bhammoud_password)
  end

  defp assert_admin(email, display_name) do
    assert {:ok, user} = Accounts.get_user_by_email(email, authorize?: false)
    assert {:ok, team_member} = Operations.get_team_member_by_user(user.id)
    assert team_member.display_name == display_name
    assert team_member.role == :admin
    assert team_member.status == :active
  end
end

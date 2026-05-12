defmodule GnomeGarden.Accounts.UserAuthTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Accounts

  describe "password authentication" do
    test "registers and signs in with an email and password" do
      email = "operator-#{System.unique_integer([:positive, :monotonic])}@example.com"
      password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

      assert {:ok, user} =
               Accounts.create_user_with_password(%{
                 email: email,
                 password: password,
                 password_confirmation: password
               })

      assert to_string(user.email) == email

      assert {:ok, signed_in_user} =
               Accounts.sign_in_user(%{
                 email: email,
                 password: password
               })

      assert signed_in_user.id == user.id
    end

    test "rejects invalid passwords" do
      email = "operator-#{System.unique_integer([:positive, :monotonic])}@example.com"
      password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

      assert {:ok, _user} =
               Accounts.create_user_with_password(%{
                 email: email,
                 password: password,
                 password_confirmation: password
               })

      assert {:error, _error} =
               Accounts.sign_in_user(%{
                 email: email,
                 password: "wrong-password"
               })
    end
  end
end

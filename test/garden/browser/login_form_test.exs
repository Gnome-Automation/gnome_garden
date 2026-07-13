defmodule GnomeGarden.Browser.LoginFormTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Browser.LoginForm

  defmodule NoFormBrowser do
    def evaluate(_script), do: {:ok, %{"has_login_form" => false, "reason" => "no_login_form"}}
    def type(_selector, _value), do: raise("must not type without a login form")
  end

  defmodule FormBrowser do
    def evaluate(script) do
      if String.contains?(script, "requestSubmit") do
        send(Process.get(:test_pid), {:submit_script, script})
        {:ok, %{"submitted" => true, "method" => "request_submit"}}
      else
        {:ok, %{"has_login_form" => true}}
      end
    end

    def type(selector, value) do
      send(Process.get(:test_pid), {:typed, selector, value})
      {:ok, %{}}
    end
  end

  setup do
    Process.put(:test_pid, self())
    :ok
  end

  test "treats a missing login form as an optional public listing page" do
    assert {:ok, :absent} =
             LoginForm.submit_if_present(NoFormBrowser, %{
               username: "operator@example.com",
               password: "source-secret"
             })
  end

  test "types secrets separately and submits within the password form" do
    assert {:ok, :submitted} =
             LoginForm.submit_if_present(FormBrowser, %{
               username: "operator@example.com",
               password: "source-secret"
             })

    assert_receive {:typed, _selector, "operator@example.com"}
    assert_receive {:typed, _selector, "source-secret"}
    assert_receive {:submit_script, script}
    assert script =~ "passInput.closest('form')"
    assert script =~ "form.querySelector"
    assert script =~ "form.requestSubmit"
    refute script =~ "source-secret"
  end
end

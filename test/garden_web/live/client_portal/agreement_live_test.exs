defmodule GnomeGardenWeb.ClientPortal.AgreementLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_client_user

  setup %{organization: org} do
    agreement = Ash.Seed.seed!(GnomeGarden.Commercial.Agreement, %{
      organization_id: org.id,
      name: "Test Agreement",
      status: :active,
      billing_model: :fixed_fee
    })
    {:ok, agreement: agreement}
  end

  test "agreement list shows active agreements for client's org", %{conn: conn, agreement: ag} do
    {:ok, _view, html} = live(conn, ~p"/portal/agreements")
    assert html =~ "Test Agreement"
  end

  test "agreement detail shows agreement info", %{conn: conn, agreement: ag} do
    {:ok, _view, html} = live(conn, ~p"/portal/agreements/#{ag.id}")
    assert html =~ "Test Agreement"
  end

  test "cannot access another org's agreement", %{conn: conn} do
    other_org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Other"})
    other_ag = Ash.Seed.seed!(GnomeGarden.Commercial.Agreement, %{
      organization_id: other_org.id,
      name: "Other Agreement",
      status: :active,
      billing_model: :fixed_fee
    })
    assert {:error, _} = live(conn, ~p"/portal/agreements/#{other_ag.id}")
  end
end

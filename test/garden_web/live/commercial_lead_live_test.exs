defmodule GnomeGardenWeb.CommercialLeadLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  test "new lead form creates a referral signal with organization, contact, and task", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/commercial/leads/new")

    assert html =~ "New Lead"
    assert has_element?(view, "#lead-intake-form")

    params = %{
      "organization" => %{
        "name" => "Acme Controls",
        "legal_name" => "Acme Controls LLC",
        "website" => "https://acme-controls.example",
        "primary_region" => "CA",
        "notes" => "Referral from plant manager"
      },
      "sites" => %{
        "0" => %{
          "name" => "Main Plant",
          "address1" => "123 Industrial Way",
          "city" => "Anaheim",
          "state" => "CA",
          "postal_code" => "92801",
          "country_code" => "US"
        }
      },
      "contacts" => %{
        "0" => %{
          "first_name" => "Alex",
          "last_name" => "Buyer",
          "email" => "alex.buyer@acme-controls.example",
          "phone" => "555-0100",
          "title" => "Procurement Manager",
          "contact_roles" => "referrer, procurement",
          "is_primary" => "true"
        }
      },
      "signal" => %{
        "title" => "Acme referral for PLC upgrade",
        "description" => "Possible controls modernization and PLC support.",
        "source_url" => "https://acme-controls.example",
        "external_ref" => "manual_referral:acme:test",
        "referral_source" => "Plant manager",
        "suspected_needs" => "PLC\nSCADA\nControls",
        "notes" => "Call to qualify scope."
      },
      "task" => %{
        "title" => "Call Acme about PLC upgrade",
        "description" => "Confirm scope and next step.",
        "task_type" => "call",
        "priority" => "urgent"
      }
    }

    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> form("#lead-intake-form", %{form: params})
             |> render_submit()

    assert String.starts_with?(path, "/commercial/signals/")

    assert {:ok, signal} = Commercial.get_signal_by_external_ref("manual_referral:acme:test")
    assert signal.title == "Acme referral for PLC upgrade"
    assert signal.signal_type == :referral

    assert {:ok, organization} = Operations.get_organization(signal.organization_id)
    assert organization.name == "Acme Controls"
    assert organization.website_domain == "acme-controls.example"

    assert {:ok, people} = Operations.list_people_for_organization(organization.id)
    assert Enum.any?(people, &(to_string(&1.email) == "alex.buyer@acme-controls.example"))

    assert {:ok, tasks} = Operations.list_tasks_by_signal(signal.id)
    assert Enum.any?(tasks, &(&1.title == "Call Acme about PLC upgrade"))
  end
end

defmodule GnomeGarden.Company.VendorRegistrationPacketTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Company.VendorRegistrationPacket

  test "builds packet sections with masked sensitive values and missing states" do
    profile = %{
      id: "profile-1",
      key: "primary",
      name: "Gnome Automation",
      legal_name: "Gnome Automation LLC",
      metadata: %{
        "vendor_registration" => %{
          "company" => %{
            "legal_entity_name" => "Gnome Automation LLC",
            "entity_type" => "LLC",
            "legal_address" => %{
              "street" => "2108 N Street, Ste N",
              "city" => "Sacramento",
              "state" => "CA",
              "zip" => "95816",
              "country" => "US"
            }
          },
          "tax_identifiers" => %{
            "fein_us" => %{"value" => "12-3456789"},
            "sales_tax_id_us" => %{"value" => "N/A"}
          },
          "banking" => %{
            "provider" => "Mercury",
            "bank_of_record" => "Column N.A.",
            "account" => %{
              "kind" => "checking",
              "number" => "123456789012",
              "routing_number" => "121145433"
            }
          }
        }
      }
    }

    packet = VendorRegistrationPacket.build(profile)
    fields = packet.sections |> Enum.flat_map(& &1.fields) |> Map.new(&{&1.id, &1})

    assert fields["legal_entity_name"].display_value == "Gnome Automation LLC"
    assert fields["legal_address"].display_value =~ "Sacramento CA 95816"
    assert fields["fein_us"].display_value == "**** 6789"
    assert fields["account_number"].display_value == "**** 9012"
    assert fields["sales_tax_id_us"].status == :not_applicable
    assert fields["swift_bic"].status == :missing

    revealed = VendorRegistrationPacket.build(profile, reveal_sensitive?: true)
    revealed_fields = revealed.sections |> Enum.flat_map(& &1.fields) |> Map.new(&{&1.id, &1})

    assert revealed_fields["fein_us"].display_value == "12-3456789"
    assert revealed_fields["account_number"].display_value == "123456789012"
  end
end

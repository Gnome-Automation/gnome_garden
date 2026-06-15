defmodule GnomeGarden.Company.DefaultRegistration do
  @moduledoc """
  Idempotent bootstrap for Gnome's vendor-registration facts.

  Non-secret company facts remain on the primary profile metadata. Sensitive
  identifiers are stored in first-class resources with encrypted payloads.
  """

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultProfiles

  @profile_metadata %{
    "vendor_registration" => %{
      "company" => %{
        "legal_entity_name" => "Gnome Automation LLC",
        "registered_address" => %{
          "street" => "2108 N Street, Ste N",
          "city" => "Sacramento",
          "state" => "CA",
          "postal_code" => "95816",
          "country" => "United States of America"
        },
        "telephone" => "(657) 866-4636",
        "order_email" => "sales@gnomeautomation.com",
        "purchasing_email" => "sales@gnomeautomation.com",
        "finance_email" => "sales@gnomeautomation.com",
        "members" => [
          %{
            "key" => "bassam_hammoud",
            "name" => "Bassam Hammoud",
            "title" => "Co-Founder",
            "direct_phone" => nil,
            "email" => "bhammoud@gnomeautomation.com",
            "vendor_contact_eligible" => true
          },
          %{
            "key" => "patrick_curran",
            "name" => "Patrick Curran",
            "title" => "Co-Founder",
            "direct_phone" => "970-556-4676",
            "email" => "pc@gnomeautomation.com",
            "vendor_contact_eligible" => true
          }
        ],
        "vendor_contact" => %{
          "member_key" => "patrick_curran",
          "name" => "Patrick Curran",
          "direct_phone" => "970-556-4676",
          "email" => "pc@gnomeautomation.com"
        }
      },
      "tax_identifiers" => %{
        "fein_us" => %{
          "status" => "captured",
          "stored_in" => "Company.TaxIdentifier",
          "last4" => "6117"
        },
        "sales_tax_id_us" => %{"value" => "N/A"},
        "vat_eu" => %{"value" => "N/A"},
        "gst_india" => %{"value" => "N/A"},
        "pan_india" => %{"value" => "N/A"}
      },
      "standard_terms" => %{
        "delivery_terms" => %{"default_answer" => "DDP"},
        "payment_terms" => %{"default_answer" => "Net 60"},
        "currency" => "USD"
      }
    }
  }

  @spec ensure_default(keyword()) :: %{
          profile: GnomeGarden.Company.Profile.t(),
          tax_identifiers: [GnomeGarden.Company.TaxIdentifier.t()]
        }
  def ensure_default(opts \\ []) do
    profile = DefaultProfiles.ensure_default().profile
    profile = ensure_profile_metadata(profile)

    %{
      profile: profile,
      tax_identifiers: ensure_tax_identifiers(profile, opts)
    }
  end

  defp ensure_profile_metadata(profile) do
    metadata = deep_merge(@profile_metadata, profile.metadata || %{})

    if metadata == (profile.metadata || %{}) do
      profile
    else
      {:ok, profile} = Company.update_company_profile(profile, %{metadata: metadata})
      profile
    end
  end

  defp ensure_tax_identifiers(profile, opts) do
    case Keyword.get(opts, :fein) || System.get_env("GNOME_COMPANY_FEIN") do
      value when is_binary(value) and value != "" ->
        [ensure_fein(profile, value)]

      _ ->
        []
    end
  end

  defp ensure_fein(profile, value) do
    attrs = %{
      company_profile_id: profile.id,
      identifier_type: :fein,
      jurisdiction: "US",
      label: "Federal Employer Identification Number",
      value: value,
      status: :active,
      notes: "Used for vendor onboarding and procurement source registration.",
      metadata: %{
        "source" => "vendor packet",
        "captured_on" => "2026-06-13"
      }
    }

    case Company.get_company_tax_identifier_by_type(profile.id, :fein, "US") do
      {:ok, identifier} ->
        {:ok, identifier} =
          Company.update_company_tax_identifier(
            identifier,
            Map.drop(attrs, [:company_profile_id, :value])
          )

        identifier

      {:error, _reason} ->
        {:ok, identifier} = Company.create_company_tax_identifier(attrs)
        identifier
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right
end

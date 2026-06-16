defmodule GnomeGarden.Company.VendorRegistrationPacket do
  @moduledoc """
  Normalized vendor-registration packet derived from a company profile.
  """

  @sensitive_paths [
    ["tax_identifiers", "fein_us", "value"],
    ["banking", "account", "number"],
    ["banking", "domestic_transfer", "account_number"],
    ["banking", "domestic_transfer", "beneficiary", "account_number"],
    ["banking", "international_wire", "iban_or_account_number"],
    ["banking", "international_wire", "beneficiary", "iban_or_account_number"],
    ["banking", "international_wire", "beneficiary", "account_number"]
  ]

  @spec build(map(), keyword()) :: map()
  def build(profile, opts \\ []) do
    reveal_sensitive? = Keyword.get(opts, :reveal_sensitive?, false)
    vendor_registration = get_in(profile_metadata(profile), ["vendor_registration"]) || %{}

    sections =
      [
        company_section(profile, vendor_registration, reveal_sensitive?),
        tax_section(vendor_registration, reveal_sensitive?),
        banking_section(vendor_registration, reveal_sensitive?),
        terms_section(vendor_registration, reveal_sensitive?)
      ]

    fields = Enum.flat_map(sections, & &1.fields)
    ready_count = Enum.count(fields, &(&1.status == :ready))
    missing_count = Enum.count(fields, &(&1.status == :missing))

    %{
      profile_id: Map.get(profile, :id),
      profile_key: Map.get(profile, :key),
      profile_name: Map.get(profile, :name),
      legal_name: first_present([Map.get(profile, :legal_name), Map.get(profile, :name)]),
      imported_at: Map.get(vendor_registration, "imported_at"),
      reveal_sensitive?: reveal_sensitive?,
      ready_count: ready_count,
      missing_count: missing_count,
      total_count: length(fields),
      sections: sections
    }
  end

  defp company_section(profile, vendor_registration, reveal_sensitive?) do
    company = Map.get(vendor_registration, "company", %{})

    fields = [
      field(
        "legal_entity_name",
        "Legal entity name",
        first_present([get_in(company, ["legal_entity_name"]), Map.get(profile, :legal_name)]),
        ["company", "legal_entity_name"],
        reveal_sensitive?
      ),
      field(
        "entity_type",
        "Entity type",
        get_in(company, ["entity_type"]),
        ["company", "entity_type"],
        reveal_sensitive?
      ),
      field(
        "legal_address",
        "Legal address",
        format_address(get_in(company, ["legal_address"])),
        ["company", "legal_address"],
        reveal_sensitive?
      ),
      field(
        "registered_agent",
        "Registered agent",
        get_in(company, ["registered_agent"]),
        ["company", "registered_agent"],
        reveal_sensitive?
      ),
      field(
        "signing_authority",
        "Signing authority",
        get_in(company, ["signing_authority", "title"]),
        ["company", "signing_authority", "title"],
        reveal_sensitive?
      )
    ]

    section("company", "Company", fields)
  end

  defp tax_section(vendor_registration, reveal_sensitive?) do
    tax = Map.get(vendor_registration, "tax_identifiers", %{})

    fields = [
      field(
        "fein_us",
        "FEIN",
        get_in(tax, ["fein_us", "value"]),
        ["tax_identifiers", "fein_us", "value"],
        reveal_sensitive?
      ),
      field(
        "sales_tax_id_us",
        "Sales tax ID",
        get_in(tax, ["sales_tax_id_us", "value"]),
        ["tax_identifiers", "sales_tax_id_us", "value"],
        reveal_sensitive?
      ),
      field(
        "vat_eu",
        "VAT",
        get_in(tax, ["vat_eu", "value"]),
        ["tax_identifiers", "vat_eu", "value"],
        reveal_sensitive?
      ),
      field(
        "gst_india",
        "GST",
        get_in(tax, ["gst_india", "value"]),
        ["tax_identifiers", "gst_india", "value"],
        reveal_sensitive?
      ),
      field(
        "pan_india",
        "PAN",
        get_in(tax, ["pan_india", "value"]),
        ["tax_identifiers", "pan_india", "value"],
        reveal_sensitive?
      )
    ]

    section("tax", "Tax", fields)
  end

  defp banking_section(vendor_registration, reveal_sensitive?) do
    banking = Map.get(vendor_registration, "banking", %{})
    domestic = Map.get(banking, "domestic_transfer", %{})
    international = Map.get(banking, "international_wire", %{})

    fields = [
      field(
        "banking_provider",
        "Provider",
        Map.get(banking, "provider"),
        ["banking", "provider"],
        reveal_sensitive?
      ),
      field(
        "bank_of_record",
        "Bank of record",
        first_present([Map.get(banking, "bank_of_record"), get_in(domestic, ["bank_name"])]),
        ["banking", "bank_of_record"],
        reveal_sensitive?
      ),
      field(
        "account_kind",
        "Account kind",
        first_present([get_in(banking, ["account", "kind"]), get_in(domestic, ["account_kind"])]),
        ["banking", "account", "kind"],
        reveal_sensitive?
      ),
      field(
        "account_number",
        "Account number",
        first_present([
          get_in(banking, ["account", "number"]),
          get_in(domestic, ["account_number"]),
          get_in(domestic, ["beneficiary", "account_number"])
        ]),
        ["banking", "account", "number"],
        reveal_sensitive?
      ),
      field(
        "routing_number",
        "Routing number",
        first_present([
          get_in(banking, ["account", "routing_number"]),
          get_in(domestic, ["routing_number"])
        ]),
        ["banking", "account", "routing_number"],
        reveal_sensitive?
      ),
      field(
        "alternate_routing_number",
        "Alternate routing number",
        first_present([
          get_in(banking, ["account", "alternate_routing_number"]),
          get_in(domestic, ["alternate_routing_number"])
        ]),
        ["banking", "account", "alternate_routing_number"],
        reveal_sensitive?
      ),
      field(
        "bank_address",
        "Bank address",
        first_present([
          format_address(get_in(domestic, ["bank_address"])),
          Map.get(banking, "bank_address")
        ]),
        ["banking", "domestic_transfer", "bank_address"],
        reveal_sensitive?
      ),
      field(
        "beneficiary_name",
        "Beneficiary name",
        first_present([
          get_in(domestic, ["beneficiary", "name"]),
          get_in(domestic, ["beneficiary_name"])
        ]),
        ["banking", "domestic_transfer", "beneficiary", "name"],
        reveal_sensitive?
      ),
      field(
        "beneficiary_address",
        "Beneficiary address",
        first_present([
          format_address(get_in(domestic, ["beneficiary", "address"])),
          get_in(domestic, ["beneficiary_address"])
        ]),
        ["banking", "domestic_transfer", "beneficiary", "address"],
        reveal_sensitive?
      ),
      field(
        "swift_bic",
        "SWIFT / BIC",
        first_present([
          get_in(international, ["swift_bic"]),
          get_in(international, ["receiving_bank", "swift_bic"])
        ]),
        ["banking", "international_wire", "swift_bic"],
        reveal_sensitive?
      ),
      field(
        "international_account_number",
        "International account number",
        first_present([
          get_in(international, ["iban_or_account_number"]),
          get_in(international, ["beneficiary", "iban_or_account_number"]),
          get_in(international, ["beneficiary", "account_number"])
        ]),
        ["banking", "international_wire", "beneficiary", "account_number"],
        reveal_sensitive?
      ),
      field(
        "international_bank_address",
        "International bank address",
        first_present([
          format_address(get_in(international, ["bank_address"])),
          format_address(get_in(international, ["receiving_bank", "address"])),
          get_in(international, ["receiving_bank", "bank_address"])
        ]),
        ["banking", "international_wire", "receiving_bank", "address"],
        reveal_sensitive?
      ),
      field(
        "intermediary_swift_bic",
        "Intermediary SWIFT / BIC",
        first_present([
          get_in(international, ["intermediary_swift_bic"]),
          get_in(international, ["intermediary_bank", "swift_bic"])
        ]),
        ["banking", "international_wire", "intermediary_swift_bic"],
        reveal_sensitive?
      )
    ]

    section("banking", "Banking", fields)
  end

  defp terms_section(vendor_registration, reveal_sensitive?) do
    terms = Map.get(vendor_registration, "standard_terms", %{})

    fields = [
      field(
        "delivery_terms",
        "Delivery terms",
        get_in(terms, ["delivery_terms", "default_answer"]),
        ["standard_terms", "delivery_terms", "default_answer"],
        reveal_sensitive?
      ),
      field(
        "payment_terms",
        "Payment terms",
        first_present([
          get_in(terms, ["payment_terms", "default_answer"]),
          get_in(terms, ["payment_terms", "policy"])
        ]),
        ["standard_terms", "payment_terms"],
        reveal_sensitive?
      ),
      field(
        "invoice_footer",
        "Invoice footer",
        Map.get(terms, "invoice_footer"),
        ["standard_terms", "invoice_footer"],
        reveal_sensitive?
      )
    ]

    section("terms", "Terms", fields)
  end

  defp section(id, title, fields) do
    %{
      id: id,
      title: title,
      ready_count: Enum.count(fields, &(&1.status == :ready)),
      missing_count: Enum.count(fields, &(&1.status == :missing)),
      fields: fields
    }
  end

  defp field(id, label, value, path, reveal_sensitive?) do
    status = field_status(value)
    sensitive? = path in @sensitive_paths
    display_value = display_value(value, status, sensitive?, reveal_sensitive?)

    %{
      id: id,
      label: label,
      value: normalize_value(value),
      display_value: display_value,
      path: Enum.join(path, "."),
      status: status,
      sensitive?: sensitive?
    }
  end

  defp field_status(value) do
    value = normalize_value(value)

    cond do
      value in [nil, "", "NOT_CAPTURED"] -> :missing
      value in ["N/A", "NA", "Not applicable"] -> :not_applicable
      true -> :ready
    end
  end

  defp display_value(_value, :missing, _sensitive?, _reveal_sensitive?), do: "Missing"

  defp display_value(value, :not_applicable, _sensitive?, _reveal_sensitive?),
    do: normalize_value(value)

  defp display_value(value, _status, true, false), do: mask_value(value)
  defp display_value(value, _status, _sensitive?, _reveal_sensitive?), do: normalize_value(value)

  defp mask_value(value) do
    value = normalize_value(value)

    case String.length(value) do
      length when length <= 4 -> "****"
      length -> "**** " <> String.slice(value, max(length - 4, 0), 4)
    end
  end

  defp profile_metadata(profile), do: Map.get(profile, :metadata) || %{}

  defp format_address(nil), do: nil
  defp format_address(""), do: nil
  defp format_address(value) when is_binary(value), do: value

  defp format_address(address) when is_map(address) do
    [
      Map.get(address, "street"),
      Map.get(address, "street_2"),
      city_state_zip(address),
      Map.get(address, "country")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp format_address(_value), do: nil

  defp city_state_zip(address) do
    [Map.get(address, "city"), Map.get(address, "state"), Map.get(address, "zip")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp first_present(values) do
    Enum.find_value(values, fn value ->
      value = normalize_value(value)
      if value in [nil, ""], do: nil, else: value
    end)
  end

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp normalize_value(value), do: to_string(value) |> String.trim()
end

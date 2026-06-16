defmodule GnomeGarden.Company.RegistrationFacts do
  @moduledoc """
  Read model for vendor-registration and procurement-site signup forms.

  Sensitive fields are masked by default. Callers that are explicitly filling a
  trusted form can request revealed values with `reveal_sensitive?: true`.
  """

  alias GnomeGarden.Company
  alias GnomeGarden.SensitiveValueCrypto

  @tax_scope "gnome_garden:commercial_company_tax_identifiers:v1"
  @payment_scope "gnome_garden:finance_payment_destinations:v1"

  @spec resolve(keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(opts \\ []) do
    with {:ok, profile} <- Company.get_primary_company_profile(),
         {:ok, tax_identifiers} <- Company.list_company_tax_identifiers_for_profile(profile.id) do
      payment_destination_key =
        Keyword.get(opts, :payment_destination_key, "gnome_mercury_checking")

      reveal_sensitive? = Keyword.get(opts, :reveal_sensitive?, false)

      {:ok,
       %{
         company: company_facts(profile),
         tax_identifiers: tax_identifier_facts(tax_identifiers, reveal_sensitive?),
         payment_destination:
           payment_destination_facts(payment_destination_key, reveal_sensitive?),
         standard_terms: standard_terms(profile)
       }}
    end
  end

  defp company_facts(profile) do
    vendor_registration = vendor_registration(profile)
    company = Map.get(vendor_registration, "company", %{})

    %{
      legal_entity_name: company["legal_entity_name"] || profile.legal_name,
      registered_address: company["registered_address"] || company["legal_address"],
      telephone: company["telephone"],
      order_email: company["order_email"],
      purchasing_email: company["purchasing_email"],
      finance_email: company["finance_email"],
      members: company["members"] || [],
      vendor_contact: company["vendor_contact"]
    }
  end

  defp standard_terms(profile) do
    profile
    |> vendor_registration()
    |> Map.get("standard_terms", %{})
  end

  defp tax_identifier_facts(tax_identifiers, reveal_sensitive?) do
    Map.new(tax_identifiers, fn identifier ->
      key =
        case {identifier.identifier_type, identifier.jurisdiction} do
          {:fein, "US"} -> :fein_us
          {type, jurisdiction} -> :"#{type}_#{String.downcase(jurisdiction)}"
        end

      value =
        if reveal_sensitive? and identifier.encrypted_value do
          SensitiveValueCrypto.decrypt!(@tax_scope, identifier.encrypted_value)
        end

      {key,
       %{
         label: identifier.label,
         jurisdiction: identifier.jurisdiction,
         status: identifier.status,
         value_present: identifier.value_present,
         value_last4: identifier.value_last4,
         value: value
       }}
    end)
  end

  defp payment_destination_facts(key, reveal_sensitive?) do
    case Company.get_payment_destination_by_key(key) do
      {:ok, destination} ->
        account_number =
          if reveal_sensitive? and destination.encrypted_account_number do
            SensitiveValueCrypto.decrypt!(@payment_scope, destination.encrypted_account_number)
          end

        %{
          key: destination.key,
          label: destination.label,
          provider: destination.provider,
          account_kind: destination.account_kind,
          beneficiary_name: destination.beneficiary_name,
          beneficiary_address: destination.beneficiary_address,
          bank_name: destination.bank_name,
          bank_address: destination.bank_address,
          domestic_routing_number: destination.domestic_routing_number,
          wire_routing_number: destination.wire_routing_number,
          alternate_routing_number: destination.alternate_routing_number,
          swift_bic: destination.swift_bic,
          intermediary_swift_bic: destination.intermediary_swift_bic,
          currency_code: destination.currency_code,
          account_number_present: destination.account_number_present,
          account_number_last4: destination.account_number_last4,
          account_number: account_number
        }

      {:error, _reason} ->
        nil
    end
  end

  defp vendor_registration(profile) do
    profile.metadata
    |> Kernel.||(%{})
    |> Map.get("vendor_registration", %{})
  end
end

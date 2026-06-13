defmodule GnomeGarden.Commercial.Actions.ImportVendorOnboarding do
  @moduledoc """
  Imports reusable vendor-registration facts and customer onboarding records.

  This action is intentionally rooted in `CompanyProfile`: the reusable vendor
  answers are company-profile data, while customer-specific outcomes are applied
  to Operations resources through their code interfaces.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DefaultCompanyProfiles
  alias GnomeGarden.Operations

  @supplier_code_task_key "supplier_code_of_conduct_confirmation_letter"

  @impl true
  def run(input, _opts, context) do
    payload =
      input
      |> Ash.ActionInput.get_argument(:payload)
      |> stringify_keys()

    actor = context.actor
    profile = upsert_company_profile!(payload, actor)
    customers = Enum.map(Map.get(payload, "customers", []), &ensure_customer!(&1, actor))

    {:ok,
     %{
       "company_profile_id" => profile.id,
       "customer_count" => length(customers),
       "customer_ids" => Enum.map(customers, & &1.organization.id),
       "task_ids" =>
         customers
         |> Enum.map(& &1.supplier_code_task)
         |> Enum.reject(&is_nil/1)
         |> Enum.map(& &1.id)
     }}
  rescue
    error -> {:error, error}
  end

  defp upsert_company_profile!(payload, actor) do
    profile = DefaultCompanyProfiles.ensure_default().profile
    metadata = deep_merge(profile.metadata || %{}, vendor_metadata(payload))

    {:ok, profile} =
      Commercial.update_company_profile(profile, %{metadata: metadata},
        actor: actor,
        authorize?: false
      )

    profile
  end

  defp vendor_metadata(payload) do
    payload
    |> Map.drop(["customers"])
    |> Map.put(
      "imported_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
    |> then(&%{"vendor_registration" => &1})
  end

  defp ensure_customer!(customer, actor) do
    customer = stringify_keys(customer)
    name = fetch_string!(customer, "name")

    {:ok, organization} =
      Operations.create_organization(
        %{
          name: name,
          legal_name: name,
          organization_kind: :business,
          status: :active,
          relationship_roles: ["customer"],
          primary_region: Map.get(customer, "location_engaged"),
          notes: customer_notes(customer)
        },
        actor: actor,
        authorize?: false
      )

    ap_contact = ensure_accounts_payable_contact!(customer, actor)
    affiliation = ensure_customer_affiliation!(organization, ap_contact, customer, actor)
    task = ensure_supplier_code_task!(organization, customer, actor)

    %{
      organization: organization,
      accounts_payable_contact: ap_contact,
      accounts_payable_affiliation: affiliation,
      supplier_code_task: task
    }
  end

  defp ensure_accounts_payable_contact!(%{"accounts_payable_email" => email} = customer, actor)
       when is_binary(email) and email != "" do
    normalized_email = String.trim(email)

    case Operations.get_person_by_email(normalized_email, actor: actor, authorize?: false) do
      {:ok, person} ->
        person

      {:error, error} ->
        if not_found_error?(error) do
          {:ok, person} =
            Operations.create_person(
              %{
                first_name: "Accounts",
                last_name: "Payable",
                email: normalized_email,
                status: :active,
                preferred_contact_method: :email,
                notes: "AP contact from #{fetch_string!(customer, "name")} onboarding profile."
              },
              actor: actor,
              authorize?: false
            )

          person
        else
          raise "Failed to load AP contact #{normalized_email}: #{Exception.message(error)}"
        end
    end
  end

  defp ensure_accounts_payable_contact!(_customer, _actor), do: nil

  defp ensure_customer_affiliation!(_organization, nil, _customer, _actor), do: nil

  defp ensure_customer_affiliation!(organization, person, customer, actor) do
    existing =
      organization.id
      |> Operations.list_affiliations_for_organization(actor: actor, authorize?: false)
      |> case do
        {:ok, affiliations} ->
          Enum.find(affiliations, &(&1.person_id == person.id and &1.status == :active))

        {:error, error} ->
          raise "Failed to list affiliations for #{organization.name}: #{Exception.message(error)}"
      end

    if existing do
      existing
    else
      {:ok, affiliation} =
        Operations.create_organization_affiliation(
          %{
            organization_id: organization.id,
            person_id: person.id,
            title: "Accounts Payable",
            department: "Accounts Payable",
            contact_roles: ["accounts_payable", "invoicing"],
            status: :active,
            is_primary: true,
            notes: "Imported from #{fetch_string!(customer, "name")} onboarding profile."
          },
          actor: actor,
          authorize?: false
        )

      affiliation
    end
  end

  defp ensure_supplier_code_task!(organization, customer, actor) do
    existing =
      organization.id
      |> Operations.list_tasks_by_organization(actor: actor, authorize?: false)
      |> case do
        {:ok, tasks} ->
          Enum.find(tasks, fn task ->
            get_in(task.metadata || %{}, ["vendor_onboarding", "task_key"]) ==
              @supplier_code_task_key
          end)

        {:error, error} ->
          raise "Failed to list tasks for #{organization.name}: #{Exception.message(error)}"
      end

    if existing do
      existing
    else
      {:ok, task} =
        Operations.create_task(
          %{
            title: "Return #{organization.name} supplier code of conduct letter",
            description:
              "Download the Supplier Code of Conduct Confirmation Letter from PolyPeptide's Downloads page, sign it, and return it.",
            priority: :high,
            task_type: :email,
            origin_domain: :operations,
            origin_resource: "vendor_onboarding",
            origin_label: "#{organization.name} supplier code of conduct",
            organization_id: organization.id,
            metadata: %{
              "vendor_onboarding" => %{
                "task_key" => @supplier_code_task_key,
                "source" => Map.get(customer, "source", "vendor onboarding import"),
                "status" => get_in(customer, ["status", "supplier_code_of_conduct_letter"])
              }
            }
          },
          actor: actor,
          authorize?: false
        )

      task
    end
  end

  defp customer_notes(customer) do
    [
      text_line("Description", Map.get(customer, "description")),
      text_line("Engaged location", Map.get(customer, "location_engaged")),
      text_line("NDA", get_in(customer, ["status", "nda"])),
      text_line("Vendor banking form", get_in(customer, ["status", "vendor_banking_form"])),
      text_line(
        "Supplier code of conduct",
        get_in(customer, ["status", "supplier_code_of_conduct_letter"])
      ),
      text_line("Payment terms", Map.get(customer, "payment_terms")),
      text_line("Invoice format", get_in(customer, ["invoicing", "format"])),
      checklist("Invoice required fields", get_in(customer, ["invoicing", "required_fields"]))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp text_line(_label, nil), do: nil
  defp text_line(_label, ""), do: nil
  defp text_line(label, value), do: "#{label}: #{value}"

  defp checklist(_label, nil), do: nil
  defp checklist(_label, []), do: nil

  defp checklist(label, values) when is_list(values) do
    body = Enum.map_join(values, "\n", &"- #{&1}")
    "#{label}:\n#{body}"
  end

  defp fetch_string!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "expected #{key} to be a non-empty string"
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp not_found_error?(%Ash.Error.Query.NotFound{}), do: true

  defp not_found_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  defp not_found_error?(_error), do: false
end

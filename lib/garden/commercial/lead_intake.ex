defmodule GnomeGarden.Commercial.LeadIntake do
  @moduledoc """
  Composes existing Ash actions into a practical manual lead intake workflow.

  This module intentionally does not become a parallel context layer. It is a
  thin orchestration boundary for operator-entered leads/referrals that need to
  create or update Operations records and then create a Commercial signal plus
  optional follow-up task.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.Organization
  alias GnomeGarden.Operations.OrganizationAffiliation
  alias GnomeGarden.Operations.Person
  alias GnomeGarden.Operations.Site

  @type intake_result :: %{
          organization: Organization.t(),
          sites: [Site.t()],
          contacts: [Person.t()],
          affiliations: [OrganizationAffiliation.t()],
          signal: GnomeGarden.Commercial.Signal.t(),
          task: GnomeGarden.Operations.Task.t() | nil
        }

  @doc """
  Creates a referral lead using existing Ash domain code interfaces.

  Expected attrs shape:

      %{
        organization: %{name: "...", website: "..."},
        sites: [%{name: "..."}],
        contacts: [%{first_name: "...", last_name: "...", email: "...", title: "..."}],
        signal: %{title: "...", description: "..."},
        task: %{title: "..."}
      }
  """
  @spec create_referral_lead(map(), keyword()) :: {:ok, intake_result()} | {:error, term()}
  def create_referral_lead(attrs, opts \\ []) when is_map(attrs) do
    actor = Keyword.get(opts, :actor)

    with {:ok, organization} <- upsert_organization(attrs[:organization] || %{}, actor),
         {:ok, sites} <- upsert_sites(organization, attrs[:sites] || [], actor),
         {:ok, contact_results} <- upsert_contacts(organization, attrs[:contacts] || [], actor),
         {:ok, signal} <-
           create_signal(organization, contact_results, attrs[:signal] || %{}, actor),
         {:ok, task} <-
           maybe_create_task(organization, contact_results, signal, attrs[:task], actor) do
      {:ok,
       %{
         organization: organization,
         sites: sites,
         contacts: Enum.map(contact_results, & &1.person),
         affiliations: Enum.map(contact_results, & &1.affiliation),
         signal: signal,
         task: task
       }}
    end
  end

  defp upsert_organization(attrs, actor) do
    attrs =
      attrs
      |> compact()
      |> Map.put_new(:status, :prospect)
      |> Map.put_new(:organization_kind, :business)
      |> Map.update(:relationship_roles, ["prospect"], &merge_roles(&1, ["prospect"]))

    Operations.create_organization(attrs, actor: actor)
  end

  defp upsert_sites(_organization, [], _actor), do: {:ok, []}

  defp upsert_sites(organization, site_attrs, actor) do
    with {:ok, existing_sites} <-
           Operations.list_sites_for_organization(organization.id, actor: actor) do
      site_attrs
      |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
        case upsert_site(organization, existing_sites, attrs, actor) do
          {:ok, site} -> {:cont, {:ok, [site | acc]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, sites} -> {:ok, Enum.reverse(sites)}
        error -> error
      end
    end
  end

  defp upsert_site(organization, existing_sites, attrs, actor) do
    attrs =
      attrs
      |> compact()
      |> Map.put(:organization_id, organization.id)
      |> Map.put_new(:site_kind, :facility)
      |> Map.put_new(:status, :active)

    name = Map.get(attrs, :name)

    existing_site =
      Enum.find(existing_sites, fn site ->
        String.downcase(site.name || "") == String.downcase(name || "")
      end)

    case existing_site do
      %Site{} = site -> Operations.update_site(site, attrs, actor: actor)
      nil -> Operations.create_site(attrs, actor: actor)
    end
  end

  defp upsert_contacts(_organization, [], _actor), do: {:ok, []}

  defp upsert_contacts(organization, contacts, actor) do
    contacts
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case upsert_contact(organization, attrs, actor) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp upsert_contact(organization, attrs, actor) do
    person_attrs = person_attrs(attrs)

    with {:ok, person} <- upsert_person(person_attrs, actor),
         {:ok, affiliation} <- upsert_affiliation(organization, person, attrs, actor) do
      {:ok, %{person: person, affiliation: affiliation, raw: attrs}}
    end
  end

  defp person_attrs(attrs) do
    attrs
    |> Map.take([
      :first_name,
      :last_name,
      :email,
      :phone,
      :mobile,
      :status,
      :linkedin_url,
      :preferred_contact_method,
      :notes,
      :owner_team_member_id
    ])
    |> compact()
    |> Map.put_new(:status, :active)
  end

  defp upsert_person(%{email: email} = attrs, actor) when is_binary(email) and email != "" do
    case Operations.get_person_by_email(email, actor: actor) do
      {:ok, %Person{} = person} -> Operations.update_person(person, attrs, actor: actor)
      {:error, _error} -> Operations.create_person(attrs, actor: actor)
    end
  end

  defp upsert_person(attrs, actor), do: Operations.create_person(attrs, actor: actor)

  defp upsert_affiliation(organization, person, attrs, actor) do
    affiliation_attrs =
      attrs
      |> Map.take([:title, :department, :contact_roles, :is_primary, :started_on, :notes])
      |> compact()
      |> Map.put(:organization_id, organization.id)
      |> Map.put(:person_id, person.id)
      |> Map.put_new(:status, :active)
      |> Map.update(:contact_roles, ["lead_contact"], &merge_roles(&1, ["lead_contact"]))

    with {:ok, existing} <- existing_affiliation(organization, person, actor) do
      case existing do
        %OrganizationAffiliation{} = affiliation ->
          Operations.update_organization_affiliation(affiliation, affiliation_attrs, actor: actor)

        nil ->
          Operations.create_organization_affiliation(affiliation_attrs, actor: actor)
      end
    end
  end

  defp existing_affiliation(organization, person, actor) do
    case Operations.list_affiliations_for_person(person.id, actor: actor) do
      {:ok, affiliations} ->
        {:ok,
         Enum.find(affiliations, fn affiliation ->
           affiliation.organization_id == organization.id && affiliation.status == :active
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_signal(organization, contact_results, attrs, actor) do
    metadata =
      attrs
      |> Map.get(:metadata, %{})
      |> Map.new()
      |> Map.put("intake_kind", "manual_referral")
      |> Map.put("contact_person_ids", Enum.map(contact_results, & &1.person.id))
      |> Map.put("contact_emails", contact_emails(contact_results))
      |> Map.put("referral_source", Map.get(attrs, :referral_source))
      |> compact_string_keys()

    signal_attrs =
      attrs
      |> Map.drop([:metadata, :referral_source, :suspected_needs])
      |> compact()
      |> Map.put(:organization_id, organization.id)
      |> Map.put_new(:signal_type, :referral)
      |> Map.put_new(:source_channel, :referral)
      |> Map.put_new(:observed_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> Map.put(:metadata, metadata)

    case existing_signal(signal_attrs, actor) do
      {:ok, signal} -> Commercial.update_signal(signal, signal_attrs, actor: actor)
      :not_found -> Commercial.create_signal(signal_attrs, actor: actor)
    end
  end

  defp existing_signal(%{external_ref: external_ref}, actor)
       when is_binary(external_ref) and external_ref != "" do
    case Commercial.get_signal_by_external_ref(external_ref, actor: actor) do
      {:ok, signal} -> {:ok, signal}
      {:error, _error} -> :not_found
    end
  end

  defp existing_signal(_attrs, _actor), do: :not_found

  defp maybe_create_task(_organization, _contact_results, _signal, nil, _actor), do: {:ok, nil}

  defp maybe_create_task(_organization, _contact_results, _signal, %{} = task, _actor)
       when task == %{}, do: {:ok, nil}

  defp maybe_create_task(organization, contact_results, signal, attrs, actor) do
    primary_person =
      contact_results
      |> Enum.find(fn result -> result.affiliation.is_primary end)
      |> case do
        nil -> List.first(contact_results)
        result -> result
      end

    attrs
    |> compact()
    |> Map.put(:origin_domain, :commercial)
    |> Map.put(:origin_resource, "signal")
    |> Map.put(:origin_id, signal.id)
    |> Map.put(:origin_label, signal.title)
    |> Map.put(:origin_url, "/commercial/signals/#{signal.id}")
    |> Map.put(:organization_id, organization.id)
    |> Map.put(:signal_id, signal.id)
    |> maybe_put(:person_id, primary_person && primary_person.person.id)
    |> Map.put_new(:task_type, :call)
    |> Map.put_new(:priority, :high)
    |> Operations.create_task(actor: actor)
  end

  defp contact_emails(contact_results) do
    contact_results
    |> Enum.map(& &1.person.email)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  defp compact_string_keys(map) do
    map
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_roles(existing, additions) do
    (List.wrap(existing) ++ additions)
    |> Enum.reject(&blank?/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?([]), do: true
  defp blank?(%{} = value), do: map_size(value) == 0
  defp blank?(_value), do: false
end

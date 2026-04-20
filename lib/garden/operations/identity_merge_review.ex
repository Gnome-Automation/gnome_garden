defmodule GnomeGarden.Operations.IdentityMergeReview do
  @moduledoc """
  Builds operator-facing duplicate review context for durable organizations and people.
  """

  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.Organization
  alias GnomeGarden.Operations.Person
  alias GnomeGarden.Support.IdentityNormalizer

  @organization_candidate_load [
    :status_variant,
    :people_count,
    :signal_count,
    :pursuit_count,
    :procurement_source_count
  ]
  @person_candidate_load [:full_name, :status_variant, :organization_count, organizations: []]

  @type organization_candidate_review :: %{
          organization: Organization.t(),
          match_reasons: [atom()]
        }

  @type person_candidate_review :: %{
          person: Person.t(),
          match_reasons: [atom()]
        }

  @spec organization_review(Organization.t(), keyword()) ::
          {:ok,
           %{
             name_key: String.t() | nil,
             website_domain: String.t() | nil,
             candidates: [organization_candidate_review()]
           }}
          | {:error, term()}
  def organization_review(%Organization{} = organization, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    name_key = IdentityNormalizer.organization_name_key(organization.name)
    website_domain = organization.website_domain

    with {:ok, name_candidates} <- list_organizations_by_name_key(name_key, actor),
         {:ok, domain_candidate} <- get_organization_by_website_domain(website_domain, actor) do
      candidates =
        [domain_candidate | name_candidates]
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1.id == organization.id))
        |> Enum.reject(&(not is_nil(&1.merged_into_id)))
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(fn candidate ->
          %{
            organization: candidate,
            match_reasons:
              organization_match_reasons(organization, candidate, name_key, website_domain)
          }
        end)
        |> Enum.reject(&(&1.match_reasons == []))

      {:ok, %{name_key: name_key, website_domain: website_domain, candidates: candidates}}
    end
  end

  @spec person_review(Person.t(), keyword()) ::
          {:ok,
           %{
             name_key: String.t() | nil,
             email_domain: String.t() | nil,
             candidates: [person_candidate_review()]
           }}
          | {:error, term()}
  def person_review(%Person{} = person, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    name_key = IdentityNormalizer.person_name_key(person.first_name, person.last_name)
    email_domain = IdentityNormalizer.email_domain(person.email)

    with {:ok, name_candidates} <-
           list_people_by_name_key_and_email_domain(name_key, email_domain, actor),
         {:ok, organization_candidates} <-
           list_people_for_person_organizations(person, name_key, actor) do
      candidates =
        (name_candidates ++ organization_candidates)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1.id == person.id))
        |> Enum.reject(&(not is_nil(&1.merged_into_id)))
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(fn candidate ->
          %{
            person: candidate,
            match_reasons: person_match_reasons(person, candidate, name_key, email_domain)
          }
        end)
        |> Enum.reject(&(&1.match_reasons == []))

      {:ok, %{name_key: name_key, email_domain: email_domain, candidates: candidates}}
    end
  end

  defp list_organizations_by_name_key(nil, _actor), do: {:ok, []}

  defp list_organizations_by_name_key(name_key, actor) do
    Operations.list_organizations_by_name_key(name_key,
      actor: actor,
      load: @organization_candidate_load
    )
  end

  defp get_organization_by_website_domain(nil, _actor), do: {:ok, nil}

  defp get_organization_by_website_domain(website_domain, actor) do
    case Operations.get_organization_by_website_domain(
           website_domain,
           actor: actor,
           load: @organization_candidate_load,
           not_found_error?: false
         ) do
      {:ok, organization} -> {:ok, organization}
      {:error, error} -> {:error, error}
    end
  end

  defp list_people_by_name_key_and_email_domain(nil, _email_domain, _actor), do: {:ok, []}
  defp list_people_by_name_key_and_email_domain(_name_key, nil, _actor), do: {:ok, []}

  defp list_people_by_name_key_and_email_domain(name_key, email_domain, actor) do
    Operations.list_people_by_name_key_and_email_domain(name_key, email_domain,
      actor: actor,
      load: @person_candidate_load
    )
  end

  defp list_people_for_person_organizations(
         %Person{organizations: organizations},
         name_key,
         actor
       )
       when is_list(organizations) do
    organizations
    |> Enum.reduce_while({:ok, []}, fn organization, {:ok, acc} ->
      case Operations.list_people_for_organization_by_name_key(organization.id, name_key,
             actor: actor,
             load: @person_candidate_load
           ) do
        {:ok, candidates} -> {:cont, {:ok, acc ++ candidates}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp list_people_for_person_organizations(_person, _name_key, _actor), do: {:ok, []}

  defp organization_match_reasons(_organization, candidate, name_key, website_domain) do
    [
      if(website_domain && candidate.website_domain == website_domain, do: :website_domain),
      if(name_key && candidate.name_key == name_key, do: :name_key)
    ]
    |> Enum.reject(&is_nil/1)
    |> prioritize_match_reasons(organization_priority_order())
  end

  defp person_match_reasons(person, candidate, name_key, email_domain) do
    person_organization_ids =
      person.organizations
      |> List.wrap()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    candidate_organization_ids =
      candidate.organizations
      |> List.wrap()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    [
      if(name_key && candidate.name_key == name_key, do: :name_key),
      if(email_domain && candidate.email_domain == email_domain, do: :email_domain),
      if(
        MapSet.size(MapSet.intersection(person_organization_ids, candidate_organization_ids)) > 0,
        do: :shared_organization
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> prioritize_match_reasons(person_priority_order())
  end

  defp prioritize_match_reasons(reasons, order) do
    reasons
    |> Enum.uniq()
    |> Enum.sort_by(fn reason -> Enum.find_index(order, &(&1 == reason)) || 999 end)
  end

  defp organization_priority_order, do: [:website_domain, :name_key]
  defp person_priority_order, do: [:name_key, :email_domain, :shared_organization]
end

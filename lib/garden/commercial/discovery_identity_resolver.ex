defmodule GnomeGarden.Commercial.DiscoveryIdentityResolver do
  @moduledoc """
  Resolves durable organization and person matches for discovery intake.
  """

  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.Organization
  alias GnomeGarden.Operations.Person
  alias GnomeGarden.Support.IdentityNormalizer
  alias GnomeGarden.Support.WebIdentity

  @type organization_resolution :: %{
          organization: Organization.t() | nil,
          resolution: atom(),
          website_domain: String.t() | nil,
          name_key: String.t() | nil,
          candidates: list(Organization.t())
        }

  @type person_resolution :: %{
          person: Person.t() | nil,
          resolution: atom(),
          email_domain: String.t() | nil,
          name_key: String.t() | nil,
          candidates: list(Person.t())
        }

  @organization_candidate_load [:status_variant, :people_count, :signal_count]
  @person_candidate_load [:full_name, :status_variant, organizations: []]

  @spec resolve_organization(map(), keyword()) ::
          {:ok, organization_resolution()} | {:error, term()}
  def resolve_organization(attrs, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    website = WebIdentity.normalize_website(Map.get(attrs, :website))
    website_domain = WebIdentity.website_domain(website)
    name_key = IdentityNormalizer.organization_name_key(Map.get(attrs, :name))

    with {:ok, exact_match} <- match_organization_by_website_domain(website_domain, actor) do
      cond do
        exact_match ->
          {:ok,
           %{
             organization: update_matched_organization(exact_match, attrs, actor),
             resolution: :website_domain,
             website_domain: website_domain,
             name_key: name_key,
             candidates: []
           }}

        is_nil(name_key) ->
          create_organization_resolution(attrs, website_domain, name_key, actor)

        true ->
          resolve_organization_by_name_key(attrs, website_domain, name_key, actor)
      end
    end
  end

  @spec resolve_person(map(), Organization.t() | nil, keyword()) ::
          {:ok, person_resolution()} | {:error, term()}
  def resolve_person(attrs, organization, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    email = blank_to_nil(Map.get(attrs, :email))
    email_domain = IdentityNormalizer.email_domain(email)
    {first_name, last_name} = normalized_contact_names(attrs)
    name_key = IdentityNormalizer.person_name_key(first_name, last_name)

    cond do
      is_nil(email) and is_nil(name_key) ->
        {:ok,
         %{
           person: nil,
           resolution: :none,
           email_domain: email_domain,
           name_key: name_key,
           candidates: []
         }}

      true ->
        with {:ok, exact_match} <- match_person_by_email(email, actor) do
          cond do
            exact_match ->
              {:ok,
               %{
                 person: update_matched_person(exact_match, first_name, last_name, attrs, actor),
                 resolution: :email,
                 email_domain: email_domain,
                 name_key: name_key,
                 candidates: []
               }}

            true ->
              resolve_person_without_exact_email(
                attrs,
                first_name,
                last_name,
                email_domain,
                name_key,
                organization,
                actor
              )
          end
        end
    end
  end

  @spec organization_candidates(map(), keyword()) ::
          {:ok, list(Organization.t())} | {:error, term()}
  def organization_candidates(attrs, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    website_domain = attrs |> Map.get(:website) |> WebIdentity.website_domain()
    name_key = IdentityNormalizer.organization_name_key(Map.get(attrs, :name))

    with {:ok, domain_candidate} <- match_organization_by_website_domain(website_domain, actor),
         {:ok, name_candidates} <- list_organizations_by_name_key(name_key, actor) do
      {:ok,
       [domain_candidate | name_candidates]
       |> Enum.reject(&is_nil/1)
       |> Enum.uniq_by(& &1.id)}
    end
  end

  @spec person_candidates(map(), Organization.t() | nil, keyword()) ::
          {:ok, list(Person.t())} | {:error, term()}
  def person_candidates(attrs, organization, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    email = blank_to_nil(Map.get(attrs, :email))
    email_domain = IdentityNormalizer.email_domain(email)
    {first_name, last_name} = normalized_contact_names(attrs)
    name_key = IdentityNormalizer.person_name_key(first_name, last_name)

    if is_nil(name_key) do
      {:ok, []}
    else
      with {:ok, email_candidate} <- match_person_by_email(email, actor),
           {:ok, org_candidates} <-
             list_people_for_organization_name_key(organization, name_key, actor),
           {:ok, domain_candidates} <-
             list_people_by_name_key_and_email_domain(name_key, email_domain, actor) do
        {:ok,
         [email_candidate | org_candidates ++ domain_candidates]
         |> Enum.reject(&is_nil/1)
         |> Enum.uniq_by(& &1.id)}
      end
    end
  end

  @spec target_contact_snapshot(map()) :: map() | nil
  def target_contact_snapshot(params) do
    snapshot =
      %{
        first_name:
          blank_to_nil(Map.get(params, :contact_first_name) || Map.get(params, :first_name)),
        last_name:
          blank_to_nil(Map.get(params, :contact_last_name) || Map.get(params, :last_name)),
        title: blank_to_nil(Map.get(params, :contact_title) || Map.get(params, :title)),
        email: blank_to_nil(Map.get(params, :contact_email) || Map.get(params, :email)),
        phone: blank_to_nil(Map.get(params, :contact_phone) || Map.get(params, :phone))
      }
      |> reject_nil_values()

    if snapshot == %{}, do: nil, else: snapshot
  end

  @spec target_identity_review(organization_resolution(), person_resolution()) :: map()
  def target_identity_review(organization_resolution, person_resolution) do
    %{
      organization: %{
        resolution: organization_resolution.resolution,
        website_domain: organization_resolution.website_domain,
        name_key: organization_resolution.name_key,
        candidate_ids: Enum.map(organization_resolution.candidates, & &1.id)
      },
      contact_person: %{
        resolution: person_resolution.resolution,
        email_domain: person_resolution.email_domain,
        name_key: person_resolution.name_key,
        candidate_ids: Enum.map(person_resolution.candidates, & &1.id)
      }
    }
  end

  @spec target_review_context(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def target_review_context(target_account, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    organization_attrs = %{name: target_account.name, website: target_account.website}
    organization = Map.get(target_account, :organization)

    snapshot =
      metadata_value(target_account.metadata, :contact_snapshot) ||
        metadata_value(target_account.metadata, "contact_snapshot")

    person_attrs =
      case snapshot do
        snapshot when is_map(snapshot) ->
          %{
            first_name: metadata_value(snapshot, :first_name),
            last_name: metadata_value(snapshot, :last_name),
            email: metadata_value(snapshot, :email),
            phone: metadata_value(snapshot, :phone),
            title: metadata_value(snapshot, :title)
          }

        _ ->
          %{}
      end

    with {:ok, organization_candidates} <-
           organization_candidates(organization_attrs, actor: actor),
         {:ok, person_candidates} <- person_candidates(person_attrs, organization, actor: actor) do
      {:ok,
       %{
         contact_snapshot: target_contact_snapshot(person_attrs),
         organization_candidates:
           Enum.reject(organization_candidates, &(&1.id == target_account.organization_id)),
         person_candidates:
           Enum.reject(person_candidates, &(&1.id == target_account.contact_person_id))
       }}
    end
  end

  defp resolve_organization_by_name_key(attrs, website_domain, name_key, actor) do
    with {:ok, candidates} <- list_organizations_by_name_key(name_key, actor) do
      case candidates do
        [] ->
          create_organization_resolution(attrs, website_domain, name_key, actor)

        [candidate] ->
          case organization_name_match_resolution(candidate, website_domain) do
            :match ->
              {:ok,
               %{
                 organization: update_matched_organization(candidate, attrs, actor),
                 resolution: :name_key,
                 website_domain: website_domain,
                 name_key: name_key,
                 candidates: []
               }}

            :ambiguous ->
              {:ok,
               %{
                 organization: nil,
                 resolution: :ambiguous,
                 website_domain: website_domain,
                 name_key: name_key,
                 candidates: candidates
               }}
          end

        many ->
          {:ok,
           %{
             organization: nil,
             resolution: :ambiguous,
             website_domain: website_domain,
             name_key: name_key,
             candidates: many
           }}
      end
    end
  end

  defp create_organization_resolution(attrs, website_domain, name_key, actor) do
    create_attrs =
      attrs
      |> Map.take([:name, :status, :relationship_roles, :website, :primary_region, :notes])
      |> reject_nil_values()

    create_result =
      case website_domain do
        nil ->
          Operations.create_organization(create_attrs, actor: actor)

        _ ->
          Operations.create_organization(
            create_attrs,
            actor: actor,
            upsert?: true,
            upsert_identity: :unique_website_domain,
            upsert_fields: [:website, :primary_region, :notes, :relationship_roles]
          )
      end

    case create_result do
      {:ok, organization} ->
        {:ok,
         %{
           organization: organization,
           resolution: :created,
           website_domain: website_domain,
           name_key: name_key,
           candidates: []
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp resolve_person_without_exact_email(
         attrs,
         first_name,
         last_name,
         email_domain,
         name_key,
         organization,
         actor
       ) do
    with {:ok, organization_candidates} <-
           list_people_for_organization_name_key(organization, name_key, actor),
         {:ok, domain_candidates} <-
           list_people_by_name_key_and_email_domain(name_key, email_domain, actor) do
      cond do
        length(organization_candidates) == 1 ->
          [candidate] = organization_candidates

          {:ok,
           %{
             person: update_matched_person(candidate, first_name, last_name, attrs, actor),
             resolution: :organization_name,
             email_domain: email_domain,
             name_key: name_key,
             candidates: []
           }}

        length(organization_candidates) > 1 ->
          {:ok,
           %{
             person: nil,
             resolution: :ambiguous,
             email_domain: email_domain,
             name_key: name_key,
             candidates: organization_candidates
           }}

        length(domain_candidates) == 1 ->
          [candidate] = domain_candidates

          {:ok,
           %{
             person: update_matched_person(candidate, first_name, last_name, attrs, actor),
             resolution: :email_domain_name,
             email_domain: email_domain,
             name_key: name_key,
             candidates: []
           }}

        length(domain_candidates) > 1 ->
          {:ok,
           %{
             person: nil,
             resolution: :ambiguous,
             email_domain: email_domain,
             name_key: name_key,
             candidates: domain_candidates
           }}

        should_create_person?(attrs, first_name, last_name, organization) ->
          create_person_resolution(attrs, first_name, last_name, email_domain, name_key, actor)

        true ->
          {:ok,
           %{
             person: nil,
             resolution: :unresolved,
             email_domain: email_domain,
             name_key: name_key,
             candidates: []
           }}
      end
    end
  end

  defp create_person_resolution(attrs, first_name, last_name, email_domain, name_key, actor) do
    create_attrs =
      %{
        first_name: first_name,
        last_name: last_name,
        email: blank_to_nil(Map.get(attrs, :email)),
        phone: blank_to_nil(Map.get(attrs, :phone)),
        notes: blank_to_nil(Map.get(attrs, :notes))
      }
      |> reject_nil_values()

    create_result =
      case blank_to_nil(Map.get(attrs, :email)) do
        nil ->
          Operations.create_person(create_attrs, actor: actor)

        _email ->
          Operations.create_person(
            create_attrs,
            actor: actor,
            upsert?: true,
            upsert_identity: :unique_email,
            upsert_fields: [:first_name, :last_name, :phone, :notes]
          )
      end

    case create_result do
      {:ok, person} ->
        {:ok,
         %{
           person: person,
           resolution: :created,
           email_domain: email_domain,
           name_key: name_key,
           candidates: []
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp match_organization_by_website_domain(nil, _actor), do: {:ok, nil}

  defp match_organization_by_website_domain(website_domain, actor) do
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

  defp match_person_by_email(nil, _actor), do: {:ok, nil}

  defp match_person_by_email(email, actor) do
    case Operations.get_person_by_email(
           email,
           actor: actor,
           load: @person_candidate_load,
           not_found_error?: false
         ) do
      {:ok, person} -> {:ok, person}
      {:error, error} -> {:error, error}
    end
  end

  defp list_organizations_by_name_key(nil, _actor), do: {:ok, []}

  defp list_organizations_by_name_key(name_key, actor) do
    Operations.list_organizations_by_name_key(name_key,
      actor: actor,
      load: @organization_candidate_load
    )
  end

  defp list_people_for_organization_name_key(nil, _name_key, _actor), do: {:ok, []}
  defp list_people_for_organization_name_key(_organization, nil, _actor), do: {:ok, []}

  defp list_people_for_organization_name_key(organization, name_key, actor) do
    Operations.list_people_for_organization_by_name_key(organization.id, name_key,
      actor: actor,
      load: @person_candidate_load
    )
  end

  defp list_people_by_name_key_and_email_domain(nil, _email_domain, _actor), do: {:ok, []}
  defp list_people_by_name_key_and_email_domain(_name_key, nil, _actor), do: {:ok, []}

  defp list_people_by_name_key_and_email_domain(name_key, email_domain, actor) do
    Operations.list_people_by_name_key_and_email_domain(name_key, email_domain,
      actor: actor,
      load: @person_candidate_load
    )
  end

  defp organization_name_match_resolution(
         %Organization{website_domain: existing_domain},
         website_domain
       )
       when is_binary(existing_domain) and is_binary(website_domain) and
              existing_domain != website_domain,
       do: :ambiguous

  defp organization_name_match_resolution(_organization, _website_domain), do: :match

  defp update_matched_organization(organization, attrs, actor) do
    update_attrs =
      %{
        website: updated_website(organization.website, Map.get(attrs, :website)),
        primary_region: organization.primary_region || Map.get(attrs, :primary_region),
        notes: merge_multiline_text(organization.notes, Map.get(attrs, :notes)),
        relationship_roles:
          merge_roles(organization.relationship_roles, Map.get(attrs, :relationship_roles))
      }
      |> reject_nil_values()

    case update_attrs do
      %{} ->
        organization

      _ ->
        {:ok, updated} = Operations.update_organization(organization, update_attrs, actor: actor)
        updated
    end
  end

  defp update_matched_person(person, first_name, last_name, attrs, actor) do
    incoming_email = blank_to_nil(Map.get(attrs, :email))

    update_attrs =
      %{
        first_name: person.first_name || first_name,
        last_name: person.last_name || last_name,
        email: if(is_nil(person.email), do: incoming_email, else: nil),
        phone: person.phone || blank_to_nil(Map.get(attrs, :phone)),
        notes: merge_multiline_text(person.notes, blank_to_nil(Map.get(attrs, :notes)))
      }
      |> reject_nil_values()

    case update_attrs do
      %{} ->
        person

      _ ->
        {:ok, updated} = Operations.update_person(person, update_attrs, actor: actor)
        updated
    end
  end

  defp normalized_contact_names(attrs) do
    first_name = blank_to_nil(Map.get(attrs, :first_name))
    last_name = blank_to_nil(Map.get(attrs, :last_name))
    email = blank_to_nil(Map.get(attrs, :email))

    cond do
      first_name && last_name ->
        {first_name, last_name}

      email ->
        case names_from_email(email) do
          {derived_first, derived_last}
          when not is_nil(derived_first) and not is_nil(derived_last) ->
            {first_name || derived_first, last_name || derived_last}

          _ ->
            {first_name, last_name}
        end

      true ->
        {first_name, last_name}
    end
  end

  defp names_from_email(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> case do
      nil ->
        {nil, nil}

      local_part ->
        local_part
        |> String.split(~r/[._-]+/, trim: true)
        |> case do
          [first, last | _rest] -> {String.capitalize(first), String.capitalize(last)}
          _ -> {nil, nil}
        end
    end
  end

  defp should_create_person?(attrs, first_name, last_name, organization) do
    email = blank_to_nil(Map.get(attrs, :email))

    cond do
      email && first_name && last_name -> true
      organization && first_name && last_name -> true
      true -> false
    end
  end

  defp updated_website(existing, _incoming) when is_binary(existing), do: existing
  defp updated_website(nil, incoming), do: WebIdentity.normalize_website(incoming)
  defp updated_website(existing, _incoming), do: existing

  defp merge_roles(existing, incoming) do
    (List.wrap(existing) ++ List.wrap(incoming))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      roles -> roles
    end
  end

  defp merge_multiline_text(existing, incoming) do
    [blank_to_nil(existing), blank_to_nil(incoming)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join("\n\n")
    |> blank_to_nil()
  end

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp metadata_value(metadata, key) when is_map(metadata),
    do: Map.get(metadata, key) || Map.get(metadata, to_string(key))

  defp metadata_value(_metadata, _key), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

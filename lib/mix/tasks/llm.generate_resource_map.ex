defmodule Mix.Tasks.Llm.GenerateResourceMap do
  use Mix.Task

  alias Spark.Dsl.Extension

  @shortdoc "Generate a machine-oriented Ash resource map for Codex"
  @requirements ["app.config"]

  @moduledoc """
  Generates `docs/llm/generated/resources.json` from the configured Ash domains.

  This task is intended to keep a low-drift, implemented-only map of the data
  model and action surface in the repository for Codex and similar agents.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    project_root = File.cwd!()
    app = Mix.Project.config()[:app]

    domains =
      app
      |> Application.fetch_env!(:ash_domains)
      |> Enum.sort_by(&inspect/1)

    domain_entries =
      Enum.map(domains, fn domain ->
        Code.ensure_compiled!(domain)
        serialize_domain(domain, project_root)
      end)

    resources =
      domain_entries
      |> Enum.flat_map(& &1.resources)
      |> Enum.sort_by(& &1.module)

    payload = %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      generator: "mix llm.generate_resource_map",
      otp_app: Atom.to_string(app),
      ash_domains_config_path: "config/config.exs",
      domain_count: length(domain_entries),
      resource_count: length(resources),
      authoritative_sources: %{
        implemented_map: "docs/llm/generated/resources.json",
        implementation_code: "lib/garden",
        configured_domains: "config/config.exs"
      },
      domains: domain_entries,
      resources_by_module:
        Map.new(resources, fn resource ->
          {resource.module, resource}
        end),
      resources_by_table:
        resources
        |> Enum.reject(&is_nil(&1.table))
        |> Map.new(fn resource ->
          {resource.table, resource.module}
        end)
    }

    output_path = Path.join([project_root, "docs", "llm", "generated", "resources.json"])

    output_path
    |> Path.dirname()
    |> File.mkdir_p!()

    output_path
    |> File.write!(Jason.encode_to_iodata!(payload, pretty: true))

    Mix.shell().info("Generated #{Path.relative_to(output_path, project_root)}")
  end

  defp serialize_domain(domain, project_root) do
    resource_references =
      domain
      |> Ash.Domain.Info.resource_references()
      |> Enum.sort_by(fn reference -> inspect(reference.resource) end)

    code_interfaces_by_resource =
      Map.new(resource_references, fn reference ->
        {reference.resource, Enum.map(reference.definitions, &serialize_interface/1)}
      end)

    resources =
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.sort_by(&inspect/1)
      |> Enum.map(fn resource ->
        Code.ensure_compiled!(resource)

        serialize_resource(
          resource,
          domain,
          Map.get(code_interfaces_by_resource, resource, []),
          project_root
        )
      end)

    %{
      module: inspect(domain),
      name: Module.split(domain) |> List.last(),
      description: module_doc(domain),
      source_path: source_path(domain, project_root),
      resource_count: length(resources),
      resources: resources
    }
  end

  defp serialize_resource(resource, domain, code_interfaces, project_root) do
    extensions = resource_extensions(resource)
    state_machine? = "AshStateMachine" in extensions

    relationships =
      resource
      |> Ash.Resource.Info.relationships()
      |> Enum.sort_by(&Atom.to_string(&1.name))
      |> Enum.map(&serialize_relationship(&1, domain))

    %{
      module: inspect(resource),
      name: Module.split(resource) |> List.last(),
      domain: inspect(domain),
      description: module_doc(resource),
      source_path: source_path(resource, project_root),
      table: AshPostgres.DataLayer.Info.table(resource),
      schema: AshPostgres.DataLayer.Info.schema(resource),
      extensions: extensions,
      primary_key: Enum.map(Ash.Resource.Info.primary_key(resource), &format_atom/1),
      attributes:
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.sort_by(&Atom.to_string(&1.name))
        |> Enum.map(&serialize_attribute/1),
      relationships: relationships,
      cross_domain_relationships:
        Enum.filter(relationships, fn relationship ->
          relationship.destination_domain != inspect(domain)
        end),
      identities:
        resource
        |> Ash.Resource.Info.identities()
        |> Enum.sort_by(&Atom.to_string(&1.name))
        |> Enum.map(&serialize_identity/1),
      actions:
        resource
        |> Ash.Resource.Info.actions()
        |> Enum.sort_by(&Atom.to_string(&1.name))
        |> Enum.map(&serialize_action/1),
      calculations:
        resource
        |> Ash.Resource.Info.calculations()
        |> Enum.sort_by(&Atom.to_string(&1.name))
        |> Enum.map(&serialize_calculation/1),
      aggregates:
        resource
        |> Ash.Resource.Info.aggregates()
        |> Enum.sort_by(&Atom.to_string(&1.name))
        |> Enum.map(&serialize_aggregate/1),
      code_interfaces: code_interfaces,
      state_machine: serialize_state_machine(resource, state_machine?)
    }
  end

  defp serialize_attribute(attribute) do
    %{
      name: format_atom(attribute.name),
      type: inspect(attribute.type),
      allow_nil?: attribute.allow_nil?,
      public?: attribute.public?,
      writable?: attribute.writable?,
      generated?: attribute.generated?,
      primary_key?: attribute.primary_key?,
      sensitive?: attribute.sensitive?,
      description: attribute.description,
      source: attribute.source && format_atom(attribute.source),
      constraints: normalize_term(attribute.constraints),
      default: serialize_default(attribute.default),
      update_default: serialize_default(attribute.update_default)
    }
  end

  defp serialize_identity(identity) do
    %{
      name: format_atom(identity.name),
      keys: Enum.map(identity.keys, &format_atom/1),
      description: identity.description,
      nils_distinct?: identity.nils_distinct?,
      all_tenants?: identity.all_tenants?,
      where: identity.where && inspect(identity.where)
    }
  end

  defp serialize_relationship(relationship, domain) do
    %{
      name: format_atom(relationship.name),
      type: format_atom(relationship.type),
      cardinality: format_atom(relationship.cardinality),
      public?: relationship.public?,
      writable?: Map.get(relationship, :writable?),
      allow_nil?: Map.get(relationship, :allow_nil?),
      description: relationship.description,
      source_attribute:
        relationship.source_attribute && format_atom(relationship.source_attribute),
      destination: inspect(relationship.destination),
      destination_domain:
        relationship.destination
        |> Ash.Resource.Info.domain()
        |> inspect(),
      destination_attribute:
        relationship.destination_attribute && format_atom(relationship.destination_attribute),
      through:
        relationship
        |> Map.get(:through)
        |> maybe_module(),
      join_relationship:
        relationship
        |> Map.get(:join_relationship)
        |> maybe_atom(),
      source_attribute_on_join_resource:
        relationship
        |> Map.get(:source_attribute_on_join_resource)
        |> maybe_atom(),
      destination_attribute_on_join_resource:
        relationship
        |> Map.get(:destination_attribute_on_join_resource)
        |> maybe_atom(),
      cross_domain?: Ash.Resource.Info.domain(relationship.destination) != domain
    }
  end

  defp serialize_action(action) do
    base = %{
      name: format_atom(action.name),
      type: format_atom(action.type),
      primary?: Map.get(action, :primary?),
      public?: Map.get(action, :public?),
      description: Map.get(action, :description),
      transaction?: Map.get(action, :transaction?),
      touches_resources: Enum.map(Map.get(action, :touches_resources, []), &inspect/1),
      arguments: Enum.map(Map.get(action, :arguments, []), &serialize_argument/1)
    }

    case action.type do
      :read ->
        Map.merge(base, %{
          get?: action.get?,
          get_by: normalize_term(action.get_by),
          manual?: not is_nil(action.manual),
          pagination: serialize_pagination(action.pagination)
        })

      :create ->
        Map.merge(base, %{
          accept: normalize_term(action.accept),
          require_attributes: normalize_term(action.require_attributes),
          allow_nil_input: normalize_term(action.allow_nil_input),
          upsert?: action.upsert?,
          upsert_identity: maybe_atom(action.upsert_identity)
        })

      :update ->
        Map.merge(base, %{
          accept: normalize_term(action.accept),
          require_attributes: normalize_term(action.require_attributes),
          allow_nil_input: normalize_term(action.allow_nil_input),
          manual?: not is_nil(action.manual),
          require_atomic?: action.require_atomic?
        })

      :destroy ->
        Map.merge(base, %{
          accept: normalize_term(action.accept),
          require_attributes: normalize_term(action.require_attributes),
          allow_nil_input: normalize_term(action.allow_nil_input),
          soft?: action.soft?,
          manual?: not is_nil(action.manual),
          require_atomic?: action.require_atomic?
        })

      :action ->
        Map.merge(base, %{
          allow_nil?: action.allow_nil?,
          returns: inspect(action.returns),
          constraints: normalize_term(action.constraints)
        })
    end
  end

  defp serialize_argument(argument) do
    %{
      name: format_atom(argument.name),
      type: inspect(argument.type),
      allow_nil?: argument.allow_nil?,
      public?: argument.public?,
      sensitive?: argument.sensitive?,
      description: argument.description,
      constraints: normalize_term(argument.constraints),
      default: serialize_default(argument.default)
    }
  end

  defp serialize_calculation(calculation) do
    %{
      name: format_atom(calculation.name),
      type: inspect(calculation.type),
      public?: calculation.public?,
      allow_nil?: calculation.allow_nil?,
      description: calculation.description,
      async?: calculation.async?,
      load: normalize_term(calculation.load)
    }
  end

  defp serialize_aggregate(aggregate) do
    %{
      name: format_atom(aggregate.name),
      kind: normalize_term(aggregate.kind),
      type: inspect(aggregate.type),
      public?: aggregate.public?,
      description: aggregate.description,
      relationship_path: normalize_term(aggregate.relationship_path),
      field: aggregate.field && format_atom(aggregate.field),
      default: serialize_default(aggregate.default)
    }
  end

  defp serialize_interface(%Ash.Resource.Interface{} = interface) do
    %{
      kind: "action",
      name: format_atom(interface.name),
      action: format_atom(interface.action),
      args: normalize_term(interface.args),
      get?: interface.get?,
      get_by: normalize_term(interface.get_by),
      get_by_identity: maybe_atom(interface.get_by_identity),
      require_reference?: interface.require_reference?
    }
  end

  defp serialize_interface(%Ash.Resource.CalculationInterface{} = interface) do
    %{
      kind: "calculation",
      name: format_atom(interface.name),
      calculation: format_atom(interface.calculation),
      args: normalize_term(interface.args),
      exclude_inputs: normalize_term(interface.exclude_inputs)
    }
  end

  defp serialize_pagination(false), do: nil
  defp serialize_pagination(nil), do: nil

  defp serialize_pagination(pagination) do
    %{
      keyset?: pagination.keyset?,
      offset?: pagination.offset?,
      default_limit: pagination.default_limit,
      max_page_size: pagination.max_page_size,
      required?: pagination.required?,
      countable: normalize_term(pagination.countable)
    }
  end

  defp serialize_state_machine(_resource, false), do: nil

  defp serialize_state_machine(resource, true) do
    %{
      state_attribute:
        resource
        |> AshStateMachine.Info.state_machine_state_attribute()
        |> unwrap_info_result()
        |> maybe_atom(),
      initial_states:
        resource
        |> AshStateMachine.Info.state_machine_initial_states()
        |> unwrap_info_result()
        |> normalize_term(),
      default_initial_state:
        resource
        |> AshStateMachine.Info.state_machine_default_initial_state()
        |> unwrap_info_result()
        |> maybe_atom(),
      all_states:
        resource
        |> AshStateMachine.Info.state_machine_all_states()
        |> normalize_term(),
      transitions:
        resource
        |> AshStateMachine.Info.state_machine_transitions()
        |> Enum.map(fn transition ->
          %{
            action: format_atom(transition.action),
            from: normalize_term(transition.from),
            to: normalize_term(transition.to)
          }
        end)
    }
  end

  defp resource_extensions(resource) do
    resource
    |> Extension.get_persisted(:spark_extensions, [])
    |> Enum.map(&inspect/1)
    |> Enum.sort()
  end

  defp source_path(module, project_root) do
    case module.module_info(:compile)[:source] do
      nil ->
        nil

      source ->
        source
        |> List.to_string()
        |> Path.relative_to(project_root)
    end
  end

  defp module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} when is_binary(doc) -> blank_to_nil(doc)
      {:docs_v1, _, _, _, :none, _, _} -> nil
      _ -> nil
    end
  end

  defp serialize_default(nil), do: nil

  defp serialize_default(value) do
    %{
      value: normalize_term(value),
      computed?: is_function(value) or is_tuple(value)
    }
  end

  defp normalize_term(value) when is_nil(value) or is_boolean(value) or is_number(value) do
    value
  end

  defp normalize_term(value) when is_binary(value), do: value

  defp normalize_term(value) when is_atom(value), do: format_atom(value)

  defp normalize_term(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {key, item} ->
        %{
          key: format_atom(key),
          value: normalize_term(item)
        }
      end)
    else
      Enum.map(value, &normalize_term/1)
    end
  end

  defp normalize_term(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize_term(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_term(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_term(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize_term(%Regex{} = value), do: Regex.source(value)
  defp normalize_term(%_{} = value), do: inspect(value)

  defp normalize_term(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      {normalize_map_key(key), normalize_term(item)}
    end)
  end

  defp normalize_term(value) when is_tuple(value) do
    %{tuple: value |> Tuple.to_list() |> Enum.map(&normalize_term/1)}
  end

  defp normalize_term(value), do: inspect(value)

  defp normalize_map_key(key) when is_atom(key), do: format_atom(key)
  defp normalize_map_key(key), do: to_string(key)

  defp format_atom(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> case do
      "Elixir." <> _ -> inspect(atom)
      string -> string
    end
  end

  defp maybe_atom(nil), do: nil
  defp maybe_atom(atom) when is_atom(atom), do: format_atom(atom)
  defp maybe_atom(other), do: normalize_term(other)

  defp maybe_module(nil), do: nil
  defp maybe_module(module) when is_atom(module), do: inspect(module)
  defp maybe_module(other), do: normalize_term(other)

  defp unwrap_info_result({:ok, value}), do: value
  defp unwrap_info_result(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "" do
      nil
    else
      value
    end
  end
end

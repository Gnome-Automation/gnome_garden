defmodule GnomeGarden.Agents.TemplateCatalog do
  @moduledoc """
  Synchronizes persisted agent template records with the in-memory registry.

  This removes any operator dependency on Ash Admin just to create
  `AgentDeployment` records.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.Templates

  @spec sync_templates() :: [GnomeGarden.Agents.Agent.t()]
  def sync_templates do
    existing_by_name =
      Agents.list_agent_templates!()
      |> Map.new(fn template -> {template.name, template} end)

    Templates.list()
    |> Enum.sort_by(fn {name, _config} -> name end)
    |> Enum.map(fn {name, config} ->
      attrs = attrs_for(name, config)

      case existing_by_name[name] do
        nil ->
          Agents.create_agent_template!(attrs)

        existing ->
          maybe_update(existing, attrs)
      end
    end)
  end

  @spec template_options() :: [{String.t(), Ecto.UUID.t()}]
  def template_options do
    sync_templates()
    |> Enum.map(fn template ->
      {"#{humanize(template.name)} (#{template.model})", template.id}
    end)
  end

  defp maybe_update(template, attrs) do
    update_attrs =
      attrs
      |> Map.take([:description, :model, :max_iterations, :tools, :system_prompt])
      |> Enum.reject(fn {key, value} -> Map.get(template, key) == value end)
      |> Map.new()

    if map_size(update_attrs) == 0 do
      template
    else
      Agents.update_agent_template!(template, update_attrs)
    end
  end

  defp attrs_for(name, config) do
    %{
      name: name,
      template: name,
      description: config.description,
      model: config.model,
      max_iterations: config.max_iterations,
      tools: [],
      system_prompt: nil
    }
  end

  defp humanize(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

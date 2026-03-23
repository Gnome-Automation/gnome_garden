defmodule GnomeHub.Agents.Tools.RunSkill do
  @moduledoc """
  Execute a registered skill by name.

  Skills are multi-step workflows defined in YAML that combine
  multiple tools into higher-level operations.
  """

  use Jido.Action,
    name: "run_skill",
    description: "Execute a skill by name. Skills are multi-step workflows that combine tools.",
    schema: [
      skill_name: [type: :string, required: true, doc: "Name of the skill to execute"],
      params: [type: :map, default: %{}, doc: "Parameters to pass to the skill"]
    ]

  @impl true
  def run(params, _context) do
    skill_name = Map.get(params, :skill_name) || Map.get(params, "skill_name")
    skill_params = Map.get(params, :params) || Map.get(params, "params", %{})

    # Load skill from YAML file in .gnome_hub/skills/
    skill_path = Path.join([".gnome_hub", "skills", "#{skill_name}.yaml"])

    case load_skill(skill_path) do
      {:ok, skill_def} ->
        {:ok, %{
          skill: skill_name,
          definition: skill_def,
          params: skill_params,
          note: "Skill loaded. Execute steps manually or integrate with jido_composer."
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_skill(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, yaml} -> {:ok, yaml}
          {:error, _} -> {:error, "Invalid YAML in skill file: #{path}"}
        end

      {:error, :enoent} ->
        {:error, "Skill file not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read skill file: #{inspect(reason)}"}
    end
  end
end

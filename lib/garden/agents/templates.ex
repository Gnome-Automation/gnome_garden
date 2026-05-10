defmodule GnomeGarden.Agents.Templates do
  @moduledoc """
  Registry of agent templates for the swarm system.

  Each template maps a name to a configuration that specifies
  which worker agent module to use and its operational parameters.
  """

  @templates %{
    "base" => %{
      module: GnomeGarden.Agents.Workers.Base,
      description: "Full-capability agent with all tools including swarm orchestration",
      model: :fast,
      max_iterations: 25
    },
    "coder" => %{
      module: GnomeGarden.Agents.Workers.Coder,
      description: "Full-capability coding agent with all tools",
      model: :fast,
      max_iterations: 25
    },
    "test_runner" => %{
      module: GnomeGarden.Agents.Workers.TestRunner,
      description: "Runs tests and reports results (read-only)",
      model: :fast,
      max_iterations: 15
    },
    "reviewer" => %{
      module: GnomeGarden.Agents.Workers.Reviewer,
      description: "Reviews code changes for bugs and style issues (read-only)",
      model: :fast,
      max_iterations: 15
    },
    "docs_writer" => %{
      module: GnomeGarden.Agents.Workers.DocsWriter,
      description: "Writes documentation and comments",
      model: :fast,
      max_iterations: 15
    },
    "researcher" => %{
      module: GnomeGarden.Agents.Workers.Researcher,
      description: "Explores and analyzes codebase structure",
      model: :fast,
      max_iterations: 15
    },
    "refactorer" => %{
      module: GnomeGarden.Agents.Workers.Refactorer,
      description: "Refactors code with full tool access",
      model: :fast,
      max_iterations: 25
    },
    # Procurement and commercial discovery workers
    "bid_scanner" => %{
      module: GnomeGarden.Agents.Workers.Procurement.BidScanner,
      description: "Scans procurement portals for bid opportunities",
      model: :fast,
      max_iterations: 30
    },
    "procurement_source_scan" => %{
      module: GnomeGarden.Agents.Workers.Procurement.SourceScan,
      description: "Runs a deterministic procurement scan for a single source",
      model: :fast,
      max_iterations: 1
    },
    "source_discovery" => %{
      module: GnomeGarden.Agents.Workers.Procurement.SourceDiscovery,
      description: "Discovers new procurement portals to monitor",
      model: :fast,
      max_iterations: 25
    },
    "smart_scanner" => %{
      module: GnomeGarden.Agents.Workers.Procurement.SmartScanner,
      description: "Autonomous browser-based scanner that figures out any site",
      model: :capable,
      max_iterations: 25
    },
    "target_discovery" => %{
      module: GnomeGarden.Agents.Workers.Commercial.TargetDiscovery,
      description: "Discovers target companies and saves reviewable discovery findings",
      model: :fast,
      max_iterations: 30
    },
    # Pi sidecar workers (run pi --mode rpc as a managed child process)
    "pi_bid_scanner" => %{
      module: GnomeGarden.Agents.Workers.PiProcess,
      description: "Pi-powered bid scanner with browser automation and PlanetBids extraction",
      model: :fast,
      max_iterations: 1
    },
    "pi_target_discovery" => %{
      module: GnomeGarden.Agents.Workers.PiProcess,
      description: "Pi-powered commercial target discovery across directories and job boards",
      model: :fast,
      max_iterations: 1
    },
    "pi_source_discovery" => %{
      module: GnomeGarden.Agents.Workers.PiProcess,
      description: "Pi-powered procurement portal discovery",
      model: :fast,
      max_iterations: 1
    }
  }

  @doc "Returns the config map for a named template."
  @spec get(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(name) do
    case Map.get(@templates, name) do
      nil -> {:error, "Unknown template '#{name}'. Available: #{Enum.join(names(), ", ")}"}
      template -> {:ok, template}
    end
  end

  @doc "Returns all templates as a map keyed by name."
  @spec list() :: %{String.t() => map()}
  def list, do: @templates

  @doc "Returns all template names."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@templates)

  @doc "Returns true if a template with the given name exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(name), do: Map.has_key?(@templates, name)
end

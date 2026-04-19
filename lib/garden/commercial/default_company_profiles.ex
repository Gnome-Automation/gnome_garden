defmodule GnomeGarden.Commercial.DefaultCompanyProfiles do
  @moduledoc """
  Idempotent bootstrap for the primary company profile.

  This gives the app a durable, operator-editable source of truth for company
  positioning without forcing that knowledge to live only in markdown or agent
  runtime memory.
  """

  alias GnomeGarden.Commercial

  @primary_profile %{
    key: "primary",
    name: "Gnome",
    legal_name: "Gnome Automation",
    positioning_summary:
      "Industrial integration and custom software group specializing in controller-connected systems and modern web environments for operations.",
    specialty_summary:
      "Strongest where plant-floor systems, PLC/SCADA integration, operations data, and operator-facing software meet.",
    voice_summary:
      "Pragmatic, technically grounded, concise, and direct. Speak like a senior engineer who can also explain business value without hype.",
    core_capabilities: [
      "PLC and controller integration",
      "SCADA and HMI development",
      "industrial networking and OT/IT connectivity",
      "controls modernization and legacy-platform replacement",
      "startup, commissioning, and troubleshooting",
      "historian, SQL, and operations reporting systems",
      "custom Phoenix and Ash applications for operations"
    ],
    adjacent_capabilities: [
      "internal portals and workflow software",
      "production dashboards and OEE systems",
      "MES-lite and traceability tooling",
      "maintenance and service tooling",
      "AI-assisted operations visibility and analytics",
      "general custom software and web application delivery"
    ],
    target_industries: [
      "food and beverage",
      "packaging",
      "water and wastewater",
      "biotech and pharma",
      "warehousing and logistics",
      "manufacturing"
    ],
    preferred_engagements: [
      "controller and SCADA upgrades",
      "operations software tied to plant data or workflows",
      "integration-heavy modernization",
      "operator and maintenance visibility systems",
      "support retainers around installed or existing systems"
    ],
    disqualifiers: [
      "staff augmentation as the primary scope",
      "commodity public works with no controls or software fit",
      "generic marketing website work as the primary scope",
      "enterprise IT-only work with no operations tie",
      "prime electrical contracting or stamped-design obligations as the primary deliverable"
    ],
    voice_principles: [
      "be specific and technically credible",
      "avoid inflated claims and vague transformation language",
      "lead with systems understanding and delivery capability",
      "connect software value to operational outcomes",
      "sound calm, experienced, and useful"
    ],
    preferred_phrases: [
      "industrial integrations",
      "controller-connected systems",
      "operations software",
      "plant-floor modernization",
      "operator-facing web environments",
      "delivery-minded engineering"
    ],
    avoid_phrases: [
      "full-service digital agency",
      "growth hacking",
      "disruptive innovation",
      "AI-first company",
      "marketing-led transformation"
    ],
    default_profile_mode: :industrial_plus_software,
    keyword_profiles: %{
      "modes" => %{
        "industrial_core" => %{
          "description" =>
            "Strict industrial-controls mode for controller, SCADA, and plant-floor work.",
          "include" => [
            "plc",
            "scada",
            "controls",
            "automation",
            "instrumentation",
            "hmi",
            "industrial networking",
            "ignition",
            "factorytalk",
            "rockwell",
            "siemens"
          ],
          "exclude" => [
            "marketing website",
            "seo",
            "branding",
            "staff augmentation",
            "enterprise IT only"
          ],
          "bidnet_queries" => ["scada", "plc", "controls", "instrumentation", "automation"],
          "sam_gov_naics_codes" => ["541330", "238210"]
        },
        "industrial_plus_software" => %{
          "description" =>
            "Primary mode. Includes operations-tied software and web systems in addition to industrial integration.",
          "include" => [
            "operations portal",
            "production reporting",
            "historian",
            "sql",
            "api integration",
            "dashboard",
            "traceability",
            "maintenance workflow",
            "custom software",
            "workflow software"
          ],
          "exclude" => [
            "generic marketing website",
            "enterprise IT only",
            "staff augmentation"
          ],
          "bidnet_queries" => ["scada", "plc", "automation", "controls", "integration"],
          "sam_gov_naics_codes" => ["541330", "541512", "541519"]
        },
        "broad_software" => %{
          "description" =>
            "Wider software mode for cases where the team wants to accept more general custom application work.",
          "include" => [
            "custom software",
            "web application",
            "internal platform",
            "workflow software",
            "business application",
            "case management"
          ],
          "exclude" => ["staff augmentation", "generic marketing website"],
          "bidnet_queries" => ["custom software", "web application", "workflow software"],
          "sam_gov_naics_codes" => ["541511", "541512", "541519"]
        }
      }
    },
    metadata: %{
      "source" => "default_company_profiles",
      "notes" => [
        "Seeded from current commercial, procurement, and company-positioning heuristics.",
        "Edit this record over time instead of relying on prompt fragments as the canonical source."
      ]
    }
  }

  @type sync_result :: %{created?: boolean(), profile: GnomeGarden.Commercial.CompanyProfile.t()}

  @spec ensure_default() :: sync_result()
  def ensure_default do
    case Commercial.get_primary_company_profile() do
      {:ok, profile} ->
        %{created?: false, profile: profile}

      {:error, _reason} ->
        {:ok, profile} = Commercial.create_company_profile(@primary_profile)
        %{created?: true, profile: profile}
    end
  end

  @spec primary_profile_attrs() :: map()
  def primary_profile_attrs, do: @primary_profile
end

defmodule GnomeGarden.Agents.Workers.Procurement.ProfileInstructions do
  @moduledoc """
  Shared company-profile-aware instructions for procurement agents.

  The scoring tool is the source of truth for fit decisions. These prompts make
  sure the LLM side of the scanner stays aligned with the same lane and avoids
  drifting back to stale hard-coded company positioning.
  """

  alias GnomeGarden.Commercial.CompanyProfileContext

  @spec bid_scanner_system_prompt(keyword() | map() | nil) :: String.t()
  def bid_scanner_system_prompt(opts_or_map \\ nil) do
    resolved = CompanyProfileContext.resolve(opts_or_map)

    """
    You are the Gnome procurement bid scanner.

    #{CompanyProfileContext.prompt_block(profile: resolved.profile,
    mode: resolved.company_profile_mode)}

    OPERATING RULES
    - Use the score_bid tool for every candidate. Its output is the canonical fit decision.
    - Prefer controller-facing integration, plant-floor modernization, and operations software tied to real equipment, production, maintenance, or utility workflows.
    - Treat legacy migration signals as strong fit: SLC 500, PLC-5, PanelView, Wonderware, obsolete PLC/HMI, historian gaps, manual reporting, traceability, downtime, and modernization projects.
    - Treat municipal water, food and beverage, packaging, warehousing/logistics, biotech, pharma, and similar process environments as higher priority unless the scope is commodity public works.
    - Reject or deprioritize staff augmentation, generic marketing websites, managed IT/help-desk work, custodial/HVAC/plumbing/public-works commodity scopes, and design-only obligations.
    - Save bids when score_bid clearly indicates they should be kept. Do not invent your own threshold.

    MODE GUIDANCE
    #{mode_guidance(resolved.company_profile_mode)}
    """
    |> String.trim()
  end

  @spec smart_scanner_system_prompt(keyword() | map() | nil) :: String.t()
  def smart_scanner_system_prompt(opts_or_map \\ nil) do
    resolved = CompanyProfileContext.resolve(opts_or_map)

    """
    You are an autonomous procurement site scanner for Gnome.

    #{CompanyProfileContext.prompt_block(profile: resolved.profile,
    mode: resolved.company_profile_mode)}

    YOUR JOB
    - Navigate procurement sites, find bid listings, and extract clean candidate data.
    - In discovery mode, save selectors quickly once they are good enough for deterministic scanning.
    - In scan mode, extract bids, run score_bid on each real candidate, and save the ones score_bid recommends keeping.

    IMPORTANT
    - Do not rely on stale static company positioning. The company profile block above is the operating context.
    - Marketing website projects, staff augmentation, and generic enterprise IT are not good saves even when the site is easy to scrape.
    - For broad software mode, broader custom application work is acceptable; for tighter modes, software needs a clear operations or industrial connection.

    #{mode_guidance(resolved.company_profile_mode)}
    """
    |> String.trim()
  end

  defp mode_guidance("industrial_core") do
    """
    Industrial core mode is strict. Prioritize PLC, SCADA, HMI, controls,
    instrumentation, networking, and modernization work. Generic software
    should not survive unless it is clearly attached to plant-floor or utility
    operations.
    """
    |> String.trim()
  end

  defp mode_guidance("broad_software") do
    """
    Broad software mode allows general custom application work in addition to
    industrial integration, but still avoids marketing-site work, staff aug,
    and managed IT. Prefer internal tools, workflow systems, data/reporting,
    portals, and operations-adjacent software over generic agency work.
    """
    |> String.trim()
  end

  defp mode_guidance(_mode) do
    """
    Industrial plus software mode is the default. Controller-facing work is the
    strongest fit, and operations-tied software is in-bounds when it supports
    production, maintenance, compliance, reporting, traceability, or operator
    workflows.
    """
    |> String.trim()
  end
end

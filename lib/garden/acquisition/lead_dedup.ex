defmodule GnomeGarden.Acquisition.LeadDedup do
  @moduledoc """
  Classifies an Exa lead candidate against the data we already have — bids,
  sources, findings, discovery records, and organizations.

  This is deliberately a *relationship classifier*, not a blunt "already seen,
  drop it" filter. The bid/source databases are also context: a company already
  in procurement can raise confidence or change routing, and a known
  organization with a fresh expansion/hiring/project signal is a keeper, not a
  duplicate.

  `classify/2` returns a `%{context:, suppress?:, recommendation:, related:}`
  map where `context` is one of:

    * `:new` — no match; a genuinely new candidate lead.
    * `:duplicate_existing_lead` — same company/domain already exists as a
      finding, discovery record, or organization (usually suppress).
    * `:known_organization_new_signal` — the company already exists, but this is
      a new signal; route it to the existing org rather than suppressing.
    * `:existing_bid_related` — matches a saved bid; do not create a lead
      automatically — attach as context/evidence if later promoted.
    * `:known_procurement_source` — url/domain is a configured procurement or
      acquisition source (suppress for commercial discovery unless it's a
      company-specific signal page).
    * `:known_bid_source` — url/domain is a bid portal / agency listing; keep
      only if the extracted entity is the prospect, otherwise public-sector
      signal context.

  A candidate is `%{url: ..., title: ..., name: optional, type: :company | :signal}`.
  Pass `:source_domains` in opts to reuse one preloaded set across a whole run.
  """

  alias GnomeGarden.{Acquisition, Commercial, Operations, Procurement}
  alias GnomeGarden.Acquisition.LeadIdentity
  alias GnomeGarden.Support.{IdentityNormalizer, WebIdentity}

  # Domains that are bid portals / agency listings even if not in our source
  # registry. `.gov`/`.us` are treated as public-sector signal context.
  @portal_patterns ~w(planetbids bidnet demandstar bonfirehub publicpurchase opengov bidexpress periscope)

  @doc "Classifies one candidate. See moduledoc for the contract."
  def classify(candidate, opts \\ []) when is_map(candidate) do
    actor = Keyword.get(opts, :actor)
    source_domains = Keyword.get(opts, :source_domains) || load_source_domains(actor)

    url = candidate[:url] || candidate["url"]
    domain = WebIdentity.website_domain(url)
    name_key = IdentityNormalizer.organization_name_key(candidate[:name] || candidate[:title])
    signal? = (candidate[:type] || candidate["type"]) == :signal

    cond do
      bid = bid_match(url, actor) ->
        result(
          :existing_bid_related,
          true,
          "Matches a saved bid — do not create a lead; attach as context/evidence if promoted.",
          [related(:bid, bid.id, bid.title)]
        )

      source = source_match(domain, url, source_domains, actor) ->
        known_source_result(source, signal?)

      portal_domain?(domain) ->
        known_bid_source_result(domain, signal?)

      org = org_match(domain, name_key, actor) ->
        org_result(org, signal?)

      record = discovery_record_match(domain, actor) ->
        discovery_result(record, signal?)

      finding = finding_match(url, actor) ->
        result(:duplicate_existing_lead, true, "Already a finding in the review queue.", [
          related(:finding, finding.id, finding.title)
        ])

      true ->
        result(:new, false, "New candidate lead.", [])
    end
  end

  @doc "Classifies many candidates, loading the known-source domain set once."
  def classify_all(candidates, opts \\ []) do
    opts = Keyword.put_new(opts, :source_domains, load_source_domains(Keyword.get(opts, :actor)))
    Enum.map(candidates, fn candidate -> {candidate, classify(candidate, opts)} end)
  end

  # --- result builders ---

  defp known_source_result(source, false),
    do:
      result(
        :known_procurement_source,
        true,
        "Already a configured procurement/acquisition source — procurement context, not a new commercial lead.",
        [related(:source, source.id, source_label(source))]
      )

  defp known_source_result(source, true),
    do:
      result(
        :known_procurement_source,
        false,
        "Domain is a known source, but this looks like a company-specific signal — attach as signal/context.",
        [related(:source, source.id, source_label(source))]
      )

  defp known_bid_source_result(domain, signal?),
    do:
      result(
        :known_bid_source,
        not signal?,
        "Bid portal / agency listing (#{domain}) — keep only if the extracted entity is the prospect; otherwise public-sector signal.",
        [related(:portal, nil, domain)]
      )

  defp org_result(org, true),
    do:
      result(
        :known_organization_new_signal,
        false,
        "Known organization (#{org.name}) with a new signal — route to the existing org; do not create a new one.",
        [related(:organization, org.id, org.name)]
      )

  defp org_result(org, false),
    do:
      result(
        :duplicate_existing_lead,
        true,
        "Company already exists as an organization (#{org.name}).",
        [related(:organization, org.id, org.name)]
      )

  defp discovery_result(record, true),
    do:
      result(
        :known_organization_new_signal,
        false,
        "Already a discovery record (#{record.name}) — attach the new signal to it.",
        [related(:discovery_record, record.id, record.name)]
      )

  defp discovery_result(record, false),
    do:
      result(:duplicate_existing_lead, true, "Already a discovery record (#{record.name}).", [
        related(:discovery_record, record.id, record.name)
      ])

  defp result(context, suppress?, recommendation, related),
    do: %{
      context: context,
      suppress?: suppress?,
      recommendation: recommendation,
      related: related
    }

  defp related(kind, id, label), do: %{kind: kind, id: id, label: label}

  # --- lookups (internal system reads; authorize? false) ---

  defp bid_match(nil, _actor), do: nil

  defp bid_match(url, actor),
    do: Procurement.get_bid_by_url(url, actor: actor, authorize?: false) |> first_ok()

  defp source_match(domain, url, source_domains, actor) do
    if domain && MapSet.member?(source_domains, domain) do
      lookup_source_record(url, actor) || %{id: nil, name: domain}
    else
      lookup_source_record(url, actor)
    end
  end

  defp lookup_source_record(nil, _actor), do: nil

  defp lookup_source_record(url, actor) do
    first_ok(Procurement.get_procurement_source_by_url(url, actor: actor, authorize?: false)) ||
      first_ok(Acquisition.get_source_by_url(url, actor: actor, authorize?: false))
  end

  defp org_match(domain, name_key, actor) do
    (domain &&
       Operations.get_organization_by_website_domain(domain, actor: actor, authorize?: false)
       |> first_ok()) ||
      (name_key &&
         Operations.list_organizations_by_name_key(name_key, actor: actor, authorize?: false)
         |> first_ok())
  end

  defp discovery_record_match(nil, _actor), do: nil

  defp discovery_record_match(domain, actor),
    do:
      Commercial.get_discovery_record_by_website_domain(domain, actor: actor, authorize?: false)
      |> first_ok()

  defp finding_match(nil, _actor), do: nil

  defp finding_match(url, actor) do
    normalized_match =
      case LeadIdentity.company_domain_key(url) do
        nil ->
          nil

        key ->
          Acquisition.get_finding_by_external_ref(key, actor: actor, authorize?: false)
          |> first_ok()
      end

    normalized_match ||
      Acquisition.get_finding_by_external_ref(url, actor: actor, authorize?: false) |> first_ok()
  end

  defp load_source_domains(actor) do
    procurement =
      case Procurement.list_procurement_sources(actor: actor, authorize?: false) do
        {:ok, sources} -> sources
        _ -> []
      end

    acquisition =
      case Acquisition.list_sources(actor: actor, authorize?: false) do
        {:ok, sources} -> sources
        _ -> []
      end

    (procurement ++ acquisition)
    |> Enum.map(&WebIdentity.website_domain(&1.url))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp portal_domain?(nil), do: false

  defp portal_domain?(domain) do
    String.ends_with?(domain, [".gov", ".us"]) or
      Enum.any?(@portal_patterns, &String.contains?(domain, &1))
  end

  defp source_label(%{name: name}) when is_binary(name), do: name
  defp source_label(_), do: "source"

  defp first_ok({:ok, %{} = record}), do: record
  defp first_ok({:ok, [record | _]}), do: record
  defp first_ok(_), do: nil
end

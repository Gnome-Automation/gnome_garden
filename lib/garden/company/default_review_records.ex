defmodule GnomeGarden.Company.DefaultReviewRecords do
  @moduledoc """
  Idempotent defaults for company compliance and source review records.

  These records summarize the current reviewed state from `gnome-company`.
  They are editable database records, not a bulk import pipeline.
  """

  alias GnomeGarden.Company
  alias GnomeGarden.Company.DefaultRegistration

  @source_commit "081cf8a6543e"

  @compliance_obligations [
    %{
      key: "boi-report",
      title: "BOI report",
      category: :federal,
      status: :complete,
      summary:
        "BOI status was captured from the company source repo; confirmation number remains missing.",
      completed_on: ~D[2026-03-30],
      source_path: "02-compliance/federal/boi-report.md",
      source_commit: @source_commit,
      metadata: %{"missing" => ["confirmation_number"]}
    },
    %{
      key: "registered-agent-renewal",
      title: "Registered agent renewal",
      category: :registered_agent,
      status: :active,
      summary: "Northwest Registered Agent renewal is tracked from the reviewed operations note.",
      due_on: ~D[2027-02-01],
      source_path: "03-operations/registered-agent.md",
      source_commit: @source_commit,
      metadata: %{"service" => "Northwest Registered Agent", "annual_cost" => "$125/year"}
    },
    %{
      key: "california-statement-of-information",
      title: "California statement of information",
      category: :state,
      status: :needs_review,
      summary:
        "Formation milestones mention state filings; confirm next SOI due date before relying on it.",
      source_path: "03-operations/milestones.md",
      source_commit: @source_commit,
      metadata: %{"needs" => ["next_due_date"]}
    },
    %{
      key: "california-franchise-tax",
      title: "California franchise tax",
      category: :tax,
      status: :needs_review,
      summary:
        "Annual checklist mentions franchise tax obligations; verify dates and payment status.",
      source_path: "05-checklists/annual-checklist.md",
      source_commit: @source_commit,
      metadata: %{"needs" => ["due_date", "payment_status"]}
    },
    %{
      key: "business-license-check",
      title: "Business license check",
      category: :license,
      status: :needs_review,
      summary:
        "Older license notes appear stale; verify whether current operations require a city license.",
      source_path: "02-compliance/california/business-license.md",
      source_commit: @source_commit,
      metadata: %{"source_status" => "stale"}
    }
  ]

  @source_review_items [
    %{
      key: "signed-w9",
      title: "Signed W-9",
      status: :applied,
      source_path: "06-templates/w9-gnome-automation-signed.pdf",
      source_commit: @source_commit,
      evidence_date: ~D[2026-06-04],
      target_resource: "Company.Document",
      summary: "Signed W-9 PDF is current enough to reuse for vendor onboarding.",
      recommendation: "Keep as active reusable company document.",
      metadata: %{"sha256" => "ebe7b70c98af026bae8ff30c4aedc837bfca6e25e1501e66ccf4a60e02cbf276"}
    },
    %{
      key: "registered-agent",
      title: "Registered agent",
      status: :applied,
      source_path: "03-operations/registered-agent.md",
      source_commit: @source_commit,
      evidence_date: ~D[2026-03-30],
      target_resource: "Company.ComplianceObligation",
      summary:
        "Northwest Registered Agent data was applied to company compliance/profile metadata.",
      recommendation: "Promote renewal date into first-class compliance record.",
      metadata: %{}
    },
    %{
      key: "company-profile-boilerplate",
      title: "Company profile boilerplate",
      status: :needs_review,
      source_path: "03-operations/company-profile.md",
      source_commit: @source_commit,
      evidence_date: ~D[2026-04-05],
      target_resource: "Company.Profile",
      summary: "Contains RFI/RFP positioning, rates, capabilities, and industry language.",
      recommendation: "Diff against current Garden positioning before applying.",
      metadata: %{}
    },
    %{
      key: "relayfi-banking-conflict",
      title: "Relayfi banking conflict",
      status: :conflict,
      source_path: "03-operations/banking.md",
      source_commit: @source_commit,
      evidence_date: ~D[2026-03-26],
      target_resource: "Company.PaymentDestination",
      summary:
        "Older files mention Relayfi, while current Garden account details are Mercury/Column.",
      recommendation:
        "Treat Relayfi as historical unless a current bank statement proves otherwise.",
      metadata: %{"current_provider" => "Mercury/Column"}
    },
    %{
      key: "cp-575-missing",
      title: "CP 575 document",
      status: :missing,
      source_path: "05-checklists/annual-checklist.md",
      source_commit: @source_commit,
      evidence_date: ~D[2026-03-30],
      target_resource: "Company.Document",
      summary:
        "Checklist says CP 575 was located, but no CP 575 file was found in the visible repo tree.",
      recommendation: "Locate the IRS CP 575 letter and attach it as a company document.",
      metadata: %{}
    }
  ]

  @spec ensure_defaults(keyword()) :: %{
          profile: GnomeGarden.Company.Profile.t(),
          compliance_obligations: [GnomeGarden.Company.ComplianceObligation.t()],
          source_review_items: [GnomeGarden.Company.SourceReviewItem.t()]
        }
  def ensure_defaults(opts \\ []) do
    profile = Keyword.get(opts, :profile) || DefaultRegistration.ensure_default().profile

    %{
      profile: profile,
      compliance_obligations: Enum.map(@compliance_obligations, &ensure_compliance(profile, &1)),
      source_review_items: Enum.map(@source_review_items, &ensure_source_review_item(profile, &1))
    }
  end

  defp ensure_compliance(profile, attrs) do
    attrs = Map.put(attrs, :company_profile_id, profile.id)

    case Company.get_company_compliance_obligation_by_key(profile.id, attrs.key) do
      {:ok, obligation} ->
        obligation

      {:error, _reason} ->
        {:ok, obligation} = Company.create_company_compliance_obligation(attrs)
        obligation
    end
  end

  defp ensure_source_review_item(profile, attrs) do
    attrs = Map.put(attrs, :company_profile_id, profile.id)

    case Company.get_company_source_review_item_by_key(profile.id, attrs.key) do
      {:ok, item} ->
        item

      {:error, _reason} ->
        {:ok, item} = Company.create_company_source_review_item(attrs)
        item
    end
  end
end

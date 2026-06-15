# Company Information Source Inventory

Last reviewed: 2026-06-13

Source repository: `/home/pc/gnome/gnome-company`

Reviewed commit: `081cf8a` (`2026-06-04T08:23:28-07:00`) on `main`

Latest dev population: source files were reviewed and applied through Tidewave
runtime Ash calls on 2026-06-13.

## Purpose

This inventory organizes the older `gnome-company` repository into reviewed
source evidence for company records now owned by GnomeGarden. Treat
`gnome-company` as a source candidate, not as automatically authoritative. Some
files are current, some are stale, and some conflict with newer records entered
directly in Garden.

Do not copy raw sensitive values from the source repo into markdown docs. Tax
IDs and account numbers belong in encrypted Ash resources and should be shown
only as masked last-four values unless an explicit trusted reveal flow is used.

## Current Garden Targets

| Category | Garden target | Notes |
| --- | --- | --- |
| Legal identity and registered address | `Company.Profile.metadata["vendor_registration"]` | Public registration facts. |
| Contacts and vendor emails | `Company.Profile.metadata["vendor_registration"]["company"]` | Public-ish operational contact fields. |
| Tax IDs | `Company.TaxIdentifier` | Encrypted value plus masked last-four. |
| Accounts and payment instructions | `Company.PaymentDestination` | UI label is `Company > Facts > Accounts`; account number encrypted. |
| Reusable company docs | `Company.Document` | W-9, CP 575, insurance certificates, signed confirmations. |
| Customer-specific requirements | `Commercial.CustomerVendorOnboarding` and requirements | Per-customer instructions such as "always include X/Y/Z". |
| Compliance reminders | Future compliance/checklist resource | Do not bury renewal obligations in profile metadata long term. |
| Pricing/capability boilerplate | `Company.Profile` profile/capability fields | Needs review before replacing current Garden positioning. |

## High-Confidence Source Items

These items look suitable to read and apply through Tidewave/runtime Ash calls
after a quick operator review.

| Source | Evidence date | What it contains | Garden target | Status |
| --- | ---: | --- | --- | --- |
| `06-templates/w9.md` | 2026-06-04 | W-9 completion guide, legal name, tax classification, registered address, masked EIN reference | `Company.TaxIdentifier`, `Company.Document`, legal facts | Applied to dev; raw EIN belongs encrypted. |
| `06-templates/w9-gnome-automation-signed.pdf` | 2026-06-04 | Signed W-9 PDF, SHA256 `ebe7b70c98af026bae8ff30c4aedc837bfca6e25e1501e66ccf4a60e02cbf276` | `Company.Document(kind: :w9)` | Applied to dev as `w9_signed_2026_06_04`. |
| `03-operations/registered-agent.md` | 2026-03-30 | Northwest Registered Agent, renewal date, registered agent address | `Company.Profile.metadata["registered_agent"]` | Applied to dev. |
| `03-operations/milestones.md` | 2026-04-28 | Formation dates, SOI, BOI, EIN obtained, Mercury account approval | `Company.Profile.metadata["formation"]` | Applied to dev with Relayfi marked historical/superseded. |
| `02-compliance/federal/boi-report.md` | 2026-03-30 | BOI filing status and filing date; confirmation number still TBD | `Company.Profile.metadata["compliance"]["boi"]` | Applied to dev; confirmation remains missing. |
| `05-checklists/annual-checklist.md` | 2026-03-30 | Recurring tax, SOI, BOI, franchise-tax, license reminders | `Company.Profile.metadata["compliance"]["annual"]` | Applied to dev as summary metadata. |

## Needs Review Before Applying

These files contain useful information but should not directly overwrite Garden.

| Source | Issue | Recommended handling |
| --- | --- | --- |
| `03-operations/company-profile.md` | Last updated 2026-04-05. Strong RFI/RFP boilerplate, rates, capabilities, and industries, but may not match current Garden positioning. | Diff against current `CompanyProfile` fields; apply only reviewed capabilities/boilerplate. |
| `00-formation/plan.md` | Says banking is Relayfi, while later milestones mention Mercury and Garden currently stores Mercury/Column details. | Use for formation facts, not current account facts. Mark Relayfi as historical or superseded. |
| `03-operations/banking.md` | Current account section says Relayfi opened 2026-03-26. This conflicts with current Mercury/Column account data. | Do not apply to Accounts without review. Use as historical banking note only. |
| `01-finance/cost-tracker.md` | Mentions initial deposit to Mercury on 2026-04-23 and expenses. | Useful for finance ledger/history, not Company Facts. |
| `01-finance/business-rates.md` | Useful pricing strategy but not vendor registration data. | Consider a future Commercial rate-card resource or reviewed profile metadata. |
| `02-compliance/california/business-license.md` | Legal requirements and status are stale/pending. | Use as checklist seed; verify current city requirements before operational use. |
| `06-templates/operating-agreement.md` | Legal agreement text, founder/member details, transaction authority, insurance obligations. | Keep as company document/legal record. Avoid extracting personal details into broad UI unless needed. |

## Conflicts Found

| Topic | `gnome-company` says | Garden/current direction | Resolution |
| --- | --- | --- | --- |
| Bank/account provider | README, plan, banking docs say Relayfi. Milestones and cost tracker mention Mercury later. | Garden has Mercury/Column payment destination. | Treat Relayfi as historical/superseded until confirmed. Do not replace Mercury. |
| Contact email | `company-profile.md` lists general email as `info@gnomeautomation.com`. Recent vendor packet usage used `sales@gnomeautomation.com`. | Garden currently uses sales/purchasing/finance as `sales@gnomeautomation.com`. | Add both as contact channels if desired; decide default per form context. |
| Business location language | Older profile says Southern California / Irvine + Anaheim. Vendor forms use registered agent address in Sacramento. | Company Facts currently stores registered address as Sacramento. | Keep registered address separate from operating/service geography. |
| W-9 task status | Checklist still says complete signed W-9 unchecked, but signed PDF exists. | Signed W-9 exists in source repo. | Mark source checklist stale; apply signed W-9 document. |
| CP 575 | Checklist says located and saved, but no CP 575 file was found in the visible repo tree. | Garden has tax ID value encrypted but no CP 575 company document. | Add CP 575 as missing document until located. |

## Proposed Company Area Layout

The Company area now uses focused tabs instead of one large catch-all.

| Tab | Contents |
| --- | --- |
| `Profile` | Legal entity, registered address, contacts, terms, tax IDs, accounts. Implemented at `/company/facts` and `/company/profile`. |
| `Documents` | W-9, CP 575, operating agreement, insurance certificates, supplier-code confirmations. Implemented at `/company/documents` on `Company.Document`. |
| `Compliance` | BOI, SOI, franchise tax, business licenses, registered agent renewal. Implemented at `/company/compliance` on `Company.ComplianceObligation`. |
| `Sources` | Reviewed source files, freshness, conflicts, review decisions. Implemented at `/company/sources` on `Company.SourceReviewItem`. |
| Future `Positioning` | RFI/RFP boilerplate, capabilities, industries, rates, proof points. Still needs review before replacing current Garden positioning. |

Customer-specific forms and requirements, such as PolyPeptide's prospective
vendor packet, belong in `Commercial.CustomerVendorOnboarding` and should be
surfaced in the Commercial area as customer onboarding or pursuit context. Do
not put those packet rules on Company Facts unless the value is a reusable Gnome
fact that should answer many customers' forms.

## Immediate Next Source Work

1. Locate and attach CP 575 as a `Company.Document`.
2. Add source provenance fields to any remaining populated records:
   - source repo
   - source path
   - source commit
   - source file SHA256 for binary documents
   - reviewed status
3. Review older profile/rates/capability boilerplate before promoting it into
   `Company.Profile` or a future Company positioning page.

## Do Not Apply Automatically

- Relayfi current-account values into current Accounts.
- Founder personal/home data into broad operator UI.
- Raw EIN or account numbers into markdown, metadata, or non-encrypted fields.
- Deployment and server docs into Company Facts; those belong in ops/runbook
  documentation, not company registration records.

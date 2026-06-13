---
title: Vendor Onboarding Playbook
tags:
  - vendor-onboarding
  - finance
created: 2026-06-11
status: active
---

# Vendor Onboarding Playbook

Reusable answer key for customer vendor registration / supplier setup packets.

Customer-specific records:

- [[customers/polypeptide]]

Do not commit raw bank account numbers, routing numbers, FEIN values, or signed
vendor packet files. Import those values from a secure JSON file with
`mix gnome_garden.import_vendor_onboarding /secure/path/vendor-onboarding.json`
or the release import helper.

## Tax & entity identifiers — answer key

Copy straight onto vendor forms.

- **Legal entity name:** Gnome Automation LLC
  - Must match IRS records and Mercury account exactly.
- **FEIN (US):** secure company record only
  - The ONE value not captured in this exercise.
  - Pull from the IRS CP 575 letter or Mercury onboarding docs and fill in permanently.
  - This is the field US customers actually need for AP setup and 1099s.
- **Sales Tax ID (US):** N/A — Gnome is not registered with CDTFA; engineering/professional services are not taxable in California.
  - NOTE: if we ever sell tangible goods (panels, hardware, skids), register with CDTFA first and update this page.
- **VAT (EU):** N/A — European value-added tax registration number.
- **GST (India):** N/A — Indian goods and services tax registration number.
- **PAN (India):** N/A — Indian permanent account number for tax identity.
- **IFSC (India):** N/A — Indian bank branch routing code.
- **Registered agent / legal address:** Northwest Registered Agent, 2108 N Street, Ste N, Sacramento, CA 95816
  - This is the beneficiary address on banking forms.

## Banking (Mercury) — answer key

- Bank of record is **Column N.A.**
  - Mercury is the fintech layer; never write "Mercury" as bank name.
- **Bank name:** Column N.A.
- **Bank address:** secure company record only
- **Account number (CHECKING):** secure company record only
- **Beneficiary name:** Gnome Automation LLC
- **Beneficiary address:** 2108 N Street, Ste N, Sacramento, CA 95816 US
- **ABA routing - ACH:** secure company record only
- **ABA routing - domestic wire:** secure company record only
- **SWIFT/BIC:** secure company record only
- **Intermediary bank:** secure company record only, if required
- **IBAN:** N/A — US accounts have no IBAN; SWIFT + account number serves that role.
- **Bank Giro / IFSC:** N/A — European / Indian concepts.
- **Authoritative source:** Mercury → Accounts → checking → wire details PDF (MT103-labeled).
  - Re-download if Mercury ever changes partner banks and update this page.

## Standard terms & signing

### Delivery terms (Incoterms)

- **DDP:** seller pays everything including duties to buyer's door.
- **DAP:** buyer handles import duties/customs.
- Domestic services/deliverables: accept DDP; no customs anyway.
- International shipping: prefer DAP.

### Payment terms

- Customers often default to Net 60+.
- Always counter with Net 30 or early-pay discount, e.g. 2/10 Net 60.
- Cash flow matters for a two-person shop.

### Signature block

- Sign as **Managing Member**.
- Matches operating agreement and conveys binding authority.

## Standard invoice footer

Paste-ready:

Use the secure banking profile from company data. The public footer template is:

> Bank: Column N.A. | SWIFT: [secure company record] | Routing (ABA): [secure company record] | Account: [secure company record] | IBAN: N/A (US)

## Last verified

2026-06-11 — values confirmed from Mercury's wire details PDF.

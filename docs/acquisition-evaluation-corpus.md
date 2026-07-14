# Acquisition Evaluation Corpus

Garden keeps the first acquisition workflow corpus under
`test/fixtures/acquisition_eval/v1/`. It is a frozen, redacted reconstruction of
recurring operator outcomes rather than production operational data.

The corpus provides two stable evaluation surfaces:

- one Exa search episode with accepted, rejected, suppressed, duplicate, and
  promoted outcomes plus exact expected candidate type, dedupe context, route,
  suppression state, and rank;
- representative source failures resolved through the shared
  `provider-contract/v1` taxonomy.

The same version also freezes the OpenGov embedded project-list shape that was
observed during the first bounded production canary. This keeps provider drift
reproducible without treating a live response as operational data.

`GnomeGarden.Acquisition.EvaluationCorpusTest` executes the frozen episode
through the production `LeadPreview` normalization, dedupe, routing, and ranking
path. It uses `Req.Test`, the SQL sandbox, synthetic identifiers, and frozen
fixtures, so it requires no API key, network request, browser process, or live
provider spend.

## Versioning

Do not rewrite expected outcomes in place when a deliberate policy change makes
the current corpus obsolete. Add a new version, document the policy decision,
and retain the prior version so ranking changes remain comparable. Provider
transport fixtures stay in `test/fixtures/provider_contract/`; the acquisition
manifest references that contract version instead of duplicating failure
payloads.

This corpus is the gate for experimental query-planning or ranking runtimes. A
runtime may only advance when it can emit candidate IDs and routing/ranking
results that can be compared against these expected outcomes without gaining
write authority.

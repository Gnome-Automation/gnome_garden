# Provider Contract Fixtures

Provider integrations share a versioned offline fixture contract under
`test/fixtures/provider_contract/v1/`. The manifest records provenance and resolves the same
scenario vocabulary for every provider operation:

- success and empty
- throttled and authentication failure
- schema drift and malformed payloads
- WAF challenge and timeout
- partial payload

`GnomeGarden.ProviderContract` loads raw JSON or HTML and exposes adapters for Req, injectable
HTTP getters, Jido web fetch/session APIs, and the Playwright command runner. Tests feed those raw
fixtures through production parsers; they do not bypass parsing with already-normalized test maps.

The v1 manifest covers Exa Search/Contents, SAM.gov, OpenGov, BidNet, Jido web fetch/session, and
provider-specific Playwright. OpenGov fixtures define its contract before the provider adapter is
implemented.

Run the contract suite without a Phoenix server, secrets, or live network access:

```bash
env -u PHX_SERVER -u PORT MIX_ENV=test mix test \
  test/garden/providers/provider_contract_test.exs \
  test/garden/search/exa_test.exs \
  test/garden/agents/tools/procurement/query_sam_gov_test.exs \
  test/garden/procurement/playwright_runner_test.exs
```

When a provider changes shape, add a new versioned fixture and provenance note before changing the
parser. Do not silently rewrite an existing fixture version after downstream adapters depend on it.

import Config
config :gnome_garden, Oban, testing: :manual

config :gnome_garden,
  serve_local_storage?: true,
  token_signing_secret: "0yKs9QpG/aUKOWcHig5mxRkK+spiI4IB"

config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

db_host = System.get_env("GNOME_GARDEN_DB_HOST", "localhost")
db_port = String.to_integer(System.get_env("GNOME_GARDEN_DB_PORT", "5433"))

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gnome_garden, GnomeGarden.Repo,
  username: "postgres",
  password: "postgres",
  hostname: db_host,
  port: db_port,
  database: "gnome_garden_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gnome_garden, GnomeGardenWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qV1/9y2Qk3h3UT33CEF6qDbQpWjv2zlop5zWbCs/d5NyDmSVK2xuRG/cX+q3jSRT",
  server: false

# In test we don't send emails
config :gnome_garden, GnomeGarden.Mailer, adapter: Swoosh.Adapters.Test

# Exa: a fixed test key + route all requests through a Req.Test stub so tests
# never hit the network.
config :gnome_garden, :exa,
  api_key: "test-exa-key",
  req_options: [plug: {Req.Test, GnomeGarden.Search.Exa}]

# Never make a live LLM call from contact extraction in tests; inject :llm_fun
# explicitly when a test needs the named-people path.
config :gnome_garden, :contact_extractor, llm_enabled: false

config :gnome_garden, GnomeGarden.Acquisition.Document,
  storage: [service: {AshStorage.Service.Test, []}]

config :gnome_garden, GnomeGarden.Company.Document,
  storage: [service: {AshStorage.Service.Test, []}]

config :gnome_garden, GnomeGarden.Commercial.CustomerVendorRequirementArtifact,
  storage: [service: {AshStorage.Service.Test, []}]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

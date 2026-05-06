# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cinder, default_theme: GnomeGardenWeb.CinderTheme
config :ex_cldr, default_backend: GnomeGarden.Cldr
config :ash_oban, pro?: false
config :tzdata, :autoupdate, :disabled

config :gnome_garden, :pi_service_token, System.get_env("PI_SERVICE_TOKEN", "dev-pi-token")
config :gnome_garden, serve_local_storage?: false, max_agent_run_timeout_ms: 600_000

# Register Z.AI (Zhipu AI) models in LLMDB catalog
config :llm_db,
  custom: %{
    zai: [
      name: "Z.AI (Zhipu)",
      models: %{
        "glm-5" => %{
          name: "GLM-5",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: true, strict: false, parallel: true},
            streaming: %{text: true, tool_calls: true}
          },
          limits: %{context_window: 200_000, max_output_tokens: 16384}
        },
        "glm-5-turbo" => %{
          name: "GLM-5 Turbo",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: true, strict: false, parallel: true},
            streaming: %{text: true, tool_calls: true}
          },
          limits: %{context_window: 200_000, max_output_tokens: 16384}
        },
        "glm-4.7" => %{
          name: "GLM-4.7",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: true, strict: false, parallel: true},
            streaming: %{text: true, tool_calls: true}
          },
          limits: %{context_window: 200_000, max_output_tokens: 8192}
        },
        "glm-4.7-flash" => %{
          name: "GLM-4.7 Flash",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: false, strict: false, parallel: false},
            streaming: %{text: true, tool_calls: false}
          },
          limits: %{context_window: 128_000, max_output_tokens: 8192}
        },
        "glm-4.6" => %{
          name: "GLM-4.6",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: true, strict: false, parallel: true},
            streaming: %{text: true, tool_calls: true}
          },
          limits: %{context_window: 200_000, max_output_tokens: 8192}
        },
        "glm-4.5v" => %{
          name: "GLM-4.5 Vision",
          capabilities: %{
            chat: true,
            vision: true,
            tools: %{enabled: true, streaming: false, strict: false, parallel: false},
            streaming: %{text: true, tool_calls: false}
          },
          limits: %{context_window: 128_000, max_output_tokens: 4096}
        },
        "glm-4.5-air" => %{
          name: "GLM-4.5 Air",
          capabilities: %{
            chat: true,
            tools: %{enabled: true, streaming: false, strict: false, parallel: false},
            streaming: %{text: true, tool_calls: false}
          },
          limits: %{context_window: 128_000, max_output_tokens: 4096}
        }
      }
    ]
  }

# Register Z.AI as a custom ReqLLM provider
config :req_llm,
  custom_providers: [GnomeGarden.Providers.Zai]

# Jido AI model aliases - using Z.AI GLM models via Coding Plan
# Using zai_coding_plan provider for coding plan API key
config :jido_ai,
  model_aliases: %{
    fast: "zai_coding_plan:glm-4.5-air",
    capable: "zai_coding_plan:glm-4.7",
    powerful: "zai_coding_plan:glm-5",
    coding: "zai_coding_plan:glm-4.7"
  }

config :jido_ai,
  llm_defaults: %{
    text: %{model: :fast, temperature: 0.2, max_tokens: 8192, timeout: 120_000},
    stream: %{model: :fast, temperature: 0.2, max_tokens: 8192, timeout: 120_000}
  }

config :gnome_garden, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, procurement_scanning: 2, mercury: 10, finance: 5],
  repo: GnomeGarden.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", GnomeGarden.Agents.DeploymentSchedulerWorker},
       {"13 * * * *", GnomeGarden.Commercial.DiscoverySchedulerWorker},
       {"0 6 * * *", GnomeGarden.Mercury.InvoiceSchedulerWorker},
       {"*/5 * * * *", GnomeGarden.Acquisition.Workers.RetryFailedImports},
       {"0 8 * * *", GnomeGarden.Finance.PaymentReminderWorker}
     ],
     timezone: "Etc/UTC"}
  ]

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec, AshMoney.Types.Money],
  custom_types: [money: AshMoney.Types.Money]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :jido,
        :state_machine,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :gnome_garden,
  ecto_repos: [GnomeGarden.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    GnomeGarden.Mercury,
    GnomeGarden.Accounts,
    GnomeGarden.Acquisition,
    GnomeGarden.Agents,
    GnomeGarden.Commercial,
    GnomeGarden.Execution,
    GnomeGarden.Finance,
    GnomeGarden.Operations,
    GnomeGarden.Procurement
  ]

config :gnome_garden, :payment_matching, underpayment_tolerance: "1.00"

# Configure the endpoint
config :gnome_garden, GnomeGardenWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GnomeGardenWeb.ErrorHTML, json: GnomeGardenWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GnomeGarden.PubSub,
  live_view: [signing_salt: "rmT3yBmS"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :gnome_garden, GnomeGarden.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
external_esbuild_path = System.get_env("MIX_ESBUILD_PATH")

esbuild_external_config =
  if external_esbuild_path do
    [path: external_esbuild_path, version_check: false]
  else
    []
  end

esbuild_config = [
  version: "0.25.4",
  gnome_garden: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
]

config :esbuild, esbuild_config ++ esbuild_external_config

# Configure tailwind (the version is required)
external_tailwind_path = System.get_env("MIX_TAILWIND_PATH")

tailwind_external_config =
  if external_tailwind_path do
    [path: external_tailwind_path, version_check: false]
  else
    []
  end

tailwind_config = [
  version: "4.1.12",
  gnome_garden: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
]

config :tailwind, tailwind_config ++ tailwind_external_config

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import Config

# Load .env file if it exists (for local development)
if File.exists?(".env") do
  Dotenvy.source!(".env")
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gnome_garden start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") in ~w(true 1) do
  config :gnome_garden, GnomeGardenWeb.Endpoint, server: true
end

config :gnome_garden, GnomeGardenWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Mercury Bank API configuration
if mercury_api_key = System.get_env("MERCURY_API_KEY") do
  config :gnome_garden,
    mercury_api_key: mercury_api_key,
    mercury_sandbox: System.get_env("MERCURY_SANDBOX", "true") == "true"
end

config :gnome_garden, :mercury_payment_info,
  account_number: System.get_env("MERCURY_ACCOUNT_NUMBER", ""),
  routing_number: System.get_env("MERCURY_ROUTING_NUMBER", "")

if mercury_webhook_secret = System.get_env("MERCURY_WEBHOOK_SECRET") do
  config :gnome_garden,
    mercury_webhook_secret: mercury_webhook_secret
end

if config_env() == :prod do
  unless System.get_env("MERCURY_WEBHOOK_SECRET") do
    raise """
    environment variable MERCURY_WEBHOOK_SECRET is missing.
    Set it in your production environment before starting the server.
    """
  end
end

# Z.AI (Zhipu AI) API configuration for GLM models
if zai_api_key = System.get_env("ZAI_API_KEY") do
  config :gnome_garden,
    zai_api_key: zai_api_key
end

# Brave Search API for jido_browser
if brave_api_key = System.get_env("BRAVE_API_KEY") do
  config :jido_browser,
    brave_api_key: brave_api_key
end

if config_env() == :prod and is_nil(System.get_env("GARAGE_ACCESS_KEY")) and
     System.get_env("ALLOW_LOCAL_STORAGE_IN_PROD") != "true" do
  raise """
  environment variable GARAGE_ACCESS_KEY is missing.
  Configure S3-compatible acquisition document storage before starting production.
  Set ALLOW_LOCAL_STORAGE_IN_PROD=true only for a deliberate temporary emergency.
  """
end

if garage_access_key = System.get_env("GARAGE_ACCESS_KEY") do
  garage_secret_key =
    System.get_env("GARAGE_SECRET_KEY") ||
      raise "Missing environment variable `GARAGE_SECRET_KEY` for acquisition document storage."

  config :gnome_garden, GnomeGarden.Acquisition.Document,
    storage: [
      service:
        {AshStorage.Service.S3,
         [
           bucket: System.get_env("GARAGE_BUCKET", "gnome-garden-acquisition"),
           region: System.get_env("GARAGE_REGION", "garage"),
           endpoint_url: System.get_env("GARAGE_ENDPOINT_URL", "http://127.0.0.1:3900"),
           access_key_id: garage_access_key,
           secret_access_key: garage_secret_key,
           prefix: System.get_env("GARAGE_PREFIX", "acquisition/")
         ]}
    ]
end

if config_env() == :prod do
  config :gnome_garden,
         :pi_service_token,
         System.get_env("PI_SERVICE_TOKEN") ||
           raise("PI_SERVICE_TOKEN must be set in production")

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gnome_garden, GnomeGarden.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      Set it to the public production host, for example app.example.com.
      """

  config :gnome_garden, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :gnome_garden, GnomeGardenWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :gnome_garden,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gnome_garden, GnomeGardenWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :gnome_garden, GnomeGardenWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :gnome_garden, GnomeGarden.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

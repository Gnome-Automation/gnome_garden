defmodule GnomeHub.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GnomeHubWeb.Telemetry,
      GnomeHub.Repo,
      {DNSCluster, query: Application.get_env(:gnome_hub, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:gnome_hub, :ash_domains),
         Application.fetch_env!(:gnome_hub, Oban)
       )},
      {Phoenix.PubSub, name: GnomeHub.PubSub},

      # Jido agent infrastructure
      {Registry, keys: :unique, name: GnomeHub.Agents.SessionRegistry},
      {DynamicSupervisor, name: GnomeHub.Agents.AgentSupervisor, strategy: :one_for_one},
      GnomeHub.Agents.AgentTracker,
      GnomeHub.Jido,

      # Start to serve requests, typically the last entry
      GnomeHubWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :gnome_hub]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GnomeHub.Supervisor]

    # Attach streaming telemetry handler
    GnomeHub.Agents.StreamingHandler.attach()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GnomeHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

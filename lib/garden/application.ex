defmodule GnomeGarden.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GnomeGardenWeb.Telemetry,
      GnomeGarden.Repo,
      {DNSCluster, query: Application.get_env(:gnome_garden, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:gnome_garden, :ash_domains),
         Application.fetch_env!(:gnome_garden, Oban)
       )},
      {Phoenix.PubSub, name: GnomeGarden.PubSub},

      # Jido agent infrastructure
      {Registry, keys: :unique, name: GnomeGarden.Agents.SessionRegistry},
      {DynamicSupervisor, name: GnomeGarden.Agents.AgentSupervisor, strategy: :one_for_one},
      GnomeGarden.Agents.AgentTracker,
      {Jido.Signal.Bus, name: GnomeGarden.SignalBus},
      GnomeGarden.Jido,

      # Lead pipeline — reacts to bid/lead signals
      GnomeGarden.Agents.Pipeline.PipelineSupervisor,

      # Start to serve requests, typically the last entry
      GnomeGardenWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :gnome_garden]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GnomeGarden.Supervisor]

    # Attach streaming telemetry handler
    GnomeGarden.Agents.StreamingHandler.attach()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GnomeGardenWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

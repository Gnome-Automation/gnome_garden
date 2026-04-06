defmodule GnomeGardenWeb.Router do
  use GnomeGardenWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GnomeGardenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", GnomeGardenWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      layout: {GnomeGardenWeb.Layouts, :app},
      on_mount: [{GnomeGardenWeb.LiveUserAuth, :live_user_optional}] do
      live "/agent", AgentLive

      # CRM - Review Queue
      live "/crm/review", CRM.ReviewLive, :index

      # CRM - Companies
      live "/crm/companies", CRM.CompanyLive.Index, :index
      live "/crm/companies/new", CRM.CompanyLive.Form, :new
      live "/crm/companies/:id", CRM.CompanyLive.Show, :show
      live "/crm/companies/:id/edit", CRM.CompanyLive.Form, :edit

      # CRM - Contacts
      live "/crm/contacts", CRM.ContactLive.Index, :index
      live "/crm/contacts/new", CRM.ContactLive.Form, :new
      live "/crm/contacts/:id", CRM.ContactLive.Show, :show
      live "/crm/contacts/:id/edit", CRM.ContactLive.Form, :edit

      # CRM - Leads
      live "/crm/leads", CRM.LeadLive.Index, :index
      live "/crm/leads/new", CRM.LeadLive.Form, :new
      live "/crm/leads/:id", CRM.LeadLive.Show, :show
      live "/crm/leads/:id/edit", CRM.LeadLive.Form, :edit

      # CRM - Opportunities
      live "/crm/opportunities", CRM.OpportunityLive.Index, :index
      live "/crm/opportunities/new", CRM.OpportunityLive.Form, :new
      live "/crm/opportunities/:id", CRM.OpportunityLive.Show, :show
      live "/crm/opportunities/:id/edit", CRM.OpportunityLive.Form, :edit

      # CRM - Tasks
      live "/crm/tasks", CRM.TaskLive.Index, :index
      live "/crm/tasks/new", CRM.TaskLive.Form, :new
      live "/crm/tasks/:id", CRM.TaskLive.Show, :show
      live "/crm/tasks/:id/edit", CRM.TaskLive.Form, :edit

      # Agents - Sales Discovery
      live "/agents/sales/bids", Agents.Sales.BidLive.Index, :index
      live "/agents/sales/bids/:id", Agents.Sales.BidLive.Show, :show
      live "/agents/sales/prospects", Agents.Sales.ProspectsLive
      live "/agents/sales/lead-sources", Agents.Sales.LeadSourcesLive
    end
  end

  scope "/", GnomeGardenWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, GnomeGarden.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{GnomeGardenWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    GnomeGardenWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  GnomeGardenWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route GnomeGarden.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        GnomeGardenWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(GnomeGarden.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        GnomeGardenWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", GnomeGardenWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:gnome_garden, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GnomeGardenWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:gnome_garden, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end

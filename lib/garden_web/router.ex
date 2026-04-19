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
      live "/console/agents", Console.AgentsLive
      live "/console/agents/deployments/new", Console.AgentDeploymentFormLive
      live "/console/agents/deployments/:id/edit", Console.AgentDeploymentFormLive
      live "/console/agents/runs/:id", Console.AgentRunLive

      # Operations - Organizations
      live "/operations/organizations", Operations.OrganizationLive.Index, :index
      live "/operations/organizations/new", Operations.OrganizationLive.Form, :new
      live "/operations/organizations/:id", Operations.OrganizationLive.Show, :show
      live "/operations/organizations/:id/edit", Operations.OrganizationLive.Form, :edit

      # Operations - People
      live "/operations/people", Operations.PersonLive.Index, :index
      live "/operations/people/new", Operations.PersonLive.Form, :new
      live "/operations/people/:id", Operations.PersonLive.Show, :show
      live "/operations/people/:id/edit", Operations.PersonLive.Form, :edit

      # Operations - Sites
      live "/operations/sites", Operations.SiteLive.Index, :index
      live "/operations/sites/new", Operations.SiteLive.Form, :new
      live "/operations/sites/:id", Operations.SiteLive.Show, :show
      live "/operations/sites/:id/edit", Operations.SiteLive.Form, :edit

      # Operations - Managed Systems
      live "/operations/managed-systems", Operations.ManagedSystemLive.Index, :index
      live "/operations/managed-systems/new", Operations.ManagedSystemLive.Form, :new
      live "/operations/managed-systems/:id", Operations.ManagedSystemLive.Show, :show
      live "/operations/managed-systems/:id/edit", Operations.ManagedSystemLive.Form, :edit

      # Operations - Affiliations
      live "/operations/affiliations", Operations.OrganizationAffiliationLive.Index, :index
      live "/operations/affiliations/new", Operations.OrganizationAffiliationLive.Form, :new
      live "/operations/affiliations/:id", Operations.OrganizationAffiliationLive.Show, :show
      live "/operations/affiliations/:id/edit", Operations.OrganizationAffiliationLive.Form, :edit

      # Operations - Assets
      live "/operations/assets", Operations.AssetLive.Index, :index
      live "/operations/assets/new", Operations.AssetLive.Form, :new
      live "/operations/assets/:id", Operations.AssetLive.Show, :show
      live "/operations/assets/:id/edit", Operations.AssetLive.Form, :edit

      # Commercial - Signals
      live "/commercial/signals", Commercial.SignalLive.Index, :index
      live "/commercial/signals/new", Commercial.SignalLive.Form, :new
      live "/commercial/signals/:id", Commercial.SignalLive.Show, :show
      live "/commercial/signals/:id/edit", Commercial.SignalLive.Form, :edit

      # Commercial - Pursuits
      live "/commercial/pursuits", Commercial.PursuitLive.Index, :index
      live "/commercial/pursuits/new", Commercial.PursuitLive.Form, :new
      live "/commercial/pursuits/:id", Commercial.PursuitLive.Show, :show
      live "/commercial/pursuits/:id/edit", Commercial.PursuitLive.Form, :edit

      # Commercial - Proposals
      live "/commercial/proposals", Commercial.ProposalLive.Index, :index
      live "/commercial/proposals/new", Commercial.ProposalLive.Form, :new
      live "/commercial/proposals/:id", Commercial.ProposalLive.Show, :show
      live "/commercial/proposals/:id/edit", Commercial.ProposalLive.Form, :edit

      # Commercial - Agreements
      live "/commercial/agreements", Commercial.AgreementLive.Index, :index
      live "/commercial/agreements/new", Commercial.AgreementLive.Form, :new
      live "/commercial/agreements/:id", Commercial.AgreementLive.Show, :show
      live "/commercial/agreements/:id/edit", Commercial.AgreementLive.Form, :edit

      # Commercial - Change Orders
      live "/commercial/change-orders", Commercial.ChangeOrderLive.Index, :index
      live "/commercial/change-orders/new", Commercial.ChangeOrderLive.Form, :new
      live "/commercial/change-orders/:id", Commercial.ChangeOrderLive.Show, :show
      live "/commercial/change-orders/:id/edit", Commercial.ChangeOrderLive.Form, :edit

      # Execution - Projects
      live "/execution/projects", Execution.ProjectLive.Index, :index
      live "/execution/projects/new", Execution.ProjectLive.Form, :new
      live "/execution/projects/:id", Execution.ProjectLive.Show, :show
      live "/execution/projects/:id/edit", Execution.ProjectLive.Form, :edit

      # Execution - Work Items
      live "/execution/work-items", Execution.WorkItemLive.Index, :index
      live "/execution/work-items/new", Execution.WorkItemLive.Form, :new
      live "/execution/work-items/:id", Execution.WorkItemLive.Show, :show
      live "/execution/work-items/:id/edit", Execution.WorkItemLive.Form, :edit

      # Execution - Assignments
      live "/execution/assignments", Execution.AssignmentLive.Index, :index
      live "/execution/assignments/new", Execution.AssignmentLive.Form, :new
      live "/execution/assignments/:id", Execution.AssignmentLive.Show, :show
      live "/execution/assignments/:id/edit", Execution.AssignmentLive.Form, :edit

      # Execution - Service Tickets
      live "/execution/service-tickets", Execution.ServiceTicketLive.Index, :index
      live "/execution/service-tickets/new", Execution.ServiceTicketLive.Form, :new
      live "/execution/service-tickets/:id", Execution.ServiceTicketLive.Show, :show
      live "/execution/service-tickets/:id/edit", Execution.ServiceTicketLive.Form, :edit

      # Execution - Work Orders
      live "/execution/work-orders", Execution.WorkOrderLive.Index, :index
      live "/execution/work-orders/new", Execution.WorkOrderLive.Form, :new
      live "/execution/work-orders/:id", Execution.WorkOrderLive.Show, :show
      live "/execution/work-orders/:id/edit", Execution.WorkOrderLive.Form, :edit

      # Execution - Maintenance Plans
      live "/execution/maintenance-plans", Execution.MaintenancePlanLive.Index, :index
      live "/execution/maintenance-plans/new", Execution.MaintenancePlanLive.Form, :new
      live "/execution/maintenance-plans/:id", Execution.MaintenancePlanLive.Show, :show
      live "/execution/maintenance-plans/:id/edit", Execution.MaintenancePlanLive.Form, :edit

      # Finance - Invoices
      live "/finance/invoices", Finance.InvoiceLive.Index, :index
      live "/finance/invoices/new", Finance.InvoiceLive.Form, :new
      live "/finance/invoices/:id", Finance.InvoiceLive.Show, :show
      live "/finance/invoices/:id/edit", Finance.InvoiceLive.Form, :edit

      # Finance - Time Entries
      live "/finance/time-entries", Finance.TimeEntryLive.Index, :index
      live "/finance/time-entries/new", Finance.TimeEntryLive.Form, :new
      live "/finance/time-entries/:id", Finance.TimeEntryLive.Show, :show
      live "/finance/time-entries/:id/edit", Finance.TimeEntryLive.Form, :edit

      # Finance - Expenses
      live "/finance/expenses", Finance.ExpenseLive.Index, :index
      live "/finance/expenses/new", Finance.ExpenseLive.Form, :new
      live "/finance/expenses/:id", Finance.ExpenseLive.Show, :show
      live "/finance/expenses/:id/edit", Finance.ExpenseLive.Form, :edit

      # Finance - Payments
      live "/finance/payments", Finance.PaymentLive.Index, :index
      live "/finance/payments/new", Finance.PaymentLive.Form, :new
      live "/finance/payments/:id", Finance.PaymentLive.Show, :show
      live "/finance/payments/:id/edit", Finance.PaymentLive.Form, :edit

      # Finance - Payment Applications
      live "/finance/payment-applications", Finance.PaymentApplicationLive.Index, :index
      live "/finance/payment-applications/new", Finance.PaymentApplicationLive.Form, :new
      live "/finance/payment-applications/:id", Finance.PaymentApplicationLive.Show, :show
      live "/finance/payment-applications/:id/edit", Finance.PaymentApplicationLive.Form, :edit

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
      live "/procurement/bids", Agents.Sales.BidLive.Index, :index
      live "/procurement/bids/:id", Agents.Sales.BidLive.Show, :show
      live "/agents/sales/prospects", Agents.Sales.ProspectsLive
      live "/procurement/sources", Agents.Sales.ProcurementSourcesLive
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

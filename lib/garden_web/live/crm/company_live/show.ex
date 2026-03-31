defmodule GnomeGardenWeb.CRM.CompanyLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    company = Sales.get_company!(id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, company.name)
     |> assign(:company, company)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@company.name}
      <:subtitle :if={@company.legal_name}>{@company.legal_name}</:subtitle>
      <:actions>
        <.button navigate={~p"/crm/companies"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.button>
        <.button variant="primary" navigate={~p"/crm/companies/#{@company}/edit"}>
          <.icon name="hero-pencil-square" class="size-4" /> Edit
        </.button>
      </:actions>
    </.header>

    <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
      <div>
        <h2 class="text-base font-semibold mb-4">Company Details</h2>
        <.list>
          <:item title="Type">{format_atom(@company.company_type)}</:item>
          <:item title="Status">{format_atom(@company.status)}</:item>
          <:item title="Region">{format_region(@company.region)}</:item>
          <:item title="Source">{format_atom(@company.source)}</:item>
          <:item :if={@company.employee_count} title="Employees">{@company.employee_count}</:item>
          <:item :if={@company.annual_revenue} title="Annual Revenue">
            ${Decimal.to_string(@company.annual_revenue)}
          </:item>
        </.list>
      </div>

      <div>
        <h2 class="text-base font-semibold mb-4">Contact Information</h2>
        <.list>
          <:item title="Website">
            <a
              :if={@company.website}
              href={@company.website}
              target="_blank"
              class="text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
            >
              {@company.website}
            </a>
            <span :if={!@company.website} class="text-zinc-400">-</span>
          </:item>
          <:item title="Phone">{@company.phone || "-"}</:item>
          <:item title="Address">{@company.address || "-"}</:item>
          <:item title="City">{@company.city || "-"}</:item>
          <:item title="State">{@company.state || "-"}</:item>
          <:item title="Postal Code">{@company.postal_code || "-"}</:item>
        </.list>
      </div>
    </div>

    <div :if={@company.description} class="mt-8">
      <h2 class="text-base font-semibold mb-2">Description</h2>
      <p class="text-sm text-zinc-600 dark:text-zinc-400 whitespace-pre-wrap">
        {@company.description}
      </p>
    </div>
    """
  end

  defp format_atom(nil), do: "-"
  defp format_atom(atom), do: atom |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()
end

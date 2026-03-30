defmodule GnomeGardenWeb.CRM.CompaniesLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Sales.Company

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Companies")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Companies</h1>
        <div class="flex gap-2">
          <a href="/admin/sales/company?action=create" class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Company
          </a>
        </div>
      </div>

      <Cinder.collection
        resource={Company}
        actor={@current_user}
        search={[placeholder: "Search companies..."]}
      >
        <:col :let={company} field="name" label="Name" filter sort search>
          <span class="font-medium">{company.name}</span>
        </:col>
        <:col :let={company} field="website" label="Website" search>
          <a :if={company.website} href={company.website} target="_blank" class="link link-primary">
            {URI.parse(company.website).host}
          </a>
          <span :if={!company.website} class="opacity-50">-</span>
        </:col>
        <:col :let={company} field="city" label="City" filter sort search>
          {company.city || "-"}
        </:col>
        <:col :let={company} field="region" label="Region" filter sort>
          {format_region(company.region)}
        </:col>
        <:col :let={company} field="source" label="Source" filter>
          {format_source(company.source)}
        </:col>
        <:col :let={company} label="">
          <a href={"/admin/sales/company/#{company.id}"} class="btn btn-xs btn-ghost">
            <.icon name="hero-pencil" class="size-4" />
          </a>
        </:col>
      </Cinder.collection>
    </div>
    """
  end

  defp format_region(nil), do: "-"
  defp format_region(region), do: region |> to_string() |> String.upcase()

  defp format_source(nil), do: "-"
  defp format_source(source), do: source |> to_string() |> String.replace("_", " ")
end

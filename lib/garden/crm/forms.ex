defmodule GnomeGarden.CRM.Forms do
  @moduledoc """
  CRM-facing form and lookup helpers for LiveViews.

  This keeps the web layer from depending on raw resource modules or
  scattering domain and form conventions across each screen.
  """

  alias GnomeGarden.Sales

  def get_company!(id, opts \\ []), do: Sales.get_company!(id, opts)
  def form_to_create_company(opts \\ []), do: Sales.form_to_create_company(opts)
  def form_to_update_company(record, opts \\ []), do: Sales.form_to_update_company(record, opts)

  def get_contact!(id, opts \\ []), do: Sales.get_contact!(id, opts)
  def list_contacts!(opts \\ []), do: Sales.list_contacts!(opts)
  def form_to_create_contact(opts \\ []), do: Sales.form_to_create_contact(opts)
  def form_to_update_contact(record, opts \\ []), do: Sales.form_to_update_contact(record, opts)

  def get_lead!(id, opts \\ []), do: Sales.get_lead!(id, opts)
  def form_to_create_lead(opts \\ []), do: Sales.form_to_create_lead(opts)
  def form_to_update_lead(record, opts \\ []), do: Sales.form_to_update_lead(record, opts)
  def form_to_quick_add_lead(opts \\ []), do: Sales.form_to_quick_add_lead(opts)

  def get_opportunity!(id, opts \\ []), do: Sales.get_opportunity!(id, opts)
  def list_companies!(opts \\ []), do: Sales.list_companies!(opts)

  def form_to_create_opportunity(opts \\ []),
    do: Sales.form_to_create_opportunity(opts)

  def form_to_update_opportunity(record, opts \\ []),
    do: Sales.form_to_update_opportunity(record, opts)

  def get_task!(id, opts \\ []), do: Sales.get_task!(id, opts)
  def form_to_create_task(opts \\ []), do: Sales.form_to_create_task(opts)
  def form_to_update_task(record, opts \\ []), do: Sales.form_to_update_task(record, opts)
end

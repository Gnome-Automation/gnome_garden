defmodule GnomeGarden.Acquisition.LeadIdentity do
  @moduledoc "Normalized durable identities for commercial lead discovery."

  alias GnomeGarden.Support.WebIdentity

  def company_domain_key(url_or_domain) do
    case WebIdentity.website_domain(url_or_domain) do
      nil -> nil
      domain -> "commercial-company-domain:#{domain}"
    end
  end
end

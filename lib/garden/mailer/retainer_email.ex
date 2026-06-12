defmodule GnomeGarden.Mailer.RetainerEmail do
  @moduledoc """
  Builds branded retainer invoice emails.

  Usage:
    retainer |> RetainerEmail.build() |> Mailer.deliver()

  `retainer` must have `:organization` loaded.
  """

  import Swoosh.Email

  require Logger

  alias GnomeGarden.Mailer.InvoiceEmail

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map()) :: Swoosh.Email.t()
  def build(retainer) do
    contact_email = InvoiceEmail.find_billing_email(retainer.organization || %{})
    org_name = (retainer.organization && retainer.organization.name) || "Client"
    amount = format_amount(retainer.amount)

    if is_nil(contact_email) do
      Logger.warning("RetainerEmail: no contact email found for org #{retainer.organization_id}, sending to billing address",
        retainer_number: retainer.retainer_number
      )
    end

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Retainer Invoice #{retainer.retainer_number} — USD #{amount}")
    |> html_body(build_html(retainer, org_name, amount))
  end

  defp build_html(retainer, org_name, amount) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8" /></head>
    <body style="font-family: sans-serif; background: #f8fafc; margin: 0; padding: 32px;">
      <div style="max-width: 560px; margin: 0 auto; background: white; border-radius: 8px; overflow: hidden; border: 1px solid #e2e8f0;">
        <div style="background: #16a34a; padding: 24px 32px;">
          <img src="#{@logo_url}" width="36" height="36" style="border-radius: 6px;" />
          <span style="color: white; font-size: 18px; font-weight: 600; margin-left: 12px;">Gnome Automation</span>
        </div>
        <div style="padding: 32px;">
          <h2 style="margin: 0 0 8px; color: #0f172a;">Retainer Invoice #{retainer.retainer_number}</h2>
          <p style="color: #64748b; margin: 0 0 24px;">Dear #{org_name},</p>
          <p style="color: #374151;">This retainer secures your upcoming work with Gnome Automation.</p>
          <div style="background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 6px; padding: 20px; margin: 24px 0;">
            <div style="font-size: 28px; font-weight: 700; color: #16a34a;">USD #{amount}</div>
            <div style="color: #64748b; font-size: 14px; margin-top: 4px;">Retainer Balance</div>
          </div>
          #{if retainer.notes, do: "<p style=\"color: #374151;\">#{retainer.notes}</p>", else: ""}
          <p style="color: #64748b; font-size: 14px; margin-top: 32px; border-top: 1px solid #e2e8f0; padding-top: 16px;">
            Gnome Automation Billing · billing@gnomeautomation.io
          </p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end

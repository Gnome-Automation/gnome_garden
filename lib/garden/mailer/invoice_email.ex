defmodule GnomeGarden.Mailer.InvoiceEmail do
  @moduledoc """
  Builds branded invoice emails with Mercury payment instructions.

  Usage:
    invoice |> InvoiceEmail.build(mercury_info) |> Mailer.deliver()

  `invoice` must have `:invoice_lines` and `:organization` loaded.
  `mercury_info` is a keyword list with `:account_number` and `:routing_number`.
  """

  import Swoosh.Email

  require Logger

  alias GnomeGarden.Operations

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map(), keyword()) :: Swoosh.Email.t()
  def build(invoice, mercury_info \\ []) do
    contact_email = find_billing_email(invoice.organization || %{})
    org_name = (invoice.organization && invoice.organization.name) || "Client"

    if is_nil(contact_email) do
      Logger.warning("InvoiceEmail: no contact email found for org #{invoice.organization_id}, sending to billing address",
        invoice_number: invoice.invoice_number
      )
    end

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Invoice #{invoice.invoice_number} — USD #{format_amount(invoice.total_amount)}")
    |> html_body(build_html(invoice, org_name, mercury_info))
  end

  @doc """
  Returns the best available email address for an organization.

  Priority:
  1. organization.billing_contact.email (if set and do_not_email is false)
  2. Any affiliated person with a valid email (existing logic)
  3. nil if no email found
  """
  @spec find_billing_email(map()) :: String.t() | nil
  def find_billing_email(organization) do
    with_billing_contact(organization) || find_affiliated_email(organization)
  end

  defp with_billing_contact(%{billing_contact: %{email: email, do_not_email: false}})
       when not is_nil(email),
       do: to_string(email)

  defp with_billing_contact(_), do: nil

  defp find_affiliated_email(organization) do
    case Operations.list_people_for_organization(organization.id, actor: nil, authorize?: false) do
      {:ok, people} ->
        Enum.find_value(people, fn person ->
          if person.email && !person.do_not_email, do: to_string(person.email)
        end)

      _ ->
        nil
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)

  defp build_html(invoice, org_name, mercury_info) do
    account_number = Keyword.get(mercury_info, :account_number, "")
    routing_number = Keyword.get(mercury_info, :routing_number, "")

    lines_html =
      (invoice.invoice_lines || [])
      |> Enum.map(fn line ->
        """
        <tr>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;">#{line.description}</td>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;text-align:right;">#{format_amount(line.line_total)}</td>
        </tr>
        """
      end)
      |> Enum.join("")

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"></head>
    <body style="margin:0;padding:0;background:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f8fafc;padding:40px 20px;">
        <tr><td align="center">
          <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;border:1px solid #e2e8f0;overflow:hidden;">
            <tr>
              <td style="background:#0f172a;padding:28px 40px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td>
                      <img src="#{@logo_url}" width="36" height="36" alt="Gnome Automation" style="display:block;border-radius:6px;">
                    </td>
                    <td style="padding-left:12px;vertical-align:middle;">
                      <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;">Gnome Automation</p>
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Invoice</p>
                    </td>
                    <td align="right" style="vertical-align:middle;">
                      <p style="margin:0;font-size:22px;font-weight:700;color:#ffffff;">#{invoice.invoice_number}</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:36px 40px;">
                <p style="margin:0 0 24px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 24px;color:#1e293b;">Please find your invoice below. Payment is due by <strong>#{invoice.due_on}</strong>.</p>
                <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-bottom:24px;">
                  <thead>
                    <tr style="background:#f1f5f9;">
                      <th style="padding:10px 16px;text-align:left;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;">Description</th>
                      <th style="padding:10px 16px;text-align:right;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;">Amount</th>
                    </tr>
                  </thead>
                  <tbody>#{lines_html}</tbody>
                  <tfoot>
                    <tr style="background:#f8fafc;">
                      <td style="padding:12px 16px;font-weight:700;color:#0f172a;">Total Due</td>
                      <td style="padding:12px 16px;text-align:right;font-weight:700;color:#0f172a;font-size:16px;">USD #{format_amount(invoice.total_amount)}</td>
                    </tr>
                  </tfoot>
                </table>
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:20px;margin-bottom:24px;">
                  <p style="margin:0 0 12px;font-weight:600;color:#0f172a;">Payment Instructions</p>
                  <p style="margin:0 0 8px;color:#1e293b;font-size:14px;">Please remit via wire transfer or ACH:</p>
                  <table cellpadding="0" cellspacing="0" style="font-size:14px;">
                    <tr><td style="padding:2px 0;color:#64748b;min-width:120px;">Bank:</td><td style="color:#0f172a;font-weight:500;">Mercury</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Account #:</td><td style="color:#0f172a;font-weight:500;">#{account_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Routing #:</td><td style="color:#0f172a;font-weight:500;">#{routing_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Reference:</td><td style="color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td></tr>
                  </table>
                </div>
                <p style="margin:0;color:#64748b;font-size:13px;">Questions? Contact billing@gnomeautomation.io</p>
              </td>
            </tr>
            <tr>
              <td style="background:#f8fafc;padding:20px 40px;border-top:1px solid #e2e8f0;">
                <p style="margin:0;font-size:12px;color:#94a3b8;text-align:center;">Gnome Automation LLC · gnomeautomation.io</p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end
end

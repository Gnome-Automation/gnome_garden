defmodule GnomeGarden.Mailer.PaymentReceiptEmail do
  @moduledoc """
  Sends a payment receipt email to the client when an invoice is marked paid.

  Usage:
    invoice |> PaymentReceiptEmail.build() |> Mailer.deliver()

  `invoice` must have `:organization` loaded.
  """

  import Swoosh.Email

  require Logger

  alias GnomeGarden.Mailer.InvoiceEmail

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"
  @portal_base_url Application.compile_env(:gnome_garden, :portal_base_url, "https://app.gnomeautomation.io")

  @spec build(map()) :: Swoosh.Email.t()
  def build(invoice) do
    contact_email = InvoiceEmail.find_billing_email(invoice.organization || %{})
    org_name = (invoice.organization && invoice.organization.name) || "Client"

    if is_nil(contact_email) do
      Logger.warning("PaymentReceiptEmail: no contact email found for org #{invoice.organization_id}",
        invoice_number: invoice.invoice_number
      )
    end

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Payment received — #{invoice.invoice_number}")
    |> html_body(build_html(invoice, org_name))
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)

  defp build_html(invoice, org_name) do
    portal_url = "#{@portal_base_url}/portal/invoices/#{invoice.id}"
    amount = format_amount(invoice.total_amount)
    paid_on = invoice.paid_on || Date.utc_today()

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
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Payment Receipt</p>
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
                <p style="margin:0 0 24px;color:#1e293b;">
                  We have received your payment for invoice <strong>#{invoice.invoice_number}</strong>.
                  Your account is now paid in full — thank you!
                </p>
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:24px;margin-bottom:24px;">
                  <p style="margin:0 0 16px;font-weight:600;color:#0f172a;font-size:16px;">Payment Summary</p>
                  <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;">
                    <tr>
                      <td style="padding:4px 0;color:#64748b;width:140px;">Invoice</td>
                      <td style="padding:4px 0;color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td>
                    </tr>
                    <tr>
                      <td style="padding:4px 0;color:#64748b;">Amount Paid</td>
                      <td style="padding:4px 0;color:#059669;font-weight:700;font-size:16px;">USD #{amount}</td>
                    </tr>
                    <tr>
                      <td style="padding:4px 0;color:#64748b;">Date</td>
                      <td style="padding:4px 0;color:#0f172a;font-weight:500;">#{paid_on}</td>
                    </tr>
                    <tr>
                      <td style="padding:4px 0;color:#64748b;">Status</td>
                      <td style="padding:4px 0;">
                        <span style="display:inline-block;background:#dcfce7;color:#166534;font-size:12px;font-weight:600;padding:2px 10px;border-radius:999px;">Paid</span>
                      </td>
                    </tr>
                  </table>
                </div>
                <div style="text-align:center;margin-bottom:24px;">
                  <a href="#{portal_url}" style="display:inline-block;background:#059669;color:#ffffff;font-weight:600;font-size:14px;padding:12px 28px;border-radius:8px;text-decoration:none;">View Receipt &rarr;</a>
                  <p style="margin:8px 0 0;font-size:12px;color:#94a3b8;">Sign in with your email to view this invoice in your client portal.</p>
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

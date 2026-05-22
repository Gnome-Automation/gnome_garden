defmodule GnomeGarden.Mailer.PaymentReminderEmail do
  @moduledoc """
  Builds payment reminder emails for overdue invoices.

  Usage:
    PaymentReminderEmail.build(invoice, :day_7) |> GnomeGarden.Mailer.deliver()
    PaymentReminderEmail.build(invoice, :day_30, cc: "owner@example.com") |> GnomeGarden.Mailer.deliver()

  `invoice` must have `:organization` loaded (with `:billing_contact`).
  """

  import Swoosh.Email

  alias GnomeGarden.Mailer.InvoiceEmail

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map(), :day_7 | :day_14 | :day_30, keyword()) :: Swoosh.Email.t()
  def build(invoice, threshold, opts \\ []) do
    org = invoice.organization
    contact_email = InvoiceEmail.find_billing_email(org || %{})
    days_overdue = days_since(invoice.due_on)

    email =
      new()
      |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
      |> to(contact_email || "billing@gnomeautomation.io")
      |> subject(subject_for(threshold, invoice.invoice_number, days_overdue))
      |> html_body(body_for(threshold, invoice, days_overdue))

    case Keyword.get(opts, :cc) do
      nil -> email
      cc_email -> cc(email, cc_email)
    end
  end

  defp subject_for(_threshold, number, days) do
    cond do
      days >= 30 -> "URGENT: Invoice #{number} is #{days} days overdue — immediate payment required"
      days >= 14 -> "Follow-up: Invoice #{number} is #{days} days overdue"
      true -> "Friendly reminder: Invoice #{number} was due #{days} days ago"
    end
  end

  defp body_for(threshold, invoice, days_overdue) do
    org_name = (invoice.organization && invoice.organization.name) || "Client"
    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])
    account_number = Keyword.get(mercury_info, :account_number, "")
    routing_number = Keyword.get(mercury_info, :routing_number, "")

    tone =
      cond do
        days_overdue >= 30 -> "This is an urgent notice that"
        days_overdue >= 14 -> "We wanted to follow up as"
        true -> "This is a friendly reminder that"
      end

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
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Payment Reminder</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:32px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 16px;color:#1e293b;">#{tone} invoice <strong>#{invoice.invoice_number}</strong> for <strong>USD #{format_amount(invoice.balance_amount)}</strong> is now <strong>#{days_overdue} days overdue</strong> (original due date: #{invoice.due_on}).</p>
                <p style="margin:0 0 24px;color:#1e293b;">Please remit payment at your earliest convenience using the instructions below:</p>
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:20px;margin-bottom:24px;">
                  <p style="margin:0 0 12px;font-weight:600;color:#0f172a;">Payment Instructions (ACH / Wire)</p>
                  <table cellpadding="0" cellspacing="0" style="font-size:14px;">
                    <tr><td style="padding:2px 0;color:#64748b;min-width:120px;">Bank:</td><td style="color:#0f172a;font-weight:500;">Mercury</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Account #:</td><td style="color:#0f172a;font-weight:500;">#{account_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Routing #:</td><td style="color:#0f172a;font-weight:500;">#{routing_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Reference:</td><td style="color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td></tr>
                  </table>
                </div>
                <p style="margin:0;color:#64748b;font-size:13px;">Questions? Reply to billing@gnomeautomation.io</p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp days_since(nil), do: 0
  defp days_since(due_on), do: Date.diff(Date.utc_today(), due_on)

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end

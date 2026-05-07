defmodule GnomeGarden.Mailer.CreditNoteEmail do
  @moduledoc """
  Builds branded credit note emails.

  Usage:
    credit_note |> CreditNoteEmail.build() |> GnomeGarden.Mailer.deliver()

  `credit_note` must have loaded:
    - :credit_note_lines
    - :invoice (for invoice_number)
    - organization: [:billing_contact]
  """

  import Swoosh.Email

  alias GnomeGarden.Mailer.InvoiceEmail

  @spec build(map()) :: Swoosh.Email.t()
  def build(credit_note) do
    org = credit_note.organization
    contact_email = InvoiceEmail.find_billing_email(org || %{})
    invoice_number = (credit_note.invoice && credit_note.invoice.invoice_number) || "N/A"
    org_name = (org && org.name) || "Client"

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Credit Note #{credit_note.credit_note_number} — Invoice #{invoice_number} has been credited")
    |> html_body(build_html(credit_note, org_name, invoice_number))
  end

  defp build_html(credit_note, org_name, invoice_number) do
    lines_html =
      (credit_note.credit_note_lines || [])
      |> Enum.map(fn line ->
        """
        <tr>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;">#{line.description}</td>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;text-align:right;">#{format_amount(line.line_total)}</td>
        </tr>
        """
      end)
      |> Enum.join("")

    reason_html =
      if credit_note.reason do
        """
        <p style="margin:0 0 16px;color:#1e293b;"><strong>Reason:</strong> #{credit_note.reason}</p>
        """
      else
        ""
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
                <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;">Gnome Automation</p>
                <p style="margin:4px 0 0;font-size:13px;color:#94a3b8;">Credit Note #{credit_note.credit_note_number}</p>
              </td>
            </tr>
            <tr>
              <td style="padding:36px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 16px;color:#1e293b;">Please find your credit note below, issued against invoice <strong>#{invoice_number}</strong>.</p>
                #{reason_html}
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
                      <td style="padding:12px 16px;font-weight:700;color:#0f172a;">Credit Total</td>
                      <td style="padding:12px 16px;text-align:right;font-weight:700;color:#dc2626;font-size:16px;">#{credit_note.currency_code} #{format_amount(credit_note.total_amount)}</td>
                    </tr>
                  </tfoot>
                </table>
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

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end

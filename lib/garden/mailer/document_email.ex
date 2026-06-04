defmodule GnomeGarden.Mailer.DocumentEmail do
  @moduledoc """
  Builds a branded email that delivers a company document (PDF attachment) to a client.

  NOTE: The document's `file_path` must point to an existing file under `priv/static/` at email delivery time.
  The path is resolved via `Application.app_dir(:gnome_garden, "priv/static")`. If the file does not exist,
  `Mailer.deliver/1` will raise an error.

  Usage:
    DocumentEmail.build(document, "client@example.com")
    DocumentEmail.build(document, "client@example.com", org_name: "Acme Corp", message: "Please keep for your records.")
    |> GnomeGarden.Mailer.deliver()
  """

  import Swoosh.Email

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map(), String.t(), keyword()) :: Swoosh.Email.t()
  def build(document, to_email, opts \\ []) do
    org_name = Keyword.get(opts, :org_name, "")
    message = Keyword.get(opts, :message, nil)
    file_path = Path.join(Application.app_dir(:gnome_garden, "priv/static"), document.file_path)
    filename = build_filename(document)

    new()
    |> from({"Gnome Automation", "billing@gnomeautomation.io"})
    |> to(to_email)
    |> subject("Gnome Automation — #{document.name}")
    |> html_body(build_html(document, org_name, message))
    |> attachment(%Swoosh.Attachment{
         path: file_path,
         filename: filename,
         content_type: "application/pdf"
       })
  end

  defp build_filename(document) do
    base = document.name |> String.replace(~r/[^a-zA-Z0-9]/, "-") |> String.trim("-")
    "Gnome-Automation-#{base}-#{document.version}.pdf"
  end

  defp build_html(document, org_name, message) do
    greeting = if org_name != "", do: "Dear #{org_name},", else: "Hello,"
    message_block =
      if message do
        "<p style=\"margin:0 0 16px;color:#1e293b;\">#{message}</p>"
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
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td>
                      <img src="#{@logo_url}" width="36" height="36" alt="Gnome Automation" style="display:block;border-radius:6px;">
                    </td>
                    <td style="padding-left:12px;vertical-align:middle;">
                      <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;">Gnome Automation</p>
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Document Delivery</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:32px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">#{greeting}</p>
                <p style="margin:0 0 16px;color:#1e293b;">Please find attached: <strong>#{document.name}</strong> (v#{document.version}).</p>
                #{message_block}
                <p style="margin:24px 0 0;color:#64748b;font-size:13px;">Questions? Reply to billing@gnomeautomation.io</p>
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

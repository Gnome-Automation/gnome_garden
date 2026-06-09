defmodule GnomeGarden.Mailer.DocumentEmail do
  @moduledoc """
  Builds a branded email that delivers a company document (PDF attachment) to a client.

  Supports two storage backends:
  - AshStorage-managed files: bytes are downloaded from the configured storage service and
    attached as binary data via `%Swoosh.Attachment{data: ...}`.
  - Legacy static files: the document's `file_path` points to a file under `priv/static/`.

  The document passed to `build/3` must have `file: [blob: []]` loaded when using AshStorage.
  If neither an AshStorage blob nor a `file_path` is present, the email is sent without an
  attachment (a warning is logged).

  Usage:
    document_with_file = Ash.load!(document, [file: [blob: []]], authorize?: false)
    DocumentEmail.build(document_with_file, "client@example.com")
    DocumentEmail.build(document_with_file, "client@example.com", org_name: "Acme Corp", message: "Please keep for your records.")
    |> GnomeGarden.Mailer.deliver()
  """

  import Swoosh.Email

  require Logger

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map(), String.t(), keyword()) :: Swoosh.Email.t()
  def build(document, to_email, opts \\ []) do
    org_name = Keyword.get(opts, :org_name, "")
    message = Keyword.get(opts, :message, nil)
    filename = build_filename(document)

    base_email =
      new()
      |> from({"Gnome Automation", "billing@gnomeautomation.io"})
      |> to(to_email)
      |> subject("Gnome Automation — #{document.name}")
      |> html_body(build_html(document, org_name, message))

    case build_attachment(document, filename) do
      nil ->
        base_email

      swoosh_attachment ->
        attachment(base_email, swoosh_attachment)
    end
  end

  defp build_attachment(document, filename) do
    cond do
      # AshStorage-managed blob
      match?(%{file: %{blob: blob}} when is_map(blob), document) ->
        blob = document.file.blob
        case download_blob(blob) do
          {:ok, binary} ->
            %Swoosh.Attachment{
              data: binary,
              filename: filename,
              content_type: blob.content_type || "application/pdf",
              type: :attachment
            }

          {:error, reason} ->
            Logger.warning("DocumentEmail: failed to download blob for document #{document.id}: #{inspect(reason)}")
            nil
        end

      # Legacy static file
      is_binary(document.file_path) ->
        static_path = Path.join(Application.app_dir(:gnome_garden, "priv/static"), document.file_path)
        %Swoosh.Attachment{
          path: static_path,
          filename: filename,
          content_type: "application/pdf"
        }

      true ->
        Logger.warning("DocumentEmail: no file available for document #{document.id}, sending without attachment")
        nil
    end
  end

  defp download_blob(%{service_name: service, key: key} = blob) when is_atom(service) do
    service.download(key, AshStorage.Service.Context.new(service_opts(blob)))
  end

  defp service_opts(blob) do
    persisted_opts = normalize_service_opts(blob.service_opts)

    case configured_document_service() do
      {service, runtime_opts} when service == blob.service_name ->
        Keyword.merge(persisted_opts, runtime_opts)

      _other ->
        persisted_opts
    end
  end

  defp configured_document_service do
    :gnome_garden
    |> Application.get_env(GnomeGarden.Documents.CompanyDocument, [])
    |> Keyword.get(:storage, [])
    |> Keyword.get(:service)
  end

  defp normalize_service_opts(opts) when is_list(opts), do: opts

  defp normalize_service_opts(opts) when is_map(opts) do
    opts
    |> Enum.flat_map(fn
      {key, value} when is_atom(key) ->
        [{key, value}]

      {key, value} when is_binary(key) ->
        case known_service_opt(key) do
          nil -> []
          atom_key -> [{atom_key, value}]
        end
    end)
  end

  defp normalize_service_opts(_opts), do: []

  defp known_service_opt("access_key_id"), do: :access_key_id
  defp known_service_opt("base_url"), do: :base_url
  defp known_service_opt("bucket"), do: :bucket
  defp known_service_opt("endpoint_url"), do: :endpoint_url
  defp known_service_opt("name"), do: :name
  defp known_service_opt("prefix"), do: :prefix
  defp known_service_opt("region"), do: :region
  defp known_service_opt("root"), do: :root
  defp known_service_opt("secret_access_key"), do: :secret_access_key
  defp known_service_opt(_key), do: nil

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

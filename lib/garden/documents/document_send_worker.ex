defmodule GnomeGarden.Documents.DocumentSendWorker do
  @moduledoc """
  Oban worker that sends a company document to one organization.

  Enqueued by DocumentsLive for bulk send operations.
  Each job handles one (document_id, organization_id) pair.

  Args:
    - document_id: UUID of CompanyDocument
    - organization_id: UUID of Organization
    - sent_by_user_id: UUID of the staff user who triggered the send
    - message: optional message string (may be nil)
  """

  use Oban.Worker, queue: :default

  alias GnomeGarden.Documents
  alias GnomeGarden.Operations
  alias GnomeGarden.Mailer.DocumentEmail
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    document_id = args["document_id"]
    org_id = args["organization_id"]
    sent_by_user_id = args["sent_by_user_id"]
    message = args["message"]

    with {:ok, document} <- Documents.get_document(document_id, load: [file: [blob: []]]),
         {:ok, org} <- Operations.get_organization(org_id) do
      loaded_org = Ash.load!(org, [:billing_contact], authorize?: false)
      to_email = InvoiceEmail.find_billing_email(loaded_org) || "billing@gnomeautomation.io"

      email =
        DocumentEmail.build(document, to_email,
          org_name: org.name,
          message: message
        )

      case Mailer.deliver(email) do
        {:ok, _} ->
          Documents.log_send(%{
            company_document_id: document.id,
            organization_id: org.id,
            sent_to_email: to_email,
            sent_by_user_id: sent_by_user_id,
            message: message
          })
          :ok

        {:error, reason} ->
          Logger.error("DocumentSendWorker: failed to deliver email to #{to_email}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("DocumentSendWorker: could not load document or org: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

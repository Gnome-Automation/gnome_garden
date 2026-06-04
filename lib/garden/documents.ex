defmodule GnomeGarden.Documents do
  use Ash.Domain,
    otp_app: :gnome_garden

  resources do
    resource GnomeGarden.Documents.CompanyDocument do
      define :list_active_documents, action: :active
      define :list_all_documents, action: :all_versions
      define :get_document, action: :read, get_by: [:id]
      define :create_document, action: :create
      define :update_document, action: :update
      define :destroy_document, action: :destroy
    end

    resource GnomeGarden.Documents.DocumentSendLog do
      define :log_send, action: :create
      define :list_send_logs, action: :read
      define :list_send_logs_for_document,
        action: :by_document,
        args: [:document_id]
    end
  end
end

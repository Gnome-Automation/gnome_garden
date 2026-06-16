defmodule GnomeGarden.Commercial.Actions.PopulateVendorRequirementArtifact do
  @moduledoc """
  Creates a filled DOCX draft from a customer-provided vendor form artifact.
  """

  use Ash.Resource.Actions.Implementation

  alias AshStorage.Service.Context
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.VendorFormFiller
  alias GnomeGarden.Company.DefaultProfiles
  alias GnomeGarden.Company.VendorRegistrationPacket

  @docx_content_type "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  @impl true
  def run(input, _opts, context) do
    artifact_id = Ash.ActionInput.get_argument(input, :artifact_id)
    actor = context.actor

    with {:ok, artifact} <- load_source_artifact(artifact_id, actor),
         :ok <- ensure_docx!(artifact),
         {:ok, source_bytes} <- download_blob(artifact.file.blob),
         packet <- build_packet(),
         {values, missing_fields} <- VendorFormFiller.values_from_packet(packet),
         {:ok, filled_bytes} <- VendorFormFiller.fill_docx(source_bytes, values),
         {:ok, filled_artifact} <-
           create_filled_artifact(artifact, filled_bytes, packet, values, missing_fields, actor),
         {:ok, _source} <- mark_source_extracted(artifact, packet, missing_fields, actor) do
      {:ok,
       %{
         "artifact_id" => filled_artifact.id,
         "title" => filled_artifact.title,
         "missing_fields" => missing_fields
       }}
    end
  rescue
    error -> {:error, error}
  end

  defp load_source_artifact(artifact_id, actor) do
    with {:ok, artifact} <- Commercial.get_customer_vendor_requirement_artifact(artifact_id) do
      artifact =
        Ash.load!(artifact, [file: :blob],
          actor: actor,
          authorize?: false
        )

      {:ok, artifact}
    end
  end

  defp ensure_docx!(%{file: %{blob: %{filename: filename, content_type: content_type}}}) do
    cond do
      filename |> to_string() |> String.downcase() |> String.ends_with?(".docx") ->
        :ok

      content_type == @docx_content_type ->
        :ok

      true ->
        {:error, "Only DOCX source forms can be populated in this first pass."}
    end
  end

  defp ensure_docx!(_artifact), do: {:error, "Source artifact does not have an attached file."}

  defp download_blob(blob) do
    blob = Ash.load!(blob, :parsed_service_opts, authorize?: false)

    ctx =
      blob.parsed_service_opts
      |> Kernel.||([])
      |> Context.new()
      |> Context.put_expected_md5(blob.checksum)

    blob.service_name.download(blob.key, ctx)
  end

  defp build_packet do
    profile = DefaultProfiles.ensure_default().profile
    metadata = profile.metadata || %{}

    profile = %{profile | metadata: metadata}

    packet = VendorRegistrationPacket.build(profile, reveal_sensitive?: true)
    Map.put(packet, :profile_metadata, metadata)
  end

  defp create_filled_artifact(source, filled_bytes, packet, values, missing_fields, actor) do
    path =
      Path.join(
        System.tmp_dir!(),
        "#{Ecto.UUID.generate()}-#{VendorFormFiller.draft_filename(source.file.blob.filename)}"
      )

    File.write!(path, filled_bytes)

    try do
      Commercial.create_customer_vendor_requirement_artifact(
        %{
          customer_vendor_requirement_id: source.customer_vendor_requirement_id,
          title: "#{source.title} filled draft",
          kind: :filled_docx,
          status: :drafted,
          notes: draft_notes(missing_fields),
          metadata:
            (source.metadata || %{})
            |> Map.put("source_artifact_id", source.id)
            |> Map.put("source_artifact_title", source.title)
            |> Map.put("fill", VendorFormFiller.metadata_for(packet, values, missing_fields)),
          file: Ash.Type.File.from_path(path)
        },
        actor: actor,
        authorize?: false
      )
    after
      File.rm(path)
    end
  end

  defp mark_source_extracted(source, packet, missing_fields, actor) do
    metadata =
      (source.metadata || %{})
      |> Map.put("extraction", %{
        "status" => "mapped_to_company_packet",
        "profile_id" => packet.profile_id,
        "missing_fields" => missing_fields
      })

    Commercial.extract_customer_vendor_requirement_artifact(source, %{metadata: metadata},
      actor: actor,
      authorize?: false
    )
  end

  defp draft_notes([]), do: "Filled draft created from reusable company packet data."

  defp draft_notes(missing_fields) do
    "Filled draft created. Missing fields need human review: #{Enum.join(missing_fields, ", ")}."
  end
end

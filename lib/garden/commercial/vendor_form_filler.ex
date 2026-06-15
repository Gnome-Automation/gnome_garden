defmodule GnomeGarden.Commercial.VendorFormFiller do
  @moduledoc """
  Deterministic first-pass filler for customer vendor-registration DOCX forms.

  This is intentionally format mechanics, not business state. The Ash action
  owns the artifact lifecycle; this module only transforms DOCX bytes using a
  normalized packet map.
  """

  @doc """
  Returns form values and missing fields from the reusable company packet.
  """
  def values_from_packet(packet) do
    fields =
      packet.sections
      |> Enum.flat_map(& &1.fields)
      |> Map.new(&{&1.id, &1.value})

    values = %{
      legal_entity_name: field_value(fields, "legal_entity_name"),
      registered_address: field_value(fields, "legal_address"),
      postcode: postcode(field_value(fields, "legal_address")),
      country: country(field_value(fields, "legal_address")),
      telephone_number: packet_metadata_value(packet, ["company", "telephone_number"]),
      email_for_orders: packet_metadata_value(packet, ["contacts", "orders_email"]),
      fein_us: field_value(fields, "fein_us"),
      sales_tax_id_us: field_value(fields, "sales_tax_id_us"),
      delivery_terms: field_value(fields, "delivery_terms"),
      payment_terms: field_value(fields, "payment_terms"),
      currency: packet_metadata_value(packet, ["standard_terms", "currency"]) || "USD",
      vendor_contact_name: packet_metadata_value(packet, ["contacts", "vendor_contact", "name"]),
      vendor_contact_phone:
        packet_metadata_value(packet, ["contacts", "vendor_contact", "phone"]),
      vendor_purchasing_email: packet_metadata_value(packet, ["contacts", "purchasing_email"]),
      vendor_finance_email: packet_metadata_value(packet, ["contacts", "finance_email"]),
      bank_name: field_value(fields, "bank_of_record"),
      bank_address: field_value(fields, "bank_address"),
      bank_account_number: field_value(fields, "account_number"),
      swift_address: field_value(fields, "swift_bic"),
      iban: field_value(fields, "international_account_number") || "N/A",
      ach_routing_number: field_value(fields, "routing_number"),
      wire_routing_number: field_value(fields, "routing_number"),
      signer_name: packet_metadata_value(packet, ["company", "signing_authority", "name"]),
      signer_title: packet_metadata_value(packet, ["company", "signing_authority", "title"])
    }

    missing =
      values
      |> Enum.filter(fn
        {_key, value} -> missing?(value)
      end)
      |> Enum.map(fn {key, _value} -> Atom.to_string(key) end)

    {values, missing}
  end

  @doc """
  Fills known label/value slots in a DOCX binary.
  """
  def fill_docx(docx_binary, values) when is_binary(docx_binary) and is_map(values) do
    with {:ok, files} <- unzip(docx_binary),
         {:ok, document_xml} <- fetch_document_xml(files) do
      filled_xml = fill_document_xml(document_xml, values)
      rezipped(files, filled_xml)
    end
  end

  def draft_filename(filename) when is_binary(filename) do
    root = filename |> Path.basename() |> Path.rootname()
    "#{root}-filled-draft.docx"
  end

  def fill_document_xml(document_xml, values) do
    replacements(values)
    |> Enum.reduce(document_xml, fn
      {:all, label, value}, xml -> replace_label_value(xml, label, value, global?: true)
      {label, value}, xml -> replace_label_value(xml, label, value, global?: false)
    end)
  end

  def metadata_for(packet, values, missing_fields) do
    %{
      "populate_workflow" => "deterministic_docx_label_fill",
      "source_profile_id" => packet.profile_id,
      "source_profile_key" => packet.profile_key,
      "source_legal_name" => packet.legal_name,
      "missing_fields" => missing_fields,
      "filled_fields" =>
        values
        |> Enum.reject(fn {_key, value} -> missing?(value) end)
        |> Enum.map(fn {key, _value} -> Atom.to_string(key) end)
    }
  end

  defp unzip(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, "Could not read DOCX zip: #{inspect(reason)}"}
    end
  end

  defp fetch_document_xml(files) do
    case Enum.find(files, fn {path, _contents} -> to_string(path) == "word/document.xml" end) do
      {_path, xml} -> {:ok, IO.iodata_to_binary(xml)}
      nil -> {:error, "DOCX is missing word/document.xml"}
    end
  end

  defp rezipped(files, filled_xml) do
    updated_files =
      Enum.map(files, fn
        {~c"word/document.xml", _contents} -> {~c"word/document.xml", filled_xml}
        {path, contents} -> {path, contents}
      end)

    case :zip.create(~c"filled.docx", updated_files, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      {:error, reason} -> {:error, "Could not write filled DOCX: #{inspect(reason)}"}
    end
  end

  defp replacements(values) do
    [
      {:all, "Legal Entity name:", values.legal_entity_name},
      {"Registered Address of Company:", values.registered_address},
      {"Postcode:", values.postcode},
      {"Country:", values.country},
      {"Telephone number:", values.telephone_number},
      {"E-mail for orders:", values.email_for_orders},
      {"FEIN (US):", values.fein_us},
      {"Sales TAX ID (US):", values.sales_tax_id_us},
      {"Delivery terms (standard DDP or DAP):", values.delivery_terms},
      {"Payment terms (standard min 60 days net):", values.payment_terms},
      {"Currency:", values.currency},
      {"Vendor contact (name):", values.vendor_contact_name},
      {"Direct phone number:", values.vendor_contact_phone},
      {"E-mail for Purchasing:", values.vendor_purchasing_email},
      {"E-mail for Finance:", values.vendor_finance_email},
      {"Bank name:", values.bank_name},
      {"Bank address:", values.bank_address},
      {"Bank account / Bank Giro:", values.bank_account_number},
      {"IFSC Code (India):", "N/A"},
      {"Swift address:", values.swift_address},
      {"IBAN:", values.iban},
      {"Bank Routing Number (ACH):", values.ach_routing_number},
      {"Bank Routing Number (Wire):", values.wire_routing_number},
      {"Name:", values.signer_name},
      {"Title:", values.signer_title}
    ]
  end

  defp replace_label_value(xml, _label, value, _opts) when value in [nil, ""], do: xml

  defp replace_label_value(xml, label, value, opts) do
    escaped_value = xml_escape(to_string(value))
    global? = Keyword.fetch!(opts, :global?)

    xml
    |> String.replace(
      ~s(<w:t>#{label}</w:t>),
      ~s(<w:t xml:space="preserve">#{label} #{escaped_value}</w:t>),
      global: global?
    )
    |> String.replace(
      ~s(<w:t>#{label} </w:t>),
      ~s(<w:t xml:space="preserve">#{label} #{escaped_value}</w:t>),
      global: global?
    )
    |> String.replace(
      ~s(<w:t xml:space="preserve">#{label} </w:t>),
      ~s(<w:t xml:space="preserve">#{label} #{escaped_value}</w:t>),
      global: global?
    )
  end

  defp field_value(fields, key) do
    case Map.get(fields, key) do
      value when value in [nil, "", "NOT_CAPTURED", "Missing"] -> nil
      value -> value
    end
  end

  defp packet_metadata_value(packet, path) do
    packet
    |> Map.get(:profile_metadata, %{})
    |> get_in(["vendor_registration" | path])
    |> normalize_value()
  end

  defp postcode(nil), do: nil

  defp postcode(address) do
    case Regex.run(~r/\b\d{5}(?:-\d{4})?\b/, address) do
      [zip] -> zip
      _ -> nil
    end
  end

  defp country(nil), do: nil

  defp country(address) do
    cond do
      String.contains?(address, "United States") -> "United States of America"
      String.contains?(address, "US") -> "United States of America"
      true -> nil
    end
  end

  defp missing?(value), do: normalize_value(value) in [nil, "", "NOT_CAPTURED", "Missing"]

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(value), do: value

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end

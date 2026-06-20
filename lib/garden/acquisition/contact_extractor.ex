defmodule GnomeGarden.Acquisition.ContactExtractor do
  @moduledoc """
  Extracts contacts and firmographic context from fetched page text.

  Hybrid by design:

    * **Regex** pulls emails and phone numbers — near-free, high precision,
      ground-truth strings taken verbatim from the page (an LLM summarizer often
      drops these to `null`).
    * **Structured LLM extraction** associates *named* people with titles/roles
      and summarizes firmographic context, which regex cannot do. The default
      source is Exa's own `/contents` structured `summary` (passed in via
      `:structured`, so no separate LLM key is needed); a `ReqLLM`/GLM path
      remains available via `:llm_fun`.

  LLMs confabulate people from headings ("Leadership", "Our Team"), so every
  candidate person passes a guardrail: a real first AND last name, not a generic
  label, and not the company name itself. No name is ever fabricated.

  The two are merged honestly:

    * A named person needs a first AND last name (the `Operations.Person` model
      requires both), so single-token names are never promoted to people — no
      name is ever fabricated from an email local-part.
    * Emails/phones that aren't attached to a named person stay as **org-level
      contact info** (a main line / general inbox), not invented people.

  The LLM step is *optional and degrades gracefully*: if it is disabled or fails
  (e.g. an expired key), extraction still returns the regex contact info and an
  `llm: %{status: :error, ...}` marker, rather than raising. The LLM function is
  injectable via `:llm_fun` so callers/tests can run fully offline.
  """

  require Logger

  @default_model "zai:glm-4.7"
  @max_text_for_llm 12_000

  # Asset/placeholder local-or-host fragments that are never real contacts.
  @junk_email_markers ~w(sentry example.com example.org yourdomain domain.com
    wixpress.com .png .jpg .jpeg .gif .svg .webp .css .js)

  @email_regex ~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
  @phone_regex ~r/(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/

  # Heading-ish labels an LLM may emit as a "person" — these are not people.
  @generic_name_markers ~w(leadership team management company our about contact
    staff department group division office board executive executives founders
    inc llc corp corporation co)

  @type person :: %{
          first_name: String.t(),
          last_name: String.t(),
          title: String.t() | nil,
          role: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          confidence: float(),
          source: :llm,
          source_url: String.t() | nil
        }

  @type result :: %{
          people: [person()],
          org_contact: %{emails: [String.t()], phones: [String.t()]},
          firmographic: map() | nil,
          llm: %{status: :ok | :skipped | :error, cost: float() | nil, error: term() | nil}
        }

  @doc """
  Extracts contacts from `text`. Options:

    * `:source_url` — provenance stamped on each person
    * `:company` — company name; used as LLM context and to reject self-named "people"
    * `:structured` — a pre-extracted `%{people: [...], firmographic: %{...}}` map
      (e.g. Exa's `/contents` structured summary). When present this is the
      extraction source and no separate LLM call is made.
    * `:structured_cost` — cost already paid for `:structured` (for reporting)
    * `:use_llm` — run the GLM step when no `:structured` is given (default `true`)
    * `:llm_fun` — override the LLM call with `fn text, opts -> {:ok, %{people:, firmographic:, cost:}} | {:error, term} end`
    * `:model` — model spec (default `#{@default_model}`)
  """
  @spec extract(String.t() | nil, keyword()) :: result()
  def extract(text, opts \\ [])

  def extract(nil, _opts), do: empty_result(:skipped)

  def extract(text, opts) when is_binary(text) do
    source_url = Keyword.get(opts, :source_url)
    regex_emails = scan_emails(text)
    regex_phones = scan_phones(text)

    {people, llm_meta, llm_firmographic} = derive_people(text, opts)

    people =
      people
      |> Enum.map(&finalize_person(&1, regex_emails, regex_phones, source_url))
      |> Enum.reject(&(&1 == :unnamed))

    {claimed_emails, claimed_phones} = claimed_contact_info(people)

    %{
      people: people,
      org_contact: %{
        emails: Enum.reject(regex_emails, &(&1 in claimed_emails)),
        phones: Enum.reject(regex_phones, &(&1 in claimed_phones))
      },
      firmographic: llm_firmographic,
      llm: llm_meta
    }
  end

  # --- Regex extraction --------------------------------------------------------

  defp scan_emails(text) do
    @email_regex
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.reject(&junk_email?/1)
  end

  defp junk_email?(email) do
    Enum.any?(@junk_email_markers, &String.contains?(email, &1))
  end

  defp scan_phones(text) do
    @phone_regex
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
    # A bare 7-digit run with no separators is usually a code/zip, not a phone.
    |> Enum.filter(&(String.replace(&1, ~r/\D/, "") |> String.length() >= 10))
  end

  # --- Structured / LLM extraction ---------------------------------------------

  # Prefer a pre-extracted structured map (Exa summary). Otherwise run the GLM
  # seam, unless disabled. Either way, candidate people pass the name guardrail.
  defp derive_people(text, opts) do
    company = Keyword.get(opts, :company)

    cond do
      structured = Keyword.get(opts, :structured) ->
        {normalize_people(structured, company),
         %{status: :ok, cost: Keyword.get(opts, :structured_cost), error: nil},
         normalize_firmographic(structured)}

      Keyword.get(opts, :use_llm, true) ->
        run_llm(text, opts, company)

      true ->
        {[], %{status: :skipped, cost: nil, error: nil}, nil}
    end
  end

  defp run_llm(text, opts, company) do
    llm_fun = Keyword.get(opts, :llm_fun, &default_llm/2)

    case llm_fun.(truncate(text), opts) do
      {:ok, %{} = data} ->
        {normalize_people(data, company), %{status: :ok, cost: Map.get(data, :cost), error: nil},
         normalize_firmographic(data)}

      {:error, reason} ->
        Logger.warning("ContactExtractor LLM step failed: #{inspect(reason)}")
        {[], %{status: :error, cost: nil, error: reason}, nil}
    end
  end

  defp truncate(text), do: String.slice(text, 0, @max_text_for_llm)

  @contacts_schema [
    people: [
      type:
        {:list,
         {:map,
          [
            name: [type: :string, required: true, doc: "Full name of a real person"],
            title: [type: :string, doc: "Job title"],
            role: [type: :string, doc: "Business role, e.g. buyer, engineer, procurement"],
            email: [type: :string],
            phone: [type: :string]
          ]}},
      doc: "Named individuals explicitly identified on the page. Empty if none."
    ],
    firmographic: [
      type:
        {:map,
         [
           summary: [type: :string, doc: "One-sentence description of the company"],
           headquarters: [type: :string],
           employee_estimate: [type: :string]
         ]},
      doc: "Company facts stated on the page."
    ]
  ]

  defp default_llm(text, opts) do
    company = Keyword.get(opts, :company)
    model = Keyword.get(opts, :model, @default_model)

    prompt = """
    Extract real, named people and firmographic facts from the following page text\
    #{if company, do: " for the company \"#{company}\"", else: ""}.

    Rules:
    - Only include people who are explicitly named on the page. Do NOT invent names.
    - Do NOT turn an email address or generic inbox into a person.
    - If no named people appear, return an empty people list.

    PAGE TEXT:
    #{text}
    """

    case ReqLLM.generate_object(model, prompt, @contacts_schema) do
      {:ok, response} ->
        object = ReqLLM.Response.object(response)

        {:ok,
         %{
           people: object |> fetch(["people", :people]) |> List.wrap(),
           firmographic: fetch(object, ["firmographic", :firmographic]),
           cost: get_in(response.usage, [:total_cost]) || get_in(response.usage, [:cost, :total])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Accepts either Exa's structured summary (string keys) or a GLM object (atom
  # or string keys); `fetch/2` tries both. Every candidate passes the name
  # guardrail so heading-derived confabulations are dropped.
  defp normalize_people(%{} = data, company) do
    data
    |> fetch(["people", :people])
    |> List.wrap()
    |> Enum.map(fn p ->
      %{
        name: fetch(p, ["name", :name]),
        title: fetch(p, ["title", :title]),
        role: fetch(p, ["role", :role]),
        email: fetch(p, ["email", :email]),
        phone: fetch(p, ["phone", :phone])
      }
    end)
    |> Enum.filter(&valid_person_name?(&1.name, company))
  end

  defp normalize_people(_data, _company), do: []

  # A real person name: two or more alphabetic tokens, NONE of them a generic
  # heading word ("Leadership", "Team", "Inc"...), and not merely a rephrasing
  # of the company's own name (every token already in the company name).
  defp valid_person_name?(name, company) when is_binary(name) do
    alpha_tokens =
      name
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&Regex.match?(~r/^[A-Za-z][A-Za-z.'-]*$/, &1))
      |> Enum.map(&String.downcase/1)

    length(alpha_tokens) >= 2 and
      not Enum.any?(alpha_tokens, &(&1 in @generic_name_markers)) and
      not all_company_tokens?(alpha_tokens, company)
  end

  defp valid_person_name?(_name, _company), do: false

  defp all_company_tokens?(_tokens, nil), do: false

  defp all_company_tokens?(tokens, company) do
    company_tokens =
      company |> String.downcase() |> String.split(~r/[^a-z]+/, trim: true) |> MapSet.new()

    Enum.all?(tokens, &MapSet.member?(company_tokens, &1))
  end

  defp normalize_firmographic(%{} = object) do
    case fetch(object, ["firmographic", :firmographic]) do
      %{} = firm when map_size(firm) > 0 ->
        %{
          summary: fetch(firm, ["summary", :summary]),
          headquarters: fetch(firm, ["headquarters", :headquarters]),
          employee_estimate: fetch(firm, ["employee_estimate", :employee_estimate])
        }

      _ ->
        nil
    end
  end

  defp normalize_firmographic(_), do: nil

  # --- Merge -------------------------------------------------------------------

  defp finalize_person(llm_person, regex_emails, regex_phones, source_url) do
    {first, last} = split_name(llm_person.name)

    %{
      first_name: first,
      last_name: last,
      title: presence(llm_person.title),
      role: presence(llm_person.role),
      email: resolve_email(llm_person, first, last, regex_emails),
      phone: presence(llm_person.phone) || nil,
      confidence: if(presence(llm_person.email), do: 0.8, else: 0.6),
      source: :llm,
      source_url: source_url
    }
    |> drop_unnamed(regex_phones)
  end

  # Person requires both names; if the LLM gave only one token, this isn't a
  # usable person record — mark it so the orchestrator can skip it.
  defp split_name(name) do
    case name |> to_string() |> String.split(~r/\s+/, trim: true) do
      [single] -> {single, nil}
      [first | rest] -> {first, Enum.join(rest, " ")}
      [] -> {nil, nil}
    end
  end

  defp drop_unnamed(%{first_name: f, last_name: l} = person, _phones)
       when is_binary(f) and is_binary(l) and f != "" and l != "",
       do: person

  defp drop_unnamed(_person, _phones), do: :unnamed

  # Prefer the LLM's email; otherwise attach a regex email whose local part
  # resembles the person's name (never fabricate one).
  defp resolve_email(%{email: email}, _first, _last, _regex_emails) when is_binary(email) and email != "",
    do: String.downcase(email)

  defp resolve_email(_llm_person, first, last, regex_emails) do
    f = normalize_token(first)
    l = normalize_token(last)

    Enum.find(regex_emails, fn email ->
      local = email |> String.split("@") |> List.first() |> String.downcase()
      (f != "" and String.contains?(local, f)) or (l != "" and String.contains?(local, l))
    end)
  end

  defp claimed_contact_info(people) do
    {Enum.map(people, & &1.email) |> Enum.reject(&is_nil/1),
     Enum.map(people, & &1.phone) |> Enum.reject(&is_nil/1)}
  end

  # --- helpers -----------------------------------------------------------------

  defp empty_result(status) do
    %{people: [], org_contact: %{emails: [], phones: []}, firmographic: nil, llm: %{status: status, cost: nil, error: nil}}
  end

  defp normalize_token(nil), do: ""
  defp normalize_token(t), do: t |> to_string() |> String.downcase() |> String.replace(~r/[^a-z]/, "")

  defp fetch(map, keys) when is_map(map) do
    Enum.find_value(keys, fn k -> Map.get(map, k) end)
  end

  defp fetch(_map, _keys), do: nil

  defp presence(nil), do: nil
  defp presence(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: v)
  defp presence(v), do: v
end

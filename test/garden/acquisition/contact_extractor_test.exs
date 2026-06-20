defmodule GnomeGarden.Acquisition.ContactExtractorTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Acquisition.ContactExtractor

  describe "regex ground-truth" do
    test "pulls emails and phones from text and drops asset/junk emails" do
      text = """
      Reach sales@acme.com or call (714) 555-1212.
      logo@2x.png is not an address. tracking pixel: hit@sentry.io
      """

      result = ContactExtractor.extract(text, use_llm: false)

      assert "sales@acme.com" in result.org_contact.emails
      refute Enum.any?(result.org_contact.emails, &String.contains?(&1, "sentry"))
      refute Enum.any?(result.org_contact.emails, &String.contains?(&1, ".png"))
      assert Enum.any?(result.org_contact.phones, &(String.replace(&1, ~r/\D/, "") == "7145551212"))
      assert result.llm.status == :skipped
    end

    test "ignores short digit runs that are not phone numbers" do
      result = ContactExtractor.extract("Suite 200, zip 92867", use_llm: false)
      assert result.org_contact.phones == []
    end
  end

  describe "structured people guardrail" do
    test "rejects heading-derived and company-named confabulations, keeps real people" do
      structured = %{
        "people" => [
          %{"name" => "Jane Doe", "title" => "VP Operations", "email" => "jane.doe@acme.com"},
          %{"name" => "Acme Foods Leadership", "title" => "Our Company"},
          %{"name" => "Acme Foods", "title" => "Company"},
          %{"name" => "Bob", "title" => "Owner"}
        ],
        "firmographic" => %{"summary" => "A maker of things."}
      }

      result = ContactExtractor.extract("page text", structured: structured, company: "Acme Foods, LLC")

      names = Enum.map(result.people, &{&1.first_name, &1.last_name})
      assert {"Jane", "Doe"} in names
      # "Acme Foods Leadership" (generic word), "Acme Foods" (company), and "Bob"
      # (single token) are all rejected.
      assert length(result.people) == 1
      assert result.firmographic.summary == "A maker of things."
      assert result.llm.status == :ok
    end

    test "associates a regex email with a person by name when the LLM gave none" do
      structured = %{"people" => [%{"name" => "Jane Doe", "title" => "VP"}]}
      text = "Jane Doe, VP. Email jdoe@acme.com or jane.doe@acme.com."

      result = ContactExtractor.extract(text, structured: structured, company: "Acme")

      assert [person] = result.people
      assert person.email in ["jdoe@acme.com", "jane.doe@acme.com"]
      # Claimed email is not double-counted as an org-level contact.
      refute person.email in result.org_contact.emails
    end
  end

  describe "graceful degradation" do
    test "an LLM error still returns regex contact info and marks the failure" do
      failing_llm = fn _text, _opts -> {:error, :token_expired} end
      text = "General inbox: hello@acme.com"

      result = ContactExtractor.extract(text, llm_fun: failing_llm)

      assert result.people == []
      assert "hello@acme.com" in result.org_contact.emails
      assert result.llm.status == :error
      assert result.llm.error == :token_expired
    end

    test "uses an injected llm_fun and stamps source_url on people" do
      llm = fn _text, _opts ->
        {:ok, %{people: [%{name: "Maria Lopez", title: "Buyer"}], firmographic: nil, cost: 0.0}}
      end

      result = ContactExtractor.extract("text", llm_fun: llm, source_url: "https://x.example.com")

      assert [%{first_name: "Maria", last_name: "Lopez", source_url: "https://x.example.com"}] = result.people
    end
  end
end

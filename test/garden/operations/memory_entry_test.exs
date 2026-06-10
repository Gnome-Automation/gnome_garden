defmodule GnomeGarden.Operations.MemoryEntryTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Operations

  describe "archival memory lifecycle" do
    test "proposes, approves, recalls by scope, searches by tag, and marks used" do
      assert {:ok, proposed} =
               Operations.propose_memory_entry(%{
                 title: "Relevant source pattern",
                 content:
                   "Water districts with capital improvement plans often publish recurring bids.",
                 namespace: "procurement",
                 scope: :domain,
                 scope_key: "procurement",
                 memory_type: :pattern,
                 tags: ["water", "source-priority"],
                 source_type: :workflow
               })

      assert proposed.status == :proposed

      assert {:ok, active} = Operations.approve_memory_entry(proposed)
      assert active.status == :active
      assert active.approved_at

      assert {:ok, recalled} = Operations.recall_memory_entries_for_scope(:domain, "procurement")
      assert Enum.map(recalled, & &1.id) == [active.id]

      assert {:ok, tagged} = Operations.search_memory_entries_by_tag("water")
      assert Enum.map(tagged, & &1.id) == [active.id]

      assert {:ok, used} = Operations.mark_memory_entry_used(active)
      assert used.usage_count == 1
      assert used.last_used_at
    end

    test "rejects proposed memory" do
      assert {:ok, proposed} =
               Operations.propose_memory_entry(%{
                 content: "Rejected archival memory.",
                 tags: ["discard"]
               })

      assert {:ok, rejected} =
               Operations.reject_memory_entry(proposed, %{
                 rejection_reason: "Not reliable enough"
               })

      assert rejected.status == :rejected
      assert rejected.rejected_at
      assert rejected.rejection_reason == "Not reliable enough"
    end

    test "expires active memory and removes it from recall" do
      assert {:ok, proposed} =
               Operations.propose_memory_entry(%{
                 content: "Temporary procurement note.",
                 scope: :domain,
                 scope_key: "procurement"
               })

      assert {:ok, active} = Operations.approve_memory_entry(proposed)
      assert {:ok, expired} = Operations.expire_memory_entry(active)

      assert expired.status == :expired
      assert expired.expired_at

      assert {:ok, recalled} = Operations.recall_memory_entries_for_scope(:domain, "procurement")
      assert recalled == []
    end
  end
end

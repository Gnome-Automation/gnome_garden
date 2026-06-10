defmodule GnomeGarden.Operations.MemoryBlockTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Operations

  describe "memory block lifecycle" do
    test "proposes, activates, and reads active memory for a scope" do
      assert {:ok, proposed} =
               Operations.propose_memory_block(%{
                 key: "procurement_strategy",
                 label: "Procurement strategy",
                 content: "Prioritize recurring water infrastructure maintenance.",
                 scope: :domain,
                 scope_key: "procurement",
                 memory_type: :strategy,
                 source_type: :operator
               })

      assert proposed.status == :proposed

      assert {:ok, active} = Operations.activate_memory_block(proposed)
      assert active.status == :active
      assert active.approved_at

      assert {:ok, blocks} =
               Operations.list_active_memory_blocks_for_scope(:domain, "procurement")

      assert Enum.map(blocks, & &1.key) == ["procurement_strategy"]

      assert {:ok, fetched} =
               Operations.get_memory_block_by_key(
                 "procurement_strategy",
                 :domain,
                 "procurement"
               )

      assert fetched.id == active.id
    end

    test "rejects proposed memory and excludes it from active reads" do
      assert {:ok, proposed} =
               Operations.propose_memory_block(%{
                 key: "operator_preference",
                 label: "Operator preference",
                 content: "Use short finding summaries.",
                 scope: :global,
                 scope_key: "global",
                 memory_type: :preference
               })

      assert {:ok, rejected} =
               Operations.reject_memory_block(proposed, %{
                 rejection_reason: "Too broad for global memory"
               })

      assert rejected.status == :rejected
      assert rejected.rejected_at
      assert rejected.rejection_reason == "Too broad for global memory"

      assert {:ok, blocks} = Operations.list_active_memory_blocks_for_scope(:global, "global")
      assert blocks == []
    end

    test "archives active memory" do
      assert {:ok, proposed} =
               Operations.propose_memory_block(%{
                 key: "source_scanning_rules",
                 label: "Source scanning rules",
                 content: "Skip sources marked credential-blocked.",
                 memory_type: :rule
               })

      assert {:ok, active} = Operations.activate_memory_block(proposed)
      assert {:ok, archived} = Operations.archive_memory_block(active)

      assert archived.status == :archived
      assert archived.archived_at
    end
  end
end

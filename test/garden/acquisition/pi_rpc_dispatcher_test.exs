defmodule GnomeGarden.Acquisition.PiRpcDispatcherTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Acquisition.PiRpcDispatcher

  describe "actions/0" do
    test "exposes the Pi sidecar persistence and scan actions" do
      actions = PiRpcDispatcher.actions()

      assert actions["save_bid"] == {GnomeGarden.Procurement, :create_bid}
      assert actions["save_source"] == {GnomeGarden.Procurement, :create_procurement_source}
      assert actions["save_target"] == {GnomeGarden.Commercial, :create_prospect_discovery_record}

      assert actions["save_prospect"] ==
               {GnomeGarden.Commercial, :create_prospect_discovery_record}

      assert actions["save_opportunity"] ==
               {GnomeGarden.Commercial, :create_opportunity_discovery_record}

      assert actions["save_source_config"] == {GnomeGarden.Procurement, :save_source_config}
      assert actions["run_source_scan"] == {GnomeGarden.Procurement, :run_source_scan}
    end
  end
end

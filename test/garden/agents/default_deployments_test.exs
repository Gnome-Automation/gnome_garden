defmodule GnomeGarden.Agents.DefaultDeploymentsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents.DefaultDeployments

  test "default Jido deployments are no longer bootstrapped" do
    assert DefaultDeployments.specs() == []
    assert DefaultDeployments.ensure_defaults() == %{created: [], existing: []}
  end
end

defmodule GnomeGarden.Mercury.PaymentMatcherWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury.PaymentMatcherWorker

  test "perform/1 returns :ok given a transaction_id" do
    job = %Oban.Job{args: %{"transaction_id" => "some-uuid"}}
    assert :ok = PaymentMatcherWorker.perform(job)
  end
end

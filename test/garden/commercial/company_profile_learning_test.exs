defmodule GnomeGarden.Commercial.CompanyProfileLearningTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.CompanyProfileLearning

  test "manual learned excludes can be added and removed per mode" do
    {:ok, result} =
      CompanyProfileLearning.add_learned_excludes(
        company_profile_mode: "industrial_plus_software",
        exclude_terms: ["cctv", "video surveillance"]
      )

    assert result.company_profile_mode == "industrial_plus_software"

    {:ok, snapshot} = CompanyProfileLearning.mode_snapshot(mode: "industrial_plus_software")
    assert snapshot.learned_exclude == ["cctv", "video surveillance"]
    assert hd(snapshot.feedback_history)["feedback_scope"] == "manual"

    {:ok, _result} =
      CompanyProfileLearning.remove_learned_exclude(
        company_profile_mode: "industrial_plus_software",
        exclude_term: "cctv"
      )

    {:ok, updated_snapshot} =
      CompanyProfileLearning.mode_snapshot(mode: "industrial_plus_software")

    assert updated_snapshot.learned_exclude == ["video surveillance"]
    assert hd(updated_snapshot.feedback_history)["feedback_scope"] == "manual_remove"

    {:ok, profile} = Commercial.get_primary_company_profile()

    assert get_in(
             profile.keyword_profiles,
             ["modes", "industrial_plus_software", "learned_exclude"]
           ) == ["video surveillance"]
  end
end

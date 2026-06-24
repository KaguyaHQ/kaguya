defmodule Kaguya.StatsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Stats
  alias Kaguya.Test.UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "build_user_vn_stats/3 — brand-new user (no snapshot)" do
    test "returns a fully-populated stats map with user_id set" do
      user = UserFixtures.insert_user!()

      stats = Stats.build_user_vn_stats(user)

      # Regression: prod 500 was caused by snapshot fallback leaking
      # user_id: nil into the :user_stats parent map, which downstream
      # resolvers (curated_list_progress) fed straight into Ecto.
      assert stats.user_id == user.id
      assert stats.period == nil

      # Every key the stats view expects must be present so downstream
      # consumers can use the map without defensive pattern matching.
      assert is_map(stats.vns_hist)
      assert is_map(stats.read_time_hist)
      assert is_map(stats.mean_score_hist)
      assert is_map(stats.vns_by_release_year_hist)
      assert is_map(stats.read_time_by_release_year_hist)
      assert is_map(stats.mean_score_by_release_year_hist)
      assert stats.most_read_vn_tags == []
      assert stats.highest_rated_vn_tags == []
      assert stats.most_read_producers == []
      assert stats.highest_rated_producers == []
      assert stats.most_read_languages == []
      assert stats.most_liked_vn_review == nil
      assert stats.most_liked_vn_list == nil
      assert stats.updated_at == nil
    end

    test "curated_list_progress is callable with the result's user_id" do
      # Closes the loop: the downstream resolver path that crashed in
      # production must not raise for a snapshot-less user.
      user = UserFixtures.insert_user!()
      stats = Stats.build_user_vn_stats(user)

      assert is_list(Kaguya.Lists.curated_list_progress(stats.user_id))
    end
  end
end

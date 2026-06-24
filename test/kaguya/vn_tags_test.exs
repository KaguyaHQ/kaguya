defmodule Kaguya.VNTagsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Repo
  alias Kaguya.Tags.Tag
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VNTags
  alias Kaguya.VNTags.VNTagVote

  setup do
    :ok = Sandbox.checkout(Repo)

    user = UserFixtures.insert_user!()
    vn = insert_vn!()
    tag1 = insert_tag!("time-travel", "Time Travel")
    tag2 = insert_tag!("romance", "Romance")

    %{user: user, vn: vn, tag1: tag1, tag2: tag2}
  end

  describe "vote_vn_tag activity emission" do
    test "first vote emits a :voted_tag activity with the vote's id as entity_id",
         %{user: user, vn: vn, tag1: tag} do
      assert {:ok, true} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)

      vote = Repo.get_by!(VNTagVote, user_id: user.id, visual_novel_id: vn.id, tag_id: tag.id)

      [activity] = activities_for(user)

      assert activity.action == :voted_tag
      assert activity.entity_type == "tag_vote"
      assert activity.entity_id == vote.id
      assert activity.metadata["tag_id"] == tag.id
      assert activity.metadata["tag_name"] == "Time Travel"
      assert activity.metadata["tag_slug"] == tag.slug
      assert activity.metadata["value"] == 5
      assert activity.metadata["spoiler_level"] == 0
    end

    test "re-voting on the same tag with a different value upserts (same row, fresh metadata)",
         %{user: user, vn: vn, tag1: tag} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)
      [first] = activities_for(user)

      # Tiny delay so the bumped inserted_at is observably different
      Process.sleep(1100)

      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 3)
      [second] = activities_for(user)

      assert second.id == first.id, "expected upsert (same row), got new row"
      assert second.metadata["value"] == 3
      assert DateTime.compare(second.inserted_at, first.inserted_at) == :gt
    end

    test "re-voting with the SAME value and spoiler is a no-op for the activity feed",
         %{user: user, vn: vn, tag1: tag} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)
      [original] = activities_for(user)

      Process.sleep(1100)

      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)
      [after_revote] = activities_for(user)

      assert after_revote.id == original.id

      assert after_revote.inserted_at == original.inserted_at,
             "exact-match re-vote should not bump the activity row"
    end

    test "spoiler-only change still bumps the activity row",
         %{user: user, vn: vn, tag1: tag} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5, spoiler_level: 0)
      [first] = activities_for(user)

      Process.sleep(1100)

      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5, spoiler_level: 2)
      [second] = activities_for(user)

      assert second.id == first.id
      assert second.metadata["spoiler_level"] == 2
      assert DateTime.compare(second.inserted_at, first.inserted_at) == :gt
    end

    test "voting on a different tag of the same VN creates a SEPARATE activity row",
         %{user: user, vn: vn, tag1: tag1, tag2: tag2} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag1.id, 5)
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag2.id, 4)

      activities = activities_for(user)
      assert length(activities) == 2

      tag_ids = activities |> Enum.map(& &1.metadata["tag_id"]) |> Enum.sort()
      assert tag_ids == Enum.sort([tag1.id, tag2.id])
    end

    test "clear_vn_tag_vote deletes the corresponding activity row",
         %{user: user, vn: vn, tag1: tag} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)
      assert [_] = activities_for(user)

      {:ok, _} = VNTags.clear_vn_tag_vote(user.id, vn.id, tag.id)
      assert [] = activities_for(user)
    end

    test "clearing one tag's vote leaves the other tag's activity intact",
         %{user: user, vn: vn, tag1: tag1, tag2: tag2} do
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag1.id, 5)
      {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag2.id, 4)

      {:ok, _} = VNTags.clear_vn_tag_vote(user.id, vn.id, tag1.id)

      [remaining] = activities_for(user)
      assert remaining.metadata["tag_id"] == tag2.id
    end
  end

  describe "tag listing" do
    test "batched VN tag listing includes voted sexual tags", %{user: user, vn: vn} do
      tag = insert_tag!("sexual-content", "Sexual Content", category: :sexual, kind: :sexual)

      assert {:ok, true} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 4)

      rows = VNTags.list_tags_for_vns(user.id, [vn.id]) |> Map.fetch!(vn.id)

      assert Enum.any?(rows, fn row ->
               row.tag.id == tag.id and row.my_vote == 4 and row.kaguya_vote_count == 1
             end)
    end
  end

  # ─── helpers ────────────────────────────────────────────────────────────────

  defp activities_for(user) do
    from(a in UserActivity,
      where: a.user_id == ^user.id and a.action == :voted_tag,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Tag Vote Activity Test #{suffix}",
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end

  defp insert_tag!(slug, name, attrs \\ []) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    %Tag{}
    |> Tag.changeset(
      Keyword.merge(
        [
          name: name,
          slug: "#{slug}-#{suffix}",
          vndb_tag_id: "g-test-#{suffix}",
          kind: :theme,
          category: :content
        ],
        attrs
      )
      |> Map.new()
    )
    |> Repo.insert!()
  end
end

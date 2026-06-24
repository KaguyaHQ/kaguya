defmodule KaguyaWeb.ProfileLive.TagVotesTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Tags.Tag
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VNTags
  alias Kaguya.VNTags.VNTagVote

  describe "GET /@:username/votes/tag" do
    test "renders tag votes with controls and row details" do
      user = UserFixtures.insert_user!(username: "tag_voter")
      vn = insert_vn!("Steins;Gate")
      tag = insert_tag!("time-travel", "Time Travel")

      assert {:ok, true} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 5)

      {:ok, _view, html} = live(build_conn(), "/@tag_voter/votes/tag")

      assert html =~ "Tag votes"
      assert html =~ "1 vote"
      assert html =~ "Filter by bucket"
      assert html =~ "Sort order"
      assert html =~ "Steins;Gate"
      assert html =~ "Time Travel"
      assert html =~ "Main Theme"
      assert html =~ ~s(href="/vn/#{vn.slug}")
      assert html =~ ~s(href="/browse?tags=#{tag.slug}")
      refute html =~ "coming soon"
    end

    test "filters by bucket from the URL" do
      user = UserFixtures.insert_user!(username: "bucket_voter")
      main_vn = insert_vn!("Main Theme VN")
      downvote_vn = insert_vn!("Downvote VN")
      main_tag = insert_tag!("romance", "Romance")
      downvote_tag = insert_tag!("horror", "Horror")

      assert {:ok, true} = VNTags.vote_vn_tag(user.id, main_vn.id, main_tag.id, 5)
      assert {:ok, true} = VNTags.vote_vn_tag(user.id, downvote_vn.id, downvote_tag.id, 0)

      {:ok, _view, html} = live(build_conn(), "/@bucket_voter/votes/tag?bucket=0")

      assert html =~ "2 votes"
      assert html =~ "Downvote VN"
      assert html =~ "Not relevant"
      refute html =~ "Main Theme VN"
    end

    test "sorts oldest first from the URL" do
      user = UserFixtures.insert_user!(username: "sort_voter")
      older_vn = insert_vn!("Older VN")
      newer_vn = insert_vn!("Newer VN")
      older_tag = insert_tag!("older-tag", "Older Tag")
      newer_tag = insert_tag!("newer-tag", "Newer Tag")

      assert {:ok, true} = VNTags.vote_vn_tag(user.id, older_vn.id, older_tag.id, 4)
      set_vote_time!(user.id, older_vn.id, older_tag.id, ~U[2026-01-01 00:00:00Z])

      assert {:ok, true} = VNTags.vote_vn_tag(user.id, newer_vn.id, newer_tag.id, 4)
      set_vote_time!(user.id, newer_vn.id, newer_tag.id, ~U[2026-02-01 00:00:00Z])

      {:ok, _view, html} = live(build_conn(), "/@sort_voter/votes/tag?sort=oldest")

      assert String.contains?(html, "Oldest")
      assert :binary.match(html, "Older VN") < :binary.match(html, "Newer VN")
    end

    test "renders the empty state for users with no tag votes" do
      _user = UserFixtures.insert_user!(username: "no_tag_votes")

      {:ok, _view, html} = live(build_conn(), "/@no_tag_votes/votes/tag")

      assert html =~ "no_tag_votes hasn&#39;t voted on any tags yet."
      assert html =~ "0 votes"
    end
  end

  defp insert_vn!(title) do
    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: title,
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end

  defp insert_tag!(slug, name) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    %Tag{}
    |> Tag.changeset(%{
      name: "#{name} #{suffix}",
      slug: "#{slug}-#{suffix}",
      vndb_tag_id: "g-live-#{suffix}",
      kind: :theme,
      category: :content
    })
    |> Repo.insert!()
  end

  defp set_vote_time!(user_id, vn_id, tag_id, inserted_at) do
    from(v in VNTagVote,
      where: v.user_id == ^user_id and v.visual_novel_id == ^vn_id and v.tag_id == ^tag_id
    )
    |> Repo.update_all(set: [inserted_at: inserted_at])
  end
end

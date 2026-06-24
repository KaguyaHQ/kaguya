defmodule KaguyaWeb.VNLive.PageDataCacheTest do
  @moduledoc """
  Phase 2 of the VN-page performance plan: the public core is cached in
  `:vn_page_cache`, viewer-independently, and dropped on writes that change it.
  See docs/migrations/nextjs-liveview/plans/vn-page-performance-plan.md.
  """
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Shelves
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VisualNovels.VNTag
  alias Kaguya.VisualNovels.VNPageCache
  alias Kaguya.VNTags
  alias Kaguya.Test.UserFixtures
  alias KaguyaWeb.VNLive.PageData

  setup do
    Cachex.clear(:vn_page_cache)
    :ok
  end

  defp insert_vn!(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    %VisualNovel{}
    |> VisualNovel.changeset(
      Map.merge(
        %{
          title: "Cache VN #{suffix}",
          slug: "cache-vn-#{suffix}",
          description: "A" <> String.duplicate(" cache visual novel description", 3)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  test "serves the public core from cache until it is invalidated" do
    user = UserFixtures.insert_user!()
    vn = insert_vn!()

    {:ok, _vn, page1} = PageData.get_public_page(vn.slug)
    assert page1.vn.readers_count == 0

    # Mutate the underlying data *outside* a PageData write path — nothing
    # invalidates the cache.
    {:ok, _} = Shelves.set_reading_status(user.id, vn.id, %{status: :currently_reading})

    {:ok, _vn, page2} = PageData.get_public_page(vn.slug)
    # Still the pre-mutation snapshot — proves the core was served from cache.
    assert page2.vn.readers_count == 0

    # Explicit invalidation forces a fresh assembly.
    VNPageCache.invalidate(vn.id)
    {:ok, _vn, page3} = PageData.get_public_page(vn.slug)
    assert page3.vn.readers_count == 1
  end

  test "a viewer write through PageData invalidates the cached core" do
    user = UserFixtures.insert_user!()
    vn = insert_vn!()

    {:ok, _vn, page1} = PageData.get_public_page(vn.slug)
    assert page1.vn.readers_count == 0

    # The real write path must drop the cache itself.
    {:ok, _bundle} = PageData.set_reading_status(vn.slug, user, "CURRENTLY_READING")

    {:ok, _vn, page2} = PageData.get_public_page(vn.slug)
    assert page2.vn.readers_count == 1
  end

  test "the cached core is viewer-independent; the viewer's tag votes ride the bundle" do
    user = UserFixtures.insert_user!()
    vn = insert_vn!()

    tag =
      %Tag{}
      |> Tag.changeset(%{name: "Comedy", slug: "comedy", category: :content, kind: :genre})
      |> Repo.insert!()

    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      vndb_vote_count: 10,
      vndb_avg_score: 2.0,
      relevance_score: 0.8,
      spoiler_level: :none
    })
    |> Repo.insert!()

    {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 4)

    # The cached public core carries NO per-user vote highlight…
    {:ok, _vn, page} = PageData.get_public_page(vn.slug, user)
    core_tag = Enum.find(page.vn.tags, &(&1.id == tag.id))
    assert core_tag, "expected the voted tag to appear in the public core"
    assert core_tag.my_vote == nil

    # …it rides the viewer bundle instead, to overlay after first paint.
    {:ok, bundle} = PageData.viewer_bundle_for_vn(vn, user)
    assert bundle.my_votes.tags[tag.id] == 4
  end

  test "a tag vote returns vote-less tags plus the viewer's votes (single overlay mechanism)" do
    user = UserFixtures.insert_user!()
    vn = insert_vn!()

    tag =
      %Tag{}
      |> Tag.changeset(%{name: "Drama", slug: "drama", category: :content, kind: :genre})
      |> Repo.insert!()

    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      vndb_vote_count: 10,
      vndb_avg_score: 2.0,
      relevance_score: 0.8,
      spoiler_level: :none
    })
    |> Repo.insert!()

    # The mutation path mirrors first paint: the tag list itself stays
    # viewer-independent (no `my_vote` baked in) and the viewer's votes come
    # back separately for `Data.assign_tags/3` to overlay.
    assert {:ok, {tags, votes}} = PageData.vote_tag(vn.slug, user, tag.id, 4)

    voted = Enum.find(tags, &(&1.id == tag.id))
    assert voted, "expected the voted tag in the refreshed list"
    assert voted.my_vote == nil
    assert votes[tag.id] == 4

    # Clearing the only vote returns an empty votes map — overlaying it then
    # leaves every tag vote-less.
    assert {:ok, {_tags, cleared_votes}} = PageData.clear_tag_vote(vn.slug, user, tag.id)
    assert cleared_votes == %{}
  end

  test "the normalized VN is viewer-independent even on the non-cached similar page" do
    user = UserFixtures.insert_user!()
    vn = insert_vn!()

    tag =
      %Tag{}
      |> Tag.changeset(%{name: "Mystery", slug: "mystery", category: :content, kind: :genre})
      |> Repo.insert!()

    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      vndb_vote_count: 10,
      vndb_avg_score: 2.0,
      relevance_score: 0.8,
      spoiler_level: :none
    })
    |> Repo.insert!()

    {:ok, _} = VNTags.vote_vn_tag(user.id, vn.id, tag.id, 4)

    # `get_similar_page/3` (uncached, real viewer) used to *bake* `my_vote` into
    # the VN's tags. `normalize_vn` is now viewer-independent by construction:
    # tags carry no `my_vote`, and the dead `:viewer_id` field is gone. The
    # similar page never renders tag votes, so nothing is lost.
    {:ok, %{vn: vn_payload}} = PageData.get_similar_page(vn.slug, user)

    voted = Enum.find(vn_payload.tags, &(&1.id == tag.id))
    assert voted, "expected the voted tag to appear on the similar page's VN"
    assert voted.my_vote == nil
    refute Map.has_key?(vn_payload, :viewer_id)
  end

  test "a hidden VN cached for a moderator never leaks to a regular viewer" do
    mod =
      UserFixtures.insert_user!()
      |> Ecto.Changeset.change(role: :moderator)
      |> Repo.update!()

    # `hidden_at` isn't a casted field, so set it directly after insert.
    vn =
      insert_vn!()
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

    # The moderator sees the hidden VN and warms its cache entry…
    assert {:ok, _vn, _page} = PageData.get_public_page(vn.slug, mod)

    # …but a regular viewer still gets a miss at the lookup stage, never the
    # moderator's privileged cache entry.
    assert {:error, :not_found} = PageData.get_public_page(vn.slug, nil)
  end
end

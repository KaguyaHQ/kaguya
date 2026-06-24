defmodule Kaguya.ContentScoreTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.ContentScore
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Repo
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.{Image, VisualNovel, VNTag}

  setup do
    :ok = Sandbox.checkout(Repo)
    %{vn: insert_vn!()}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # compute_visual_novel/1 — per-check coverage
  # ──────────────────────────────────────────────────────────────────────────

  describe "compute_visual_novel/1" do
    test "fresh VN passes only has_title", %{vn: vn} do
      result = ContentScore.compute_visual_novel(vn)

      assert result.passed == 1
      assert result.total == 6
      assert result.score == 17
      assert result.breakdown["has_title"] == true
      assert result.breakdown["has_cover"] == false
      assert result.breakdown["has_description"] == false
      assert result.breakdown["has_producer"] == false
      assert result.breakdown["has_two_genre_tags"] == false
      assert result.breakdown["has_backdrop"] == false
    end

    test "has_cover passes when primary_image_id is set", %{vn: vn} do
      image = insert_image!(vn)
      vn = vn |> Ecto.Changeset.change(primary_image_id: image.id) |> Repo.update!()
      assert ContentScore.compute_visual_novel(vn).breakdown["has_cover"] == true
    end

    test "has_description passes only when ≥200 chars after trim", %{vn: vn} do
      short = String.duplicate("a", 199)
      vn_short = vn |> Ecto.Changeset.change(description: short) |> Repo.update!()
      assert ContentScore.compute_visual_novel(vn_short).breakdown["has_description"] == false

      long = String.duplicate("a", 200)
      vn_long = vn |> Ecto.Changeset.change(description: long) |> Repo.update!()
      assert ContentScore.compute_visual_novel(vn_long).breakdown["has_description"] == true

      # Whitespace-padded short string still fails — trims before length check.
      padded = "  " <> String.duplicate("a", 199) <> "  "
      vn_pad = vn |> Ecto.Changeset.change(description: padded) |> Repo.update!()
      assert ContentScore.compute_visual_novel(vn_pad).breakdown["has_description"] == false
    end

    test "has_producer passes when at least one VNProducer exists", %{vn: vn} do
      assert ContentScore.compute_visual_novel(vn).breakdown["has_producer"] == false
      attach_producer!(vn)
      assert ContentScore.compute_visual_novel(vn).breakdown["has_producer"] == true
    end

    test "has_two_genre_tags requires 2+ tags with kind=:genre — non-genre tags don't count",
         %{vn: vn} do
      attach_tag!(vn, insert_tag!(:theme))
      attach_tag!(vn, insert_tag!(:cast))
      assert ContentScore.compute_visual_novel(vn).breakdown["has_two_genre_tags"] == false

      attach_tag!(vn, insert_tag!(:genre))
      assert ContentScore.compute_visual_novel(vn).breakdown["has_two_genre_tags"] == false

      attach_tag!(vn, insert_tag!(:genre))
      assert ContentScore.compute_visual_novel(vn).breakdown["has_two_genre_tags"] == true
    end

    test "has_backdrop passes via featured_screenshot_id OR any screenshot row", %{vn: vn} do
      # Featured-screenshot path
      featured = insert_screenshot!(vn)

      vn_featured =
        vn
        |> Ecto.Changeset.change(featured_screenshot_id: featured.id)
        |> Repo.update!()

      assert ContentScore.compute_visual_novel(vn_featured).breakdown["has_backdrop"] == true

      # Reset both the FK and the underlying row so the next assertion sees
      # zero screenshots — otherwise the "any screenshot" check leaks true.
      vn = vn |> Ecto.Changeset.change(featured_screenshot_id: nil) |> Repo.update!()
      Repo.delete!(featured)
      assert ContentScore.compute_visual_novel(vn).breakdown["has_backdrop"] == false

      insert_screenshot!(vn)
      assert ContentScore.compute_visual_novel(vn).breakdown["has_backdrop"] == true
    end

    test "all six checks passing → 100", %{vn: vn} do
      image = insert_image!(vn)
      featured = insert_screenshot!(vn)

      vn =
        vn
        |> Ecto.Changeset.change(
          primary_image_id: image.id,
          description: String.duplicate("a", 220),
          featured_screenshot_id: featured.id
        )
        |> Repo.update!()

      attach_producer!(vn)
      attach_tag!(vn, insert_tag!(:genre))
      attach_tag!(vn, insert_tag!(:genre))

      result = ContentScore.compute_visual_novel(vn)
      assert result.score == 100
      assert result.passed == 6
      assert Enum.all?(result.breakdown, fn {_k, v} -> v end)
    end

    test "compute_visual_novel/1 with nonexistent UUID returns nil" do
      assert ContentScore.compute_visual_novel(Ecto.UUID.generate()) == nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # recompute_visual_novel/1 — persistence
  # ──────────────────────────────────────────────────────────────────────────

  describe "recompute_visual_novel/1" do
    test "persists score + breakdown with string-keyed jsonb", %{vn: vn} do
      assert {:ok, :scored} = ContentScore.recompute_visual_novel(vn.id)

      reloaded = Repo.get(VisualNovel, vn.id)
      assert reloaded.content_score == 17

      assert reloaded.content_score_breakdown == %{
               "has_cover" => false,
               "has_title" => true,
               "has_description" => false,
               "has_producer" => false,
               "has_two_genre_tags" => false,
               "has_backdrop" => false
             }

      assert %DateTime{} = reloaded.content_score_updated_at
    end

    test "is idempotent — second call produces the same row", %{vn: vn} do
      assert {:ok, :scored} = ContentScore.recompute_visual_novel(vn.id)
      first = Repo.get(VisualNovel, vn.id).content_score_breakdown

      assert {:ok, :scored} = ContentScore.recompute_visual_novel(vn.id)
      second = Repo.get(VisualNovel, vn.id).content_score_breakdown

      assert first == second
    end

    test "returns {:ok, :not_found} when the VN doesn't exist" do
      assert {:ok, :not_found} = ContentScore.recompute_visual_novel(Ecto.UUID.generate())
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # top_contributors context query — :vndb_sync exclusion
  # ──────────────────────────────────────────────────────────────────────────

  describe "top_contributors_for_visual_novel/2" do
    test "excludes :vndb_sync and :system source revisions", %{vn: vn} do
      user = insert_user!()

      # User edits — should count
      insert_change!(vn.id, :user, user.id, 3)
      # Bot/system edits — should NOT count
      insert_change!(vn.id, :vndb_sync, nil, 50)
      insert_change!(vn.id, :system, nil, 7)

      contributors = ContentScore.top_contributors_for_visual_novel(vn.id, 4)

      assert [%{user: returned, edit_count: 3}] = contributors
      assert returned.id == user.id
    end

    test "ranks contributors by edit count descending", %{vn: vn} do
      a = insert_user!()
      b = insert_user!()
      c = insert_user!()

      insert_change!(vn.id, :user, a.id, 1)
      insert_change!(vn.id, :user, b.id, 5)
      insert_change!(vn.id, :user, c.id, 3)

      contributors = ContentScore.top_contributors_for_visual_novel(vn.id, 4)

      assert Enum.map(contributors, & &1.edit_count) == [5, 3, 1]
      assert Enum.map(contributors, & &1.user.id) == [b.id, c.id, a.id]
    end

    test "limit caps the returned list", %{vn: vn} do
      Enum.each(1..6, fn _ ->
        insert_change!(vn.id, :user, insert_user!().id, 1)
      end)

      contributors = ContentScore.top_contributors_for_visual_novel(vn.id, 4)
      assert length(contributors) == 4
    end
  end

  # ─── helpers ────────────────────────────────────────────────────────────────

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "ContentScore Test #{suffix}",
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end

  defp insert_tag!(kind) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    %Tag{
      name: "Tag #{suffix}",
      slug: "tag-#{suffix}",
      vndb_tag_id: "g-#{suffix}",
      kind: kind,
      category: :content
    }
    |> Repo.insert!()
  end

  defp insert_producer!() do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    {:ok, p} =
      %Producer{name: "Producer #{suffix}", slug: "producer-#{suffix}"}
      |> Ecto.Changeset.change()
      |> Repo.insert()

    p
  end

  defp attach_producer!(vn) do
    producer = insert_producer!()

    %VNProducer{}
    |> VNProducer.changeset(%{
      visual_novel_id: vn.id,
      producer_id: producer.id,
      role: "developer"
    })
    |> Repo.insert!()
  end

  defp attach_tag!(vn, tag) do
    %VNTag{visual_novel_id: vn.id, tag_id: tag.id}
    |> Repo.insert!()
  end

  defp insert_screenshot!(vn) do
    %Screenshot{id: Ecto.UUID.generate(), visual_novel_id: vn.id}
    |> Repo.insert!()
  end

  defp insert_image!(vn) do
    %Image{id: Ecto.UUID.generate(), visual_novel_id: vn.id}
    |> Repo.insert!()
  end

  defp insert_user!() do
    Kaguya.Test.UserFixtures.insert_user!()
  end

  # Inserts `count` Change rows for the VN. Bypasses the public API so we
  # can control source / user_id / revision_number directly.
  defp insert_change!(vn_id, source, user_id, count) do
    import Ecto.Query

    next_revision =
      (Repo.aggregate(
         from(c in Kaguya.Revisions.Change, where: c.entity_id == ^vn_id),
         :max,
         :revision_number
       ) || 0) + 1

    for offset <- 0..(count - 1) do
      Kaguya.Revisions.Change.changeset(%Kaguya.Revisions.Change{}, %{
        entity_type: :visual_novel,
        entity_id: vn_id,
        revision_number: next_revision + offset,
        action: :edit,
        changed_fields: ["title"],
        summary: "test edit",
        source: source,
        user_id: user_id
      })
      |> Repo.insert!()
    end
  end
end

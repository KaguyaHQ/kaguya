defmodule Kaguya.Revisions.EnrichmentTest do
  @moduledoc """
  Characterization tests for the reference + image URL enrichment that
  `Revisions.diff_revisions/1` and `Revisions.batch_load_diffs/2` apply on
  top of the raw diff. The diff payload exposed to LiveView and controller
  callers carries enriched fields (related_vn_title, character_name,
  producer_name, primary_image_id_url, sub-collection :url) — the upcoming
  refactor must preserve every one of them.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{Image, VNTitle, VisualNovel}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # Reference enrichment — VN titles on relations
  # ──────────────────────────────────────────────────────────────────────

  describe "enrich_relations on diff entries" do
    test "added relation gets :related_vn_title injected from the live VN row" do
      user = insert_user!()
      vn = insert_vn!(title: "Main story")
      insert_initial_title!(vn, "en", "Main story")
      related = insert_vn!(title: "Related side story")
      insert_initial_title!(related, "en", "Related side story")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "sequel"}]},
          "Add relation",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      relations = field_diff(diff, "relations")

      assert [added] = relations.added
      assert added.related_vn_id == related.id
      assert added.related_vn_title == "Related side story"
    end

    test "changed-row entries (same related_vn_id, different relation_type) " <>
           "carry related_vn_title on both :old and :new" do
      user = insert_user!()
      vn = insert_vn!(title: "Main")
      insert_initial_title!(vn, "en", "Main")
      related = insert_vn!(title: "Other VN")
      insert_initial_title!(related, "en", "Other VN")

      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "sequel"}]},
          "Initial",
          user
        )

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "prequel"}]},
          "Flip",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      relations = field_diff(diff, "relations")

      assert [%{old: old, new: new}] = relations.changed
      assert old.related_vn_title == "Other VN"
      assert new.related_vn_title == "Other VN"
    end

    test "snapshot relations are also enriched, not just the diff entries" do
      user = insert_user!()
      vn = insert_vn!(title: "Main")
      insert_initial_title!(vn, "en", "Main")
      related = insert_vn!(title: "Snapshot related")
      insert_initial_title!(related, "en", "Snapshot related")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "sequel"}]},
          "Add relation",
          user
        )

      {:ok, %{current: current}} = Revisions.diff_revisions(change.id)

      assert [rel] = current.relations
      assert rel.related_vn_title == "Snapshot related"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Image URL enrichment — main hist scalar fields
  # ──────────────────────────────────────────────────────────────────────

  describe "enrich_images on the main hist row" do
    test "VN snapshot.hist gains :primary_image_id_url when primary_image_id is set" do
      user = insert_user!()
      vn = insert_vn!(title: "Cover VN")
      insert_initial_title!(vn, "en", "Cover VN")
      cover = insert_cover!(vn)
      Repo.update!(Ecto.Changeset.change(vn, primary_image_id: cover.id))

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "force a new revision"},
          "Force rev",
          user
        )

      {:ok, %{current: current}} = Revisions.diff_revisions(change.id)

      assert current.hist.primary_image_id == cover.id
      assert is_binary(current.hist.primary_image_id_url)
      assert String.contains?(current.hist.primary_image_id_url, cover.id)
      assert String.contains?(current.hist.primary_image_id_url, "256w")
    end

    test "snapshot.hist gains nothing when primary_image_id is nil" do
      user = insert_user!()
      vn = insert_vn!(title: "No-cover VN")
      insert_initial_title!(vn, "en", "No-cover VN")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "rev"},
          "Force rev",
          user
        )

      {:ok, %{current: current}} = Revisions.diff_revisions(change.id)

      assert current.hist.primary_image_id == nil
      refute Map.get(current.hist, :primary_image_id_url)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Image URL enrichment — sub-collection rows
  # ──────────────────────────────────────────────────────────────────────

  describe "enrich_images on covers/screenshots/images collections" do
    test "covers.added rows in a diff gain :url" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      # First edit: establishes r1 (synthetic create from pre-edit state, no
      # covers) and r2 (post-edit, still no covers — only description changed).
      {:ok, _r2} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "first rev"},
          "First",
          user
        )

      # Insert a cover directly between revisions, then force another edit so
      # r3's snapshot picks up the new cover via get_for_edit.
      cover = insert_cover!(vn)

      {:ok, r3} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "second rev"},
          "Second",
          user
        )

      {:ok, %{diff: diff, current: current}} = Revisions.diff_revisions(r3.id)
      covers_diff = field_diff(diff, "covers")

      assert [added] = covers_diff.added
      assert added.cover_id == cover.id
      assert is_binary(added.url)
      assert String.contains?(added.url, cover.id)
      assert String.contains?(added.url, "256w")

      # Snapshot enrichment fires too: current.covers carries :url on every row
      assert [snap_cover] = current.covers
      assert snap_cover.url == added.url
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # batch_load_diffs/2 — enrichment parity with diff_revisions/1
  # ──────────────────────────────────────────────────────────────────────

  describe "batch_load_diffs" do
    test "enriches relations across multiple changes in a single batch" do
      user = insert_user!()
      vn1 = insert_vn!(title: "VN one")
      insert_initial_title!(vn1, "en", "VN one")
      related1 = insert_vn!(title: "Related to one")
      insert_initial_title!(related1, "en", "Related to one")

      vn2 = insert_vn!(title: "VN two")
      insert_initial_title!(vn2, "en", "VN two")
      related2 = insert_vn!(title: "Related to two")
      insert_initial_title!(related2, "en", "Related to two")

      {:ok, change1} =
        Revisions.submit_edit(
          :visual_novel,
          vn1.id,
          %{relations: [%{related_vn_id: related1.id, relation_type: "sequel"}]},
          "Edit 1",
          user
        )

      {:ok, change2} =
        Revisions.submit_edit(
          :visual_novel,
          vn2.id,
          %{relations: [%{related_vn_id: related2.id, relation_type: "prequel"}]},
          "Edit 2",
          user
        )

      result = Revisions.batch_load_diffs(:noop_key, [change1.id, change2.id])

      assert [added1] = field_diff(result[change1.id].diff, "relations").added
      assert added1.related_vn_title == "Related to one"

      assert [added2] = field_diff(result[change2.id].diff, "relations").added
      assert added2.related_vn_title == "Related to two"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Fixtures
  # ──────────────────────────────────────────────────────────────────────

  defp suffix, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

  defp insert_user!(attrs \\ %{}) do
    s = suffix()

    base = %{
      id: Ecto.UUID.generate(),
      username: "enrich_user_#{s}",
      display_name: "Enrich User #{s}",
      email: "enrich_#{s}@test.local"
    }

    %User{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:id, :username, :display_name, :email, :role])
    |> Repo.insert!()
  end

  defp insert_vn!(attrs \\ []) do
    s = suffix()
    attrs = Enum.into(attrs, %{})

    Repo.insert!(%VisualNovel{
      title: Map.get(attrs, :title, "Enrich VN #{s}"),
      slug: Map.get(attrs, :slug, "enrich-vn-#{String.downcase(s)}"),
      aliases: [],
      title_category: :vn,
      description: Map.get(attrs, :description),
      original_language: Map.get(attrs, :original_language, "en"),
      primary_image_id: Map.get(attrs, :primary_image_id)
    })
  end

  defp insert_initial_title!(vn, lang, title) do
    Repo.insert!(%VNTitle{
      visual_novel_id: vn.id,
      lang: lang,
      title: title,
      official: true
    })
  end

  defp insert_cover!(vn) do
    Repo.insert!(%Image{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      is_image_nsfw: false
    })
  end

  defp field_diff(diff, field_name) do
    Enum.find(diff, fn entry -> entry.field == field_name end)
  end
end

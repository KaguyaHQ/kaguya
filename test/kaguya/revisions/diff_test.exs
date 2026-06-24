defmodule Kaguya.Revisions.DiffTest do
  @moduledoc """
  Characterization tests for the revision diff engine. Exercises the diff
  shape returned by `Revisions.diff_revisions/1` so the upcoming Diff module
  extraction stays behaviour-preserving.

  The diff engine is currently a private function in `Kaguya.Revisions`,
  reached through `diff_revisions/1`. Tests build two consecutive revisions
  via the real `submit_edit/6` write path (which writes both the live row
  and the `_hist` snapshot in one txn), then assert on the diff shape.

  Conventions follow `test/kaguya/visual_novels/merge_test.exs`:
    - `async: false` with manual `Sandbox.checkout`
    - Inline fixture helpers with random-suffix names for uniqueness
    - `Repo.insert!` through changesets where possible
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # Scalar fields
  # ──────────────────────────────────────────────────────────────────────

  describe "scalar field diffs" do
    test "scalar string change shows up as a single field entry" do
      user = insert_user!()
      vn = insert_vn!(title: "Original", description: "v1 description")
      insert_initial_title!(vn, "en", "Original")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "v2 description"},
          "Edit description",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)

      desc_diff = field_diff(diff, "description")
      assert desc_diff.old == "v1 description"
      assert desc_diff.new == "v2 description"
      refute Map.has_key?(desc_diff, :added)
    end

    test "list-valued scalar field (aliases) diffs as added/removed sets" do
      user = insert_user!()
      vn = insert_vn!(aliases: ["alpha", "beta"])
      insert_initial_title!(vn, "en", vn.title)

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{aliases: ["beta", "gamma"]},
          "Swap aliases",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)

      aliases_diff = field_diff(diff, "aliases")
      assert aliases_diff.added == ["gamma"]
      assert aliases_diff.removed == ["alpha"]
    end

    test "no-op edit on a single field yields an empty scalar diff for that field" do
      user = insert_user!()
      vn = insert_vn!(title: "Stable", description: "unchanged")
      insert_initial_title!(vn, "en", "Stable")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{aliases: ["alpha"]},
          "Add alias only",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)

      # description didn't change, must not show in the diff
      assert field_diff(diff, "description") == nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Sub-entity identity-aware diffs
  # ──────────────────────────────────────────────────────────────────────

  describe "titles collection (natural key: [:lang])" do
    test "adding a title appears as :added, not as a 'changed' row" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", "English title")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{
            titles: [
              %{lang: "en", title: "English title", official: true},
              %{lang: "ja", title: "日本語タイトル", official: true}
            ]
          },
          "Add Japanese title",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      titles = field_diff(diff, "titles")

      assert length(titles.added) == 1
      assert hd(titles.added).lang == "ja"
      assert titles.removed == []
      assert titles.changed == []
    end

    test "editing a title's text (same lang) appears as :changed, not removed+added" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", "Old text")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{titles: [%{lang: "en", title: "New text", official: true}]},
          "Rename English title",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      titles = field_diff(diff, "titles")

      assert titles.added == []
      assert titles.removed == []
      assert [%{old: old_row, new: new_row, fields: fields}] = titles.changed
      assert old_row.title == "Old text"
      assert new_row.title == "New text"
      assert Enum.any?(fields, fn f -> f.field == "title" end)
    end

    test "removing a title appears as :removed" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", "EN")
      insert_initial_title!(vn, "ja", "JA")

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{titles: [%{lang: "en", title: "EN", official: true}]},
          "Drop Japanese title",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      titles = field_diff(diff, "titles")

      assert titles.added == []
      assert [%{lang: "ja"}] = titles.removed
      assert titles.changed == []
    end
  end

  describe "relations collection (natural key: [:related_vn_id])" do
    test "changing relation_type on the same related_vn_id is a :changed row" do
      user = insert_user!()
      vn = insert_vn!(title: "Main")
      insert_initial_title!(vn, "en", "Main")
      related = insert_vn!(title: "Related")
      insert_initial_title!(related, "en", "Related")

      # r2: add a 'sequel' relation
      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "sequel"}]},
          "Add sequel relation",
          user
        )

      # r3: change relation_type to 'prequel' — same related_vn_id
      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: related.id, relation_type: "prequel"}]},
          "Flip to prequel",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      relations = field_diff(diff, "relations")

      assert relations.added == []
      assert relations.removed == []

      assert [%{old: old, new: new, fields: fields}] = relations.changed
      assert old.relation_type == "sequel"
      assert new.relation_type == "prequel"
      assert old.related_vn_id == related.id
      assert Enum.any?(fields, fn f -> f.field == "relation_type" end)
      # The natural-key field itself must NOT appear in the per-row field diff
      refute Enum.any?(fields, fn f -> f.field == "related_vn_id" end)
    end

    test "replacing one related_vn_id with another produces removed+added, not changed" do
      user = insert_user!()
      vn = insert_vn!(title: "Main")
      insert_initial_title!(vn, "en", "Main")
      r1 = insert_vn!(title: "R1")
      insert_initial_title!(r1, "en", "R1")
      r2 = insert_vn!(title: "R2")
      insert_initial_title!(r2, "en", "R2")

      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: r1.id, relation_type: "sequel"}]},
          "Initial relation",
          user
        )

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{relations: [%{related_vn_id: r2.id, relation_type: "sequel"}]},
          "Replace related VN",
          user
        )

      {:ok, %{diff: diff}} = Revisions.diff_revisions(change.id)
      relations = field_diff(diff, "relations")

      assert [%{related_vn_id: added_id}] = relations.added
      assert added_id == r2.id
      assert [%{related_vn_id: removed_id}] = relations.removed
      assert removed_id == r1.id
      assert relations.changed == []
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # First revision behaviour
  # ──────────────────────────────────────────────────────────────────────

  describe "first revision" do
    test "diff for the synthesized r1 (no previous) returns an empty diff list" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      # First user edit triggers ensure_initial_revision which inserts a
      # synthetic r1 capturing the pre-edit state. The user's edit becomes r2.
      {:ok, _r2} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "First user edit"},
          "First edit",
          user
        )

      [r1, _r2] =
        Repo.all(
          from(c in Revisions.Change,
            where: c.entity_type == :visual_novel and c.entity_id == ^vn.id,
            order_by: [asc: c.revision_number]
          )
        )

      {:ok, %{diff: diff, previous_change: previous}} = Revisions.diff_revisions(r1.id)
      assert previous == nil
      assert diff == []
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
      username: "diff_user_#{s}",
      display_name: "Diff User #{s}",
      email: "diff_#{s}@test.local"
    }

    %User{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:id, :username, :display_name, :email, :role])
    |> Repo.insert!()
  end

  defp insert_vn!(attrs \\ []) do
    s = suffix()
    attrs = Enum.into(attrs, %{})

    base = %{
      title: Map.get(attrs, :title, "Diff VN #{s}"),
      slug: Map.get(attrs, :slug, "diff-vn-#{String.downcase(s)}"),
      aliases: Map.get(attrs, :aliases, []),
      title_category: :vn,
      description: Map.get(attrs, :description),
      original_language: Map.get(attrs, :original_language, "en")
    }

    Repo.insert!(struct(VisualNovel, base))
  end

  # Inserts a VNTitle row directly so the VN has at least one title before
  # the first submit_edit. ensure_initial_revision will snapshot this state
  # into r1 when the user's first edit lands as r2.
  defp insert_initial_title!(vn, lang, title) do
    Repo.insert!(%Kaguya.VisualNovels.VNTitle{
      visual_novel_id: vn.id,
      lang: lang,
      title: title,
      official: true
    })
  end

  defp field_diff(diff, field_name) do
    Enum.find(diff, fn entry -> entry.field == field_name end)
  end
end

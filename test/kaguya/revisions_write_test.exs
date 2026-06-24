defmodule Kaguya.RevisionsWriteTest do
  @moduledoc """
  Characterization tests for the write path: `submit_edit/6`, `revert_to_revision/3`,
  `create_entity/4`, `record_mod_action/5`, `bulk_create_system_changes/2`.

  Locks down the security boundary (mod-only field stripping), the audit
  semantics (action classification on hide/unhide/lock/unlock), the
  optimistic-concurrency guard (`base_revision` conflict), the locked
  return shape of `create_entity/4` (LiveView/controller callers depend on
  it), and the bulk-write revision-number sequencing that the recent
  `reduce_while` cleanup tightened.

  All tests funnel through the public API — no private function calls — so
  the same tests carry forward as the write engine gets extracted into
  `Kaguya.Revisions.Writer` and the entry points become thin wrappers.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.Change
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{VNTitle, VisualNovel}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # Optimistic-concurrency: base_revision conflict
  # ──────────────────────────────────────────────────────────────────────

  describe "submit_edit/6 base_revision check" do
    test "returns :edit_conflict when base_revision is stale" do
      user = insert_user!()
      vn = insert_vn!(title: "Conflict VN")
      insert_initial_title!(vn, "en", "Conflict VN")

      # First edit lands and lifts the revision number to 2 (r1 synthetic + r2).
      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "First"},
          "First edit",
          user
        )

      # Caller still thinks the head is r1; submit must refuse.
      assert {:error, :edit_conflict} =
               Revisions.submit_edit(
                 :visual_novel,
                 vn.id,
                 %{description: "Conflicting"},
                 "Stale edit",
                 user,
                 base_revision: 1
               )
    end

    test "accepts the edit when base_revision matches the current head" do
      user = insert_user!()
      vn = insert_vn!(title: "Match VN")
      insert_initial_title!(vn, "en", "Match VN")

      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "First"},
          "First edit",
          user
        )

      current_rev = Revisions.latest_revision_number(:visual_novel, vn.id)

      assert {:ok, %Change{}} =
               Revisions.submit_edit(
                 :visual_novel,
                 vn.id,
                 %{description: "Second"},
                 "Second edit",
                 user,
                 base_revision: current_rev
               )
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Security: mod-only field stripping
  # ──────────────────────────────────────────────────────────────────────

  describe "submit_edit/6 mod-only field protection" do
    test "non-mod cannot escalate by forging :hidden_at in changes" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      # Description change is real and would succeed on its own — the
      # injected :hidden_at must be silently stripped, leaving the live VN
      # row's hidden_at untouched.
      {:ok, _change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "user edit", hidden_at: DateTime.utc_now()},
          "Sneaky hide",
          user
        )

      reloaded = Repo.get!(VisualNovel, vn.id)
      assert reloaded.hidden_at == nil
      assert reloaded.description == "user edit"
    end

    test "non-mod cannot escalate by forging :is_locked in changes" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      {:ok, _change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "user edit", is_locked: true},
          "Sneaky lock",
          user
        )

      reloaded = Repo.get!(VisualNovel, vn.id)
      assert reloaded.is_locked == false
    end

    test "non-mod edit on a hidden entity is rejected" do
      mod = insert_user!(role: :moderator)
      regular = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      {:ok, _} = Revisions.record_mod_action(:visual_novel, vn.id, :hide, "hide", mod)

      assert {:error, "Entry is hidden"} =
               Revisions.submit_edit(
                 :visual_novel,
                 vn.id,
                 %{description: "should fail"},
                 "blocked",
                 regular
               )
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Audit: action classification on mod actions
  # ──────────────────────────────────────────────────────────────────────

  describe "record_mod_action/5 action classification" do
    test "hide → :hide, then unhide → :unhide" do
      mod = insert_user!(role: :moderator)
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      {:ok, hide_change} = Revisions.record_mod_action(:visual_novel, vn.id, :hide, "hide", mod)
      assert hide_change.action == :hide

      {:ok, unhide_change} =
        Revisions.record_mod_action(:visual_novel, vn.id, :unhide, "unhide", mod)

      assert unhide_change.action == :unhide
    end

    test "lock → :lock, then unlock → :unlock" do
      mod = insert_user!(role: :moderator)
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      {:ok, lock_change} = Revisions.record_mod_action(:visual_novel, vn.id, :lock, "lock", mod)
      assert lock_change.action == :lock

      reloaded_locked = Repo.get!(VisualNovel, vn.id)
      assert reloaded_locked.is_locked == true

      {:ok, unlock_change} =
        Revisions.record_mod_action(:visual_novel, vn.id, :unlock, "unlock", mod)

      assert unlock_change.action == :unlock

      reloaded_unlocked = Repo.get!(VisualNovel, vn.id)
      assert reloaded_unlocked.is_locked == false
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Side effects: edit_count
  # ──────────────────────────────────────────────────────────────────────

  describe "side effects" do
    test "successful submit_edit increments the user's edit_count" do
      user = insert_user!()
      vn = insert_vn!()
      insert_initial_title!(vn, "en", vn.title)

      starting_count = Repo.get!(User, user.id).edit_count || 0

      {:ok, _} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "Counted edit"},
          "edit",
          user
        )

      reloaded = Repo.get!(User, user.id)
      assert reloaded.edit_count == starting_count + 1
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Revert round-trip
  # ──────────────────────────────────────────────────────────────────────

  describe "revert_to_revision/3" do
    test "reverting to an earlier revision restores the snapshot fields" do
      user = insert_user!()
      vn = insert_vn!(description: "original")
      insert_initial_title!(vn, "en", vn.title)

      # r1 is synthesized with description="original". r2 changes it.
      {:ok, r2} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{description: "changed"},
          "Change",
          user
        )

      assert Repo.get!(VisualNovel, vn.id).description == "changed"

      [r1, ^r2] =
        Repo.all(
          from(c in Change,
            where: c.entity_type == :visual_novel and c.entity_id == ^vn.id,
            order_by: [asc: c.revision_number]
          )
        )

      assert {:ok, %Change{action: :revert}} =
               Revisions.revert_to_revision(r1.id, "Revert to original", user)

      assert Repo.get!(VisualNovel, vn.id).description == "original"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # create_entity locked return shape — DO NOT BREAK
  # ──────────────────────────────────────────────────────────────────────

  describe "create_entity/4" do
    test "returns {:ok, %{change: %Change{}, entity: entity_struct}} (locked shape)" do
      user = insert_user!()
      s = suffix()

      attrs = %{
        title: "Created VN #{s}",
        slug: "created-vn-#{String.downcase(s)}",
        original_language: "en",
        titles: [%{lang: "en", title: "Created VN #{s}", official: true}]
      }

      assert {:ok, %{change: %Change{action: :create, revision_number: 1}, entity: entity}} =
               Revisions.create_entity(:visual_novel, attrs, "Create test", user)

      assert %VisualNovel{} = entity
      assert entity.title == "Created VN #{s}"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Bulk write — revision-number sequencing
  # ──────────────────────────────────────────────────────────────────────

  describe "bulk_create_system_changes/2" do
    test "writes one change row per entry with revision_number = max + 1" do
      vn1 = insert_vn!()
      vn2 = insert_vn!()

      entries = [
        %{entity_type: :visual_novel, entity_id: vn1.id, summary: "import", changed_fields: []},
        %{entity_type: :visual_novel, entity_id: vn2.id, summary: "import", changed_fields: []}
      ]

      assert {:ok, 2} = Revisions.bulk_create_system_changes(entries)

      assert Revisions.revision_count(:visual_novel, vn1.id) == 1
      assert Revisions.revision_count(:visual_novel, vn2.id) == 1
    end

    test "two entries for the same entity get sequential revision numbers" do
      vn = insert_vn!()

      entries = [
        %{entity_type: :visual_novel, entity_id: vn.id, summary: "first", changed_fields: []},
        %{entity_type: :visual_novel, entity_id: vn.id, summary: "second", changed_fields: []}
      ]

      assert {:ok, 2} = Revisions.bulk_create_system_changes(entries)

      [r1, r2] =
        Repo.all(
          from(c in Change,
            where: c.entity_type == :visual_novel and c.entity_id == ^vn.id,
            order_by: [asc: c.revision_number]
          )
        )

      assert r1.revision_number == 1
      assert r2.revision_number == 2
      assert r1.summary == "first"
      assert r2.summary == "second"
    end

    test "empty list short-circuits to {:ok, 0}" do
      assert {:ok, 0} = Revisions.bulk_create_system_changes([])
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Fixtures
  # ──────────────────────────────────────────────────────────────────────

  defp suffix, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

  defp insert_user!(attrs \\ []) do
    s = suffix()
    attrs = Enum.into(attrs, %{})

    base = %{
      id: Ecto.UUID.generate(),
      username: "rw_user_#{s}",
      display_name: "RW User #{s}",
      email: "rw_#{s}@test.local"
    }

    %User{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:id, :username, :display_name, :email, :role])
    |> Repo.insert!()
  end

  defp insert_vn!(attrs \\ []) do
    s = suffix()
    attrs = Enum.into(attrs, %{})

    Repo.insert!(%VisualNovel{
      title: Map.get(attrs, :title, "RW VN #{s}"),
      slug: Map.get(attrs, :slug, "rw-vn-#{String.downcase(s)}"),
      aliases: [],
      title_category: :vn,
      description: Map.get(attrs, :description),
      original_language: Map.get(attrs, :original_language, "en")
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
end

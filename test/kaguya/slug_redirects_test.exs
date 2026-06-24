defmodule Kaguya.SlugRedirectsTest do
  # async: false — we use :auto sandbox so writes commit to the real test
  # DB, matching the pattern in revisions_test.exs. No FK dependencies, so
  # cleanup is just deleting redirects we created.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.SlugRedirects
  alias Kaguya.SlugRedirects.SlugRedirect

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    :ok
  end

  setup do
    # Tag every row this test creates with a unique scope_id so concurrent
    # test runs don't collide and cleanup is precise.
    test_tag = UUIDv7.generate()

    on_exit(fn ->
      Repo.delete_all(
        from r in SlugRedirect,
          where: r.target_id == ^test_tag or r.scope_id == ^test_tag
      )

      # Also clean any old_slug we used in this test — covers the global
      # (scope_id IS NULL) rows we record under random old_slugs.
      :ok
    end)

    %{test_tag: test_tag}
  end

  describe "record/4 + resolve/3 (global scope)" do
    test "records and resolves a vn redirect", %{test_tag: target_id} do
      old_slug = "old-vn-#{System.unique_integer([:positive])}"

      assert {:ok, _} = SlugRedirects.record(:vn, old_slug, target_id)
      assert SlugRedirects.resolve(:vn, old_slug) == target_id

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug == ^old_slug)
    end

    test "returns nil for unknown slug" do
      assert SlugRedirects.resolve(:vn, "definitely-not-a-real-slug-#{System.unique_integer()}") ==
               nil
    end

    test "is idempotent on re-record (last writer wins)", %{test_tag: target_id} do
      old_slug = "rerecord-#{System.unique_integer([:positive])}"
      other_target = UUIDv7.generate()

      assert {:ok, _} = SlugRedirects.record(:vn, old_slug, target_id)
      assert SlugRedirects.resolve(:vn, old_slug) == target_id

      assert {:ok, _} = SlugRedirects.record(:vn, old_slug, other_target, reason: :merge)
      assert SlugRedirects.resolve(:vn, old_slug) == other_target

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug == ^old_slug)
    end

    test "different entity types with same slug don't collide", %{test_tag: vn_target} do
      slug = "shared-#{System.unique_integer([:positive])}"
      character_target = UUIDv7.generate()

      assert {:ok, _} = SlugRedirects.record(:vn, slug, vn_target)
      assert {:ok, _} = SlugRedirects.record(:character, slug, character_target)

      assert SlugRedirects.resolve(:vn, slug) == vn_target
      assert SlugRedirects.resolve(:character, slug) == character_target

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug == ^slug)
    end
  end

  describe "record/4 + resolve/3 (user scope)" do
    test "records and resolves a list redirect", %{test_tag: scope_id} do
      target_id = UUIDv7.generate()
      old_slug = "my-list-#{System.unique_integer([:positive])}"

      assert {:ok, _} = SlugRedirects.record(:list, old_slug, target_id, scope_id: scope_id)
      assert SlugRedirects.resolve(:list, old_slug, scope_id: scope_id) == target_id
    end

    test "same slug under different scopes resolves independently", %{test_tag: alice_id} do
      bob_id = UUIDv7.generate()
      slug = "favorites-#{System.unique_integer([:positive])}"
      alice_list = UUIDv7.generate()
      bob_list = UUIDv7.generate()

      assert {:ok, _} = SlugRedirects.record(:list, slug, alice_list, scope_id: alice_id)
      assert {:ok, _} = SlugRedirects.record(:list, slug, bob_list, scope_id: bob_id)

      assert SlugRedirects.resolve(:list, slug, scope_id: alice_id) == alice_list
      assert SlugRedirects.resolve(:list, slug, scope_id: bob_id) == bob_list

      # No scope passed → looks for global (scope_id IS NULL) only, no match.
      assert SlugRedirects.resolve(:list, slug) == nil

      Repo.delete_all(from r in SlugRedirect, where: r.scope_id == ^bob_id)
    end

    test "scoped types reject NULL scope_id", %{test_tag: target_id} do
      assert {:error, changeset} =
               SlugRedirects.record(:list, "x", target_id)

      assert {"is required for list redirects", _} = changeset.errors[:scope_id]
    end

    test "global types reject non-NULL scope_id", %{test_tag: scope_id} do
      target_id = UUIDv7.generate()

      assert {:error, changeset} =
               SlugRedirects.record(:vn, "x", target_id, scope_id: scope_id)

      assert {"must be NULL for vn redirects", _} = changeset.errors[:scope_id]
    end
  end

  describe "resolve_many/3" do
    test "returns map of slug → target for known slugs", %{test_tag: target_id} do
      slug_a = "a-#{System.unique_integer([:positive])}"
      slug_b = "b-#{System.unique_integer([:positive])}"
      slug_unknown = "missing-#{System.unique_integer([:positive])}"

      target_b = UUIDv7.generate()

      {:ok, _} = SlugRedirects.record(:vn, slug_a, target_id)
      {:ok, _} = SlugRedirects.record(:vn, slug_b, target_b)

      result = SlugRedirects.resolve_many(:vn, [slug_a, slug_b, slug_unknown])

      assert result == %{slug_a => target_id, slug_b => target_b}

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug in ^[slug_a, slug_b])
    end

    test "empty list short-circuits" do
      assert SlugRedirects.resolve_many(:vn, []) == %{}
    end
  end

  describe "record_many/1" do
    test "bulk-inserts rows", %{test_tag: target_id} do
      slug_a = "bulk-a-#{System.unique_integer([:positive])}"
      slug_b = "bulk-b-#{System.unique_integer([:positive])}"

      entries = [
        %{entity_type: :vn, old_slug: slug_a, target_id: target_id},
        %{entity_type: :vn, old_slug: slug_b, target_id: target_id, reason: :merge}
      ]

      assert {2, _} = SlugRedirects.record_many(entries)
      assert SlugRedirects.resolve(:vn, slug_a) == target_id
      assert SlugRedirects.resolve(:vn, slug_b) == target_id

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug in ^[slug_a, slug_b])
    end

    test "is idempotent on conflict", %{test_tag: target_id} do
      slug = "bulk-conflict-#{System.unique_integer([:positive])}"
      other_target = UUIDv7.generate()

      assert {1, _} =
               SlugRedirects.record_many([
                 %{entity_type: :vn, old_slug: slug, target_id: target_id}
               ])

      assert {1, _} =
               SlugRedirects.record_many([
                 %{entity_type: :vn, old_slug: slug, target_id: other_target, reason: :merge}
               ])

      assert SlugRedirects.resolve(:vn, slug) == other_target

      Repo.delete_all(from r in SlugRedirect, where: r.old_slug == ^slug)
    end

    test "empty list short-circuits" do
      assert SlugRedirects.record_many([]) == {0, nil}
    end
  end

  describe "purge_for_target/2" do
    test "deletes only the matching entity_type/target rows", %{test_tag: target_id} do
      keep_target = UUIDv7.generate()
      slug_purge = "purge-#{System.unique_integer([:positive])}"
      slug_keep = "keep-#{System.unique_integer([:positive])}"

      {:ok, _} = SlugRedirects.record(:vn, slug_purge, target_id)
      {:ok, _} = SlugRedirects.record(:vn, slug_keep, keep_target)

      assert {1, _} = SlugRedirects.purge_for_target(:vn, target_id)

      assert SlugRedirects.resolve(:vn, slug_purge) == nil
      assert SlugRedirects.resolve(:vn, slug_keep) == keep_target

      Repo.delete_all(from r in SlugRedirect, where: r.target_id == ^keep_target)
    end
  end

  describe "purge_for_scope/1" do
    test "deletes every scoped redirect under the scope", %{test_tag: scope_id} do
      list_target = UUIDv7.generate()
      shelf_target = UUIDv7.generate()

      {:ok, _} =
        SlugRedirects.record(:list, "list-#{System.unique_integer([:positive])}", list_target,
          scope_id: scope_id
        )

      {:ok, _} =
        SlugRedirects.record(:shelf, "shelf-#{System.unique_integer([:positive])}", shelf_target,
          scope_id: scope_id
        )

      assert {2, _} = SlugRedirects.purge_for_scope(scope_id)
    end
  end

  describe "list_for_target/2" do
    test "returns every historical slug for an entity, newest first", %{test_tag: target_id} do
      a = "first-#{System.unique_integer([:positive])}"
      b = "second-#{System.unique_integer([:positive])}"

      {:ok, _} = SlugRedirects.record(:vn, a, target_id)
      Process.sleep(1100)
      {:ok, _} = SlugRedirects.record(:vn, b, target_id)

      assert [%{old_slug: ^b}, %{old_slug: ^a}] = SlugRedirects.list_for_target(:vn, target_id)
    end
  end
end

defmodule Kaguya.VisualNovels.RenameTest do
  @moduledoc """
  Tests for `Kaguya.VisualNovels.Rename` — single-VN slug/title rename
  with `slug_redirects` integration.

  Pattern mirrors `merge_test.exs`: `async: false`, manual sandbox
  checkout per test, inline fixtures with random suffixes for uniqueness.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.SlugRedirects
  alias Kaguya.VisualNovels.{Rename, VisualNovel}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "rename_vn/3" do
    test "slug-only rename: redirect recorded, current VN resolves under new slug" do
      vn = insert_vn!()
      old_slug = vn.slug
      new_slug = "renamed-#{System.unique_integer([:positive])}"

      {:ok, updated} = Rename.rename_vn(vn.id, %{slug: new_slug})

      assert updated.slug == new_slug
      assert Repo.get!(VisualNovel, vn.id).slug == new_slug

      # Old slug resolves to the same VN via slug_redirects.
      assert SlugRedirects.resolve(:vn, old_slug) == vn.id
      assert Kaguya.VisualNovels.get_visual_novel_by_slug(old_slug).id == vn.id

      # New slug resolves directly.
      assert Kaguya.VisualNovels.get_visual_novel_by_slug(new_slug).id == vn.id
    end

    test "title-only rename: no slug_redirects row written" do
      vn = insert_vn!()
      new_title = "Updated Title #{System.unique_integer([:positive])}"

      {:ok, updated} = Rename.rename_vn(vn.id, %{title: new_title})

      assert updated.title == new_title
      assert updated.slug == vn.slug

      # No redirect written for title-only changes.
      assert SlugRedirects.resolve(:vn, vn.slug) == nil
    end

    test "both slug and title in one call" do
      vn = insert_vn!()
      old_slug = vn.slug
      new_slug = "both-renamed-#{System.unique_integer([:positive])}"
      new_title = "Both Renamed"

      {:ok, updated} = Rename.rename_vn(vn.id, %{slug: new_slug, title: new_title})

      assert updated.slug == new_slug
      assert updated.title == new_title
      assert SlugRedirects.resolve(:vn, old_slug) == vn.id
    end

    test "no-op rename returns {:error, :no_changes} when neither slug nor title differ" do
      vn = insert_vn!()

      assert {:error, :no_changes} = Rename.rename_vn(vn.id, %{slug: vn.slug, title: vn.title})
      # And the same with empty attrs.
      assert {:error, :no_changes} = Rename.rename_vn(vn.id, %{})
    end

    test "non-existent vn_id returns {:error, :not_found}" do
      assert {:error, :not_found} =
               Rename.rename_vn(Ecto.UUID.generate(), %{slug: "anything"})
    end

    test "slug collision with another live VN returns {:error, %Ecto.Changeset{}}" do
      vn_a = insert_vn!()
      vn_b = insert_vn!()

      assert {:error, %Ecto.Changeset{}} = Rename.rename_vn(vn_b.id, %{slug: vn_a.slug})
      # vn_b stayed at its original slug; no DB damage.
      assert Repo.get!(VisualNovel, vn_b.id).slug == vn_b.slug
    end

    test "writes a :edit revision on the canonical with the right changed_fields" do
      vn = insert_vn!()
      new_slug = "rev-#{System.unique_integer([:positive])}"

      {:ok, _} = Rename.rename_vn(vn.id, %{slug: new_slug, title: "New Title"})

      [change] =
        Repo.all(
          from c in Change,
            where: c.entity_id == ^vn.id and c.action == :edit,
            order_by: [desc: c.inserted_at],
            limit: 1
        )

      assert "slug" in change.changed_fields
      assert "title" in change.changed_fields
      assert change.source == :system
    end

    test "reason option flows through to the slug_redirects row" do
      vn = insert_vn!()
      old_slug = vn.slug
      new_slug = "manual-#{System.unique_integer([:positive])}"

      {:ok, _} = Rename.rename_vn(vn.id, %{slug: new_slug}, reason: :manual)

      [%{reason: reason}] =
        Repo.all(
          from r in SlugRedirects.SlugRedirect,
            where: r.entity_type == :vn and r.old_slug == ^old_slug,
            select: %{reason: r.reason}
        )

      assert reason == :manual
    end

    test "renaming twice chains the redirects: both old slugs resolve" do
      vn = insert_vn!()
      slug_v0 = vn.slug
      slug_v1 = "v1-#{System.unique_integer([:positive])}"
      slug_v2 = "v2-#{System.unique_integer([:positive])}"

      {:ok, _} = Rename.rename_vn(vn.id, %{slug: slug_v1})
      {:ok, _} = Rename.rename_vn(vn.id, %{slug: slug_v2})

      assert Kaguya.VisualNovels.get_visual_novel_by_slug(slug_v0).id == vn.id
      assert Kaguya.VisualNovels.get_visual_novel_by_slug(slug_v1).id == vn.id
      assert Kaguya.VisualNovels.get_visual_novel_by_slug(slug_v2).id == vn.id
    end
  end

  describe "rename_by_slug/3" do
    test "looks up by current slug and renames" do
      vn = insert_vn!()
      old_slug = vn.slug
      new_slug = "by-slug-#{System.unique_integer([:positive])}"

      {:ok, updated} = Rename.rename_by_slug(old_slug, %{slug: new_slug})

      assert updated.id == vn.id
      assert updated.slug == new_slug
    end

    test "returns :not_found for an unknown slug" do
      assert {:error, :not_found} =
               Rename.rename_by_slug(
                 "definitely-not-here-#{System.unique_integer([:positive])}",
                 %{
                   title: "x"
                 }
               )
    end
  end

  describe "rename_many/2" do
    test "applies each entry; reports successes and errors per-id" do
      [vn_a, vn_b, vn_c] = [insert_vn!(), insert_vn!(), insert_vn!()]
      collide_with = insert_vn!()

      result =
        Rename.rename_many([
          {vn_a.id, %{title: "A renamed"}},
          {vn_b.id, %{slug: collide_with.slug}},
          {vn_c.id, %{slug: "ok-#{System.unique_integer([:positive])}"}}
        ])

      assert vn_a.id in result.ok
      assert vn_c.id in result.ok
      assert [{bad_id, %Ecto.Changeset{}}] = result.errors
      assert bad_id == vn_b.id
    end
  end

  # ────────────────────────────────────────────────────────────────────

  defp insert_vn!(attrs \\ %{}) do
    s = "#{System.unique_integer([:positive])}"
    base = %{title: "Test VN #{s}", original_language: "en"}

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    vn
  end
end

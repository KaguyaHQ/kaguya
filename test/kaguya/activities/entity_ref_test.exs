defmodule Kaguya.Activities.EntityRefTest do
  # Exercises the entity_ref virtual field across all six supported
  # entity_types: tag_vote, quote (Phase 1+2), and visual_novel /
  # character / producer / release (Phase 3 — revisions). Phase 3 emission
  # tests via the full Revisions.submit_edit flow are blocked on the pending
  # is_avn-on-vn_hist migration; these tests exercise the resolver directly
  # by inserting synthetic activity rows so we can validate the dereference
  # logic without touching vn_hist.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Activities
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    user = UserFixtures.insert_user!()
    %{user: user}
  end

  describe "entity_ref for visual_novel revision activities" do
    test "dereferences via metadata.target_entity_id", %{user: user} do
      vn = insert_vn!()
      change_id = Ecto.UUID.generate()

      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :edited_entity,
        entity_type: "visual_novel",
        entity_id: change_id,
        metadata: %{
          "target_entity_id" => vn.id,
          "revision_number" => 5,
          "summary" => "fixed typo",
          "changed_fields" => ["title"]
        }
      })

      activity = load_activity(user)

      assert activity.entity_ref != nil
      assert activity.entity_ref.entity_type == "visual_novel"
      assert activity.entity_ref.entity_id == change_id
      assert activity.entity_ref.name == vn.title
      assert activity.entity_ref.slug == vn.slug
      assert activity.entity_ref.is_hidden == false
    end

    # Note: a separate test for `entity_ref.is_hidden == true` would never
    # round-trip through `list_activities_for_user/2` because the server-side
    # filter (see `exclude_hidden_content_activities/2`) drops hidden-target
    # activities before the resolver ever runs. The `is_hidden` field on
    # entity_ref remains as defense-in-depth for any direct callers that
    # bypass the filter (preview tools, mod consoles, etc.).

    test "missing target_entity_id leaves entity_ref nil (no crash)", %{user: user} do
      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :edited_entity,
        entity_type: "visual_novel",
        entity_id: Ecto.UUID.generate(),
        metadata: %{}
      })

      activity = load_activity(user)
      assert activity.entity_ref == nil
    end
  end

  describe "entity_ref dispatch by entity_type" do
    test "unknown entity_type leaves entity_ref nil", %{user: user} do
      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :liked_review,
        entity_type: "review",
        entity_id: Ecto.UUID.generate(),
        metadata: %{}
      })

      activity = load_activity(user)
      assert activity.entity_ref == nil
    end
  end

  describe "server-side hidden filter" do
    test "edited_entity activity is filtered when target VN is hidden", %{user: user} do
      vn = insert_vn!()
      hide_entity!(VisualNovel, vn.id)

      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :edited_entity,
        entity_type: "visual_novel",
        entity_id: Ecto.UUID.generate(),
        metadata: %{"target_entity_id" => vn.id, "summary" => "secret edit"}
      })

      assert {:ok, %{items: []}} = Activities.list_activities_for_user(user.id, limit: 5)
    end

    test "voted_tag activity is filtered when parent VN is hidden", %{user: user} do
      vn = insert_vn!()
      hide_entity!(VisualNovel, vn.id)

      vote =
        Repo.insert!(%Kaguya.VNTags.VNTagVote{
          user_id: user.id,
          visual_novel_id: vn.id,
          tag_id: insert_tag!().id,
          value: 5,
          spoiler_level: 0
        })

      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :voted_tag,
        entity_type: "tag_vote",
        entity_id: vote.id,
        metadata: %{}
      })

      assert {:ok, %{items: []}} = Activities.list_activities_for_user(user.id, limit: 5)
    end

    test "added_quote activity is filtered when parent VN is hidden", %{user: user} do
      vn = insert_vn!()
      hide_entity!(VisualNovel, vn.id)

      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "Hidden VN, hidden quote.",
          created_by: user.id
        })

      assert {:ok, %{items: []}} = Activities.list_activities_for_user(user.id, limit: 5)
      # Sanity: the activity row exists, just isn't surfaced.
      assert Repo.get_by(UserActivity, action: :added_quote, entity_id: q.id) != nil
    end

    test "edited_entity for a release is filtered when its parent VN is hidden",
         %{user: user} do
      vn = insert_vn!()

      release =
        Repo.insert!(%Kaguya.Releases.Release{
          visual_novel_id: vn.id,
          title: "A Release",
          original_language: "en"
        })

      hide_entity!(VisualNovel, vn.id)

      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :edited_entity,
        entity_type: "release",
        entity_id: Ecto.UUID.generate(),
        metadata: %{"target_entity_id" => release.id}
      })

      assert {:ok, %{items: []}} = Activities.list_activities_for_user(user.id, limit: 5)
    end

    test "non-hidden activities pass through", %{user: user} do
      vn = insert_vn!()

      Repo.insert!(%UserActivity{
        user_id: user.id,
        action: :edited_entity,
        entity_type: "visual_novel",
        entity_id: Ecto.UUID.generate(),
        metadata: %{"target_entity_id" => vn.id}
      })

      assert {:ok, %{items: [_one]}} = Activities.list_activities_for_user(user.id, limit: 5)
    end
  end

  defp hide_entity!(schema, id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.update_all(from(e in schema, where: e.id == ^id), set: [hidden_at: now])
  end

  defp insert_tag!() do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    Repo.insert!(%Kaguya.Tags.Tag{
      name: "Tag #{suffix}",
      slug: "tag-#{suffix}",
      vndb_tag_id: "g-test-#{suffix}",
      kind: :theme,
      category: :content
    })
  end

  defp load_activity(user) do
    {:ok, conn} = Activities.list_activities_for_user(user.id, limit: 5)
    %{items: [activity]} = Activities.preload_associations(conn)
    activity
  end

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Revision Activity Test #{suffix}",
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end
end

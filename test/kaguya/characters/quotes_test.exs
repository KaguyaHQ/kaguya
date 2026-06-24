defmodule Kaguya.VisualNovels.QuotesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Activities
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)

    author = UserFixtures.insert_user!()
    liker = UserFixtures.insert_user!()
    vn = insert_vn!()

    %{author: author, liker: liker, vn: vn}
  end

  describe "create_quote activity emission" do
    test "emits :added_quote with vn + character + preview metadata",
         %{author: author, vn: vn} do
      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "I am mad scientist. It's so cool, sonuvabitch.",
          created_by: author.id
        })

      [activity] = activities_for(author, :added_quote)

      assert activity.entity_type == "quote"
      assert activity.entity_id == q.id
      assert activity.metadata["vn_id"] == vn.id
      assert activity.metadata["quote_text_preview"] =~ "mad scientist"
    end

    test "creating two distinct quotes emits two distinct activity rows",
         %{author: author, vn: vn} do
      {:ok, _} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "First quote, gentle and quiet.",
          created_by: author.id
        })

      {:ok, _} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "Second quote — louder and prouder.",
          created_by: author.id
        })

      assert length(activities_for(author, :added_quote)) == 2
    end
  end

  describe "like_quote / unlike_quote activity emission" do
    test "first like emits :liked_quote, unlike removes it",
         %{author: author, liker: liker, vn: vn} do
      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "Some line of dialogue here.",
          created_by: author.id
        })

      {:ok, _} = Kaguya.Characters.Quotes.like_quote(q.id, liker.id)

      [activity] = activities_for(liker, :liked_quote)
      assert activity.entity_id == q.id
      assert activity.metadata["quote_author_id"] == author.id
      assert activity.metadata["vn_id"] == vn.id

      {:ok, _} = Kaguya.Characters.Quotes.unlike_quote(q.id, liker.id)
      assert [] = activities_for(liker, :liked_quote)
    end

    test "re-liking the same quote (no-op) does not duplicate the activity",
         %{author: author, liker: liker, vn: vn} do
      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "Repeatable line.",
          created_by: author.id
        })

      {:ok, _} = Kaguya.Characters.Quotes.like_quote(q.id, liker.id)
      {:ok, _} = Kaguya.Characters.Quotes.like_quote(q.id, liker.id)

      assert [_only_one] = activities_for(liker, :liked_quote)
    end

    test "self-likes are allowed and emit activity (matches :liked_review behavior)",
         %{author: author, vn: vn} do
      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "I'll like my own quote, thanks.",
          created_by: author.id
        })

      {:ok, _} = Kaguya.Characters.Quotes.like_quote(q.id, author.id)
      assert [_self_like] = activities_for(author, :liked_quote)
    end
  end

  describe "entity_ref resolution for quote" do
    test "preload_associations populates entity_ref pointing at the parent VN",
         %{author: author, vn: vn} do
      {:ok, q} =
        Kaguya.Characters.Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "Quote that should resolve to its VN.",
          created_by: author.id
        })

      {:ok, conn} = Activities.list_activities_for_user(author.id, limit: 5)
      %{items: [activity]} = Activities.preload_associations(conn)

      assert activity.entity_id == q.id
      assert activity.entity_ref != nil
      assert activity.entity_ref.entity_type == "quote"
      assert activity.entity_ref.name == vn.title
      assert activity.entity_ref.slug == vn.slug
      assert activity.entity_ref.is_hidden == false
    end
  end

  # ─── helpers ────────────────────────────────────────────────────────────────

  defp activities_for(user, action) do
    from(a in UserActivity,
      where: a.user_id == ^user.id and a.action == ^action,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Quote Activity Test #{suffix}",
        original_language: "en"
      })
      |> Repo.insert()

    vn
  end
end

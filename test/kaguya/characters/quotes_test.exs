defmodule Kaguya.VisualNovels.QuotesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Activities
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Characters.{Character, Quote, Quotes, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
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

  describe "update_quote" do
    setup %{author: author, vn: vn} do
      {:ok, quote} =
        Quotes.create_quote(%{
          visual_novel_id: vn.id,
          quote: "The original line.",
          created_by: author.id
        })

      %{quote: quote}
    end

    test "author can edit text, attribute and remove a character", ctx do
      character = insert_character!(ctx.vn)

      assert {:ok, updated} =
               Quotes.update_quote(ctx.quote.id, ctx.author.id, %{
                 "quote" => "The corrected line.",
                 "character_id" => character.id
               })

      assert updated.quote == "The corrected line."
      assert updated.character.id == character.id
      assert {:ok, updated} = Quotes.update_quote(updated.id, ctx.author.id, %{character_id: nil})
      assert is_nil(updated.character)
    end

    test "another user, an anonymous viewer and malformed IDs cannot edit", ctx do
      assert {:error, "Quote not found"} =
               Quotes.update_quote(ctx.quote.id, ctx.liker.id, %{quote: "Changed."})

      assert {:error, "Quote not found"} =
               Quotes.update_quote(ctx.quote.id, nil, %{quote: "Changed."})

      assert {:error, "Quote not found"} =
               Quotes.update_quote("1", ctx.author.id, %{quote: "Changed."})

      assert Repo.get!(Quote, ctx.quote.id).quote == ctx.quote.quote
    end

    test "character must belong to the quote's VN and invalid input returns an error", ctx do
      character = insert_character!(insert_vn!())

      assert {:error, "Character does not appear in this visual novel"} =
               Quotes.update_quote(ctx.quote.id, ctx.author.id, %{character_id: character.id})

      assert {:error, %Ecto.Changeset{}} =
               Quotes.update_quote(ctx.quote.id, ctx.author.id, %{character_id: "1"})

      assert {:error, %Ecto.Changeset{}} =
               Quotes.update_quote(ctx.quote.id, ctx.author.id, %{quote: " "})
    end

    test "ignores server-owned fields and preserves reactions", ctx do
      {:ok, _} = Quotes.like_quote(ctx.quote.id, ctx.author.id)
      {:ok, _} = Kaguya.Users.add_favorite_quote(ctx.author.id, ctx.quote.id)

      assert {:ok, updated} =
               Quotes.update_quote(ctx.quote.id, ctx.author.id, %{
                 quote: "The corrected line.",
                 created_by: ctx.liker.id,
                 visual_novel_id: insert_vn!().id,
                 score: 99,
                 vndb_id: "forged"
               })

      assert updated.created_by == ctx.author.id
      assert updated.visual_novel_id == ctx.vn.id
      assert updated.score == 0
      assert is_nil(updated.vndb_id)
      assert updated.likes_count == 1
      assert updated.liked_by_me
      assert updated.favorited_by_me

      [activity] = activities_for(ctx.author, :liked_quote)
      assert activity.metadata["quote_text_preview"] == updated.quote
      assert activity.metadata["quote_author_id"] == ctx.author.id
      assert activity.metadata["vn_id"] == ctx.vn.id
      assert length(activities_for(ctx.author, :added_quote)) == 1
    end

    test "page update stays within the current VN and returns author info", ctx do
      alias KaguyaWeb.VNLive.PageData
      other_vn = insert_vn!()

      assert {:error, "Quote not found"} =
               PageData.update_quote(other_vn.slug, ctx.author, ctx.quote.id, "Changed.", nil)

      assert {:ok, quote} =
               PageData.update_quote(ctx.vn.slug, ctx.author, ctx.quote.id, " Changed. ", "")

      assert quote.quote == "Changed."
      assert quote.created_by == ctx.author.id
    end
  end

  defp insert_character!(vn) do
    character = Repo.insert!(Character.changeset(%Character{}, %{name: "Quote character"}))

    Repo.insert!(
      VNCharacter.changeset(%VNCharacter{}, %{
        visual_novel_id: vn.id,
        character_id: character.id,
        role: :main
      })
    )

    character
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

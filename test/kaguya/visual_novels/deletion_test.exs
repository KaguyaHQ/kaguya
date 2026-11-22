defmodule Kaguya.VisualNovels.DeletionTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.{RatingDistribution, Repo}
  alias Kaguya.Lists.{List, ListItem}
  alias Kaguya.Reviews.{Rating, Review, ReviewComment}
  alias Kaguya.Shelves.{Shelf, ShelfItem}
  alias Kaguya.Social.Notification
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{BannedVndbId, Deletion, VisualNovel}

  setup do
    previous = Application.fetch_env(:kaguya, :browse_cache_warm_async)
    Application.put_env(:kaguya, :browse_cache_warm_async, false)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:kaguya, :browse_cache_warm_async, value)
        :error -> Application.delete_env(:kaguya, :browse_cache_warm_async)
      end
    end)

    :ok
  end

  for skip_blocklist <- [false, true] do
    @skip_blocklist skip_blocklist
    test "deletion updates dependent counts with skip_blocklist=#{skip_blocklist}" do
      [deleted, kept] =
        for n <- 1..2 do
          Repo.insert!(%VisualNovel{
            title: "Deletion VN #{n}",
            slug: "deletion-vn-#{n}",
            vndb_id: "v8994000#{n}"
          })
        end

      dist =
        RatingDistribution.default_dist()
        |> RatingDistribution.adjust_bucket(4.0, 1)
        |> RatingDistribution.adjust_bucket(2.0, 1)

      user =
        Kaguya.Test.UserFixtures.insert_user!()
        |> Ecto.Changeset.change(%{
          favorite_visual_novels: [deleted.id, kept.id],
          vn_ratings_dist: dist,
          vn_ratings_count: 2,
          vn_average_rating: 3.0,
          vn_reviews_count: 2
        })
        |> Repo.update!()

      for {vn, rating} <- [{deleted, 4.0}, {kept, 2.0}] do
        Repo.insert!(%Rating{user_id: user.id, visual_novel_id: vn.id, rating: rating})
      end

      [deleted_review, _kept_review] =
        for vn <- [deleted, kept] do
          Repo.insert!(%Review{user_id: user.id, visual_novel_id: vn.id, content: "Review"})
        end

      comment =
        Repo.insert!(%ReviewComment{
          user_id: user.id,
          vn_review_id: deleted_review.id,
          content: "A deleted review comment"
        })

      list =
        Repo.insert!(%List{
          name: "Ranked deletion list",
          slug: "ranked-deletion-list",
          user_id: user.id,
          is_ranked: true,
          vns_count: 2
        })

      shelf =
        Repo.insert!(%Shelf{
          name: "Deletion shelf",
          slug: "deletion-shelf",
          user_id: user.id,
          vns_count: 2
        })

      for {vn, position} <- [{deleted, 1}, {kept, 3}] do
        Repo.insert!(%ListItem{list_id: list.id, visual_novel_id: vn.id, position: position})
        Repo.insert!(%ShelfItem{shelf_id: shelf.id, visual_novel_id: vn.id})
      end

      notifications =
        for {type, id} <- [{:review, deleted_review.id}, {:comment, comment.id}, {:list, list.id}] do
          Repo.insert!(%Notification{
            user_id: user.id,
            action: :like,
            entity_type: type,
            entity_id: id
          })
        end

      assert {:ok, %{deleted_vns: 1}} =
               Deletion.delete_vns([deleted.id],
                 skip_r2: true,
                 skip_blocklist: @skip_blocklist,
                 reasons: %{deleted.id => "Fixture removal"}
               )

      refute Repo.get(VisualNovel, deleted.id)
      assert Repo.get!(VisualNovel, kept.id)
      assert Repo.get!(List, list.id).vns_count == 1
      assert Repo.get!(Shelf, shelf.id).vns_count == 1
      assert Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: kept.id).position == 1

      remaining_user = Repo.get!(User, user.id)
      assert remaining_user.favorite_visual_novels == [kept.id]
      assert remaining_user.vn_ratings_count == 1
      assert remaining_user.vn_average_rating == 2.0
      assert remaining_user.vn_reviews_count == 1
      assert remaining_user.vn_ratings_dist == RatingDistribution.adjust_bucket(dist, 4.0, -1)
      refute Repo.get(Review, deleted_review.id)
      refute Repo.get(ReviewComment, comment.id)
      for notification <- notifications, do: refute(Repo.get(Notification, notification.id))

      if @skip_blocklist do
        refute Repo.get(BannedVndbId, deleted.vndb_id)
      else
        assert %{reason: "Fixture removal"} = Repo.get!(BannedVndbId, deleted.vndb_id)
      end
    end
  end
end

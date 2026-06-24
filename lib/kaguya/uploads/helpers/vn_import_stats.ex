defmodule Kaguya.Uploads.Helpers.VnImportStats do
  @moduledoc """
  Responsible for updating VN stats (Bayesian) and single-user VN stats.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Users.User
  alias Kaguya.Reviews.RatingUpdater

  @doc """
  Incrementally updates each VN's rating distribution and Bayesian average
  based on newly inserted ratings.
  """
  def update_vn_ratings_count(inserted_ratings) do
    RatingUpdater.adjust_vns_ratings_bulk(inserted_ratings)
  end

  @doc """
  Increments the `reviews_count` for each VN based on newly inserted reviews.
  """
  def update_vn_reviews_count(inserted_reviews) do
    vn_ids =
      inserted_reviews
      |> Enum.map(& &1.visual_novel_id)
      |> Enum.uniq()

    # Single SQL statement to update all VN review counts
    query =
      from(v in VisualNovel,
        where: v.id in ^vn_ids,
        update: [
          set: [
            reviews_count:
              fragment(
                "(SELECT COUNT(*) FROM reviews WHERE visual_novel_id = ?)",
                v.id
              )
          ]
        ]
      )

    Repo.update_all(query, [])
  end

  @doc """
  Updates a single user's VN rating stats.
  Updates: vn_ratings_dist, vn_ratings_count, vn_average_rating, vn_reviews_count.
  """
  def update_user_vn_stats_for_user(user_id) do
    Repo.transaction(fn ->
      # Lock the user row to ensure exclusive access
      from(u in User, where: u.id == ^user_id, select: u)
      |> Repo.one!(lock: "FOR UPDATE")

      # 1) Build a rating distribution for this user
      rating_histogram =
        Rating
        |> where(user_id: ^user_id)
        |> group_by(:rating)
        |> select([r], {r.rating, count(r.id)})
        |> Repo.all()

      # 2) Turn it into a map for O(1) lookups
      hist_map = Map.new(rating_histogram)

      # 3) Build your 10-slot array (0.5, 1.0, …, 5.0)
      ratings_array =
        for slot <- 1..10 do
          Map.get(hist_map, slot / 2, 0)
        end

      # 4) Total count is just sum of that array
      ratings_count = Enum.sum(ratings_array)

      # 5) Weighted sum is a straight sum over the histogram
      total_ratings_sum =
        rating_histogram
        |> Enum.map(fn {rating, cnt} -> rating * cnt end)
        |> Enum.sum()

      # 6) Calculate the simple average (avoid division by zero)
      average_rating =
        if ratings_count > 0, do: total_ratings_sum / ratings_count, else: 0.0

      # 7) Count the total number of reviews
      reviews_count =
        from(rv in Review, where: rv.user_id == ^user_id)
        |> Repo.aggregate(:count, :id)

      # 8) Update user stats in the database
      Repo.update_all(
        from(u in User, where: u.id == ^user_id),
        set: [
          vn_ratings_dist: ratings_array,
          vn_ratings_count: ratings_count,
          vn_average_rating: average_rating,
          vn_reviews_count: reviews_count
        ]
      )
    end)
  end
end

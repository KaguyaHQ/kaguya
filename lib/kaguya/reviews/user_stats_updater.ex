defmodule Kaguya.Reviews.UserStatsUpdater do
  @moduledoc """
  Adjusts VN-scoped user stats stored on `users`.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.RatingDistribution
  alias Kaguya.Users.User

  @doc """
  Adjusts a user's VN rating distribution for `old_rating` -> `new_rating`.

  Recomputes:
  - `users.vn_ratings_dist`
  - `users.vn_ratings_count`
  - `users.vn_average_rating` (simple average)
  """
  def adjust_user_vn_rating(user_id, old_rating, new_rating) do
    user = Repo.get!(User, user_id)
    dist = user.vn_ratings_dist || RatingDistribution.default_dist()

    updated_dist =
      dist
      |> RatingDistribution.adjust_bucket(old_rating, -1)
      |> RatingDistribution.adjust_bucket(new_rating, +1)

    total_count = Enum.sum(updated_dist)
    total_sum = RatingDistribution.total_sum(updated_dist)
    avg = if total_count > 0, do: total_sum / total_count, else: 0.0

    {updated_count, _} =
      User
      |> where(id: ^user_id)
      |> Repo.update_all(
        set: [
          vn_ratings_dist: updated_dist,
          vn_ratings_count: total_count,
          vn_average_rating: avg
        ]
      )

    if updated_count > 0, do: {:ok, :updated}, else: {:error, :no_update}
  end

  @doc """
  Increments or decrements a user's VN reviews count (`users.vn_reviews_count`) by `delta`.
  """
  def adjust_user_vn_review_count(user_id, delta) do
    {updated_count, _} =
      User
      |> where(id: ^user_id)
      |> Repo.update_all(inc: [vn_reviews_count: delta])

    case updated_count > 0 do
      true -> {:ok, if(delta < 0, do: :decremented, else: :incremented)}
      false -> {:error, :no_update}
    end
  end
end

defmodule Kaguya.Reviews.Ratings do
  @moduledoc """
  Context for visual-novel ratings — the score a user assigns a VN,
  independent of whether they've written a review.

  Split out of `Kaguya.Reviews`: ratings have their own schema
  (`Kaguya.Reviews.Rating`), their own VN/user stat updaters, and share only
  the activity-metadata builders (`Kaguya.Reviews.ActivityMetadata`) with
  reviews.
  """

  import Kaguya.Reviews.ActivityMetadata, only: [vn_metadata: 1]

  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.VisualNovels
  alias Kaguya.Reviews.Rating
  alias Kaguya.Reviews.RatingUpdater
  alias Kaguya.Reviews.UserStatsUpdater
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Activities

  @doc """
  Creates a rating for a visual novel.
  """
  def create_rating(user_id, visual_novel_id, rating_value) do
    attrs = %{user_id: user_id, rating: rating_value, visual_novel_id: visual_novel_id}
    suppressed? = Users.ratings_suppressed?(user_id)

    result =
      Repo.transact(fn ->
        with {:ok, rating} <- Repo.insert(Rating.changeset(%Rating{}, attrs)),
             {:ok, :updated} <-
               maybe_adjust_vn_rating(suppressed?, visual_novel_id, nil, rating_value),
             {:ok, :updated} <-
               UserStatsUpdater.adjust_user_vn_rating(user_id, nil, rating_value),
             {:ok, _} <- upsert_reading_status(user_id, visual_novel_id) do
          {:ok, rating}
        end
      end)

    with {:ok, rating} <- result do
      record_rating_activity(user_id, visual_novel_id, rating.id, rating_value)
      {:ok, rating_value}
    end
  end

  @doc """
  Updates a rating.
  """
  def update_rating(visual_novel_id, user_id, new_rating_value) do
    suppressed? = Users.ratings_suppressed?(user_id)

    result =
      Repo.transact(fn ->
        with {:ok, rating} <- fetch_user_rating(visual_novel_id, user_id),
             {:ok, updated_rating} <-
               Repo.update(Rating.changeset(rating, %{rating: new_rating_value})),
             {:ok, :updated} <-
               maybe_adjust_vn_rating(
                 suppressed?,
                 visual_novel_id,
                 rating.rating,
                 new_rating_value
               ),
             {:ok, :updated} <-
               UserStatsUpdater.adjust_user_vn_rating(user_id, rating.rating, new_rating_value) do
          {:ok, updated_rating}
        end
      end)

    with {:ok, rating} <- result do
      record_rating_activity(user_id, visual_novel_id, rating.id, rating.rating)
      {:ok, rating.rating}
    end
  end

  @doc """
  Deletes a rating.
  """
  def delete_rating(visual_novel_id, user_id) do
    suppressed? = Users.ratings_suppressed?(user_id)

    result =
      Repo.transact(fn ->
        with {:ok, rating} <- fetch_user_rating(visual_novel_id, user_id),
             {:ok, _deleted} <- Repo.delete(rating),
             {:ok, :updated} <-
               maybe_adjust_vn_rating(suppressed?, visual_novel_id, rating.rating, nil),
             {:ok, :updated} <-
               UserStatsUpdater.adjust_user_vn_rating(user_id, rating.rating, nil) do
          {:ok, rating.id}
        end
      end)

    with {:ok, rating_id} <- result do
      Activities.delete_activity(user_id, :rated, "rating", rating_id)
      {:ok, true}
    end
  end

  defp maybe_adjust_vn_rating(true, _vn_id, _old, _new), do: {:ok, :updated}

  defp maybe_adjust_vn_rating(false, vn_id, old, new),
    do: RatingUpdater.adjust_vn_rating(vn_id, old, new)

  @doc """
  Gets a user's rating for a visual novel.
  """
  def get_user_rating(visual_novel_id, user_id) do
    case Repo.get_by(Rating, visual_novel_id: visual_novel_id, user_id: user_id) do
      nil -> {:ok, nil}
      %{rating: rating} -> {:ok, rating}
    end
  end

  defp fetch_user_rating(visual_novel_id, user_id) do
    case Repo.get_by(Rating, visual_novel_id: visual_novel_id, user_id: user_id) do
      nil -> {:error, :not_found}
      rating -> {:ok, rating}
    end
  end

  # Rating a VN implies the user has read it; mirror that into the shelf so the
  # rating and reading status never drift.
  defp upsert_reading_status(user_id, visual_novel_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(ReadingStatus, user_id: user_id, visual_novel_id: visual_novel_id) do
      nil ->
        %ReadingStatus{}
        |> ReadingStatus.changeset(%{
          user_id: user_id,
          visual_novel_id: visual_novel_id,
          status: :read,
          library_added_at: now
        })
        |> Repo.insert()

      %ReadingStatus{status: :read} = rs ->
        {:ok, rs}

      %ReadingStatus{} = rs ->
        rs
        |> Ecto.Changeset.change(%{
          status: :read,
          updated_at: now
        })
        |> Repo.update()
    end
  end

  defp record_rating_activity(user_id, visual_novel_id, rating_id, rating_value) do
    vn = VisualNovels.get_visual_novel(visual_novel_id)

    # Delete previous rating activity so re-ratings get fresh metadata
    Activities.delete_activity(user_id, :rated, "rating", rating_id)

    Activities.record_activity(%{
      user_id: user_id,
      action: :rated,
      entity_type: "rating",
      entity_id: rating_id,
      metadata: Map.put(vn_metadata(vn), :rating, rating_value)
    })
  end
end

defmodule Kaguya.Reviews.RatingUpdater do
  @moduledoc """
  Handles rating and review count updates for visual novels.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.RatingDistribution
  alias Kaguya.VisualNovels.VisualNovel

  @prior_mean 3.5
  @prior_count 10

  @values_types %{
    id: :binary_id,
    ratings_dist: {:array, :integer},
    ratings_count: :integer,
    average_rating: :float
  }

  # ------------------------------------------------------------------
  # Bulk Update (many new ratings, e.g. import)
  # ------------------------------------------------------------------

  @doc """
  Given a list of `inserted_ratings` (each with %{visual_novel_id, rating}), merges them
  with existing ratings in the DB, recalculates distribution, and does a bulk upsert.
  """
  def adjust_vns_ratings_bulk([]), do: :ok

  def adjust_vns_ratings_bulk(inserted_ratings) do
    # 1) Gather all visual_novel_ids from the newly inserted ratings
    vn_ids = Enum.map(inserted_ratings, & &1.visual_novel_id)

    # 2) Fetch existing distributions from the DB in one query
    existing_dists =
      Repo.all(
        from v in VisualNovel,
          where: v.id in ^vn_ids,
          select: {v.id, v.ratings_dist}
      )
      |> Map.new()

    # 3) Merge new ratings with existing distributions
    merged_dists =
      Enum.reduce(inserted_ratings, existing_dists, fn %{visual_novel_id: vn_id, rating: rating},
                                                       acc ->
        old_dist = Map.get(acc, vn_id, RatingDistribution.default_dist())
        new_dist = RatingDistribution.adjust_bucket(old_dist, rating, +1)
        Map.put(acc, vn_id, new_dist)
      end)

    # 4) Build the "rows" we'll upsert
    updates =
      Enum.map(merged_dists, fn {vn_id, dist} ->
        total_count = Enum.sum(dist)
        total_sum = RatingDistribution.total_sum(dist)

        bayesian =
          RatingDistribution.bayesian_average(@prior_mean, @prior_count, total_sum, total_count)

        %{
          id: vn_id,
          ratings_dist: dist,
          ratings_count: total_count,
          average_rating: bayesian
        }
      end)

    # 5) Single bulk UPDATE via VALUES()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(
      from(v in VisualNovel,
        join: vals in values(updates, @values_types),
        on: vals.id == v.id,
        update: [
          set: [
            ratings_dist: field(vals, :ratings_dist),
            ratings_count: field(vals, :ratings_count),
            average_rating: field(vals, :average_rating),
            updated_at: ^now
          ]
        ]
      ),
      []
    )
  end

  # ------------------------------------------------------------------
  # Single-VN Updates
  # ------------------------------------------------------------------

  @doc """
  Adjusts the review count for a visual novel.
  """
  def adjust_vn_review_count(visual_novel_id, delta) do
    {updated_count, _} =
      VisualNovel
      |> where(id: ^visual_novel_id)
      |> Repo.update_all(inc: [reviews_count: delta])

    if updated_count > 0 do
      {:ok, if(delta < 0, do: :decremented, else: :incremented)}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Adjusts the rating statistics for a visual novel.
  Called when a rating is created, updated, or deleted.
  """
  def adjust_vn_rating(visual_novel_id, old_rating, new_rating) do
    case Repo.get(VisualNovel, visual_novel_id) do
      nil ->
        {:error, :not_found}

      vn ->
        dist = vn.ratings_dist || RatingDistribution.default_dist()

        updated_dist =
          dist
          |> RatingDistribution.adjust_bucket(old_rating, -1)
          |> RatingDistribution.adjust_bucket(new_rating, +1)

        new_count = RatingDistribution.total_count(updated_dist)
        total_sum = RatingDistribution.total_sum(updated_dist)

        new_avg =
          RatingDistribution.bayesian_average(@prior_mean, @prior_count, total_sum, new_count)

        {updated_count, _} =
          VisualNovel
          |> where(id: ^visual_novel_id)
          |> Repo.update_all(
            set: [
              ratings_dist: updated_dist,
              ratings_count: new_count,
              average_rating: new_avg
            ]
          )

        if updated_count > 0, do: {:ok, :updated}, else: {:error, :no_update}
    end
  end
end

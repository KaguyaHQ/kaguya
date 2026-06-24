defmodule Kaguya.Reviews.RatingRecalculator do
  @moduledoc """
  Recalculates VN rating aggregates from scratch, excluding suppressed users.

  Used when a user's `ratings_suppressed` flag is toggled — all VNs they've
  rated need their cached stats rebuilt from the remaining valid ratings.
  """

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VNPageCache

  @prior_mean 3.5
  @prior_count 10

  @doc """
  Recalculates `average_rating`, `ratings_count`, and `ratings_dist` for every
  VN that `user_id` has rated. Excludes all suppressed users' ratings.

  Runs as a single SQL statement regardless of how many VNs are affected.
  """
  def recalculate_for_user(user_id) do
    result = Repo.query!(recalc_sql(), [dump_uuid!(user_id)])
    # Touches an unbounded set of VNs (everything the user rated), so a full
    # clear is cheaper than computing the affected set to invalidate per-VN.
    VNPageCache.clear_all()
    result
  end

  @doc """
  Recalculates rating aggregates for a specific VN, excluding suppressed users.
  """
  def recalculate_for_vn(visual_novel_id) do
    result = Repo.query!(recalc_vn_sql(), [dump_uuid!(visual_novel_id)])
    VNPageCache.invalidate(visual_novel_id)
    result
  end

  defp dump_uuid!(<<_::128>> = raw), do: raw
  defp dump_uuid!(id), do: Ecto.UUID.dump!(id)

  # Recalculates all VNs touched by a given user.
  defp recalc_sql do
    """
    WITH affected AS (
      SELECT DISTINCT visual_novel_id FROM ratings WHERE user_id = $1
    ),
    recalced AS (
      SELECT
        r.visual_novel_id,
        COUNT(*)::int AS ratings_count,
        SUM(r.rating)::double precision AS total_sum,
        ARRAY[
          COUNT(*) FILTER (WHERE r.rating = 0.5),
          COUNT(*) FILTER (WHERE r.rating = 1.0),
          COUNT(*) FILTER (WHERE r.rating = 1.5),
          COUNT(*) FILTER (WHERE r.rating = 2.0),
          COUNT(*) FILTER (WHERE r.rating = 2.5),
          COUNT(*) FILTER (WHERE r.rating = 3.0),
          COUNT(*) FILTER (WHERE r.rating = 3.5),
          COUNT(*) FILTER (WHERE r.rating = 4.0),
          COUNT(*) FILTER (WHERE r.rating = 4.5),
          COUNT(*) FILTER (WHERE r.rating = 5.0)
        ]::int[] AS ratings_dist
      FROM ratings r
      JOIN users u ON u.id = r.user_id
      WHERE r.visual_novel_id IN (SELECT visual_novel_id FROM affected)
        AND NOT u.ratings_suppressed
      GROUP BY r.visual_novel_id
    )
    UPDATE visual_novels v
    SET ratings_dist    = COALESCE(rc.ratings_dist, '{0,0,0,0,0,0,0,0,0,0}'),
        ratings_count   = COALESCE(rc.ratings_count, 0),
        average_rating  = CASE
          WHEN COALESCE(rc.ratings_count, 0) = 0 THEN #{@prior_mean}
          ELSE (#{@prior_count} * #{@prior_mean} + COALESCE(rc.total_sum, 0))
               / (#{@prior_count} + COALESCE(rc.ratings_count, 0))
        END,
        updated_at      = NOW()
    FROM affected a
    LEFT JOIN recalced rc ON rc.visual_novel_id = a.visual_novel_id
    WHERE v.id = a.visual_novel_id
    """
  end

  # Recalculates a single VN.
  defp recalc_vn_sql do
    """
    WITH recalced AS (
      SELECT
        r.visual_novel_id,
        COUNT(*)::int AS ratings_count,
        SUM(r.rating)::double precision AS total_sum,
        ARRAY[
          COUNT(*) FILTER (WHERE r.rating = 0.5),
          COUNT(*) FILTER (WHERE r.rating = 1.0),
          COUNT(*) FILTER (WHERE r.rating = 1.5),
          COUNT(*) FILTER (WHERE r.rating = 2.0),
          COUNT(*) FILTER (WHERE r.rating = 2.5),
          COUNT(*) FILTER (WHERE r.rating = 3.0),
          COUNT(*) FILTER (WHERE r.rating = 3.5),
          COUNT(*) FILTER (WHERE r.rating = 4.0),
          COUNT(*) FILTER (WHERE r.rating = 4.5),
          COUNT(*) FILTER (WHERE r.rating = 5.0)
        ]::int[] AS ratings_dist
      FROM ratings r
      JOIN users u ON u.id = r.user_id
      WHERE r.visual_novel_id = $1
        AND NOT u.ratings_suppressed
      GROUP BY r.visual_novel_id
    )
    UPDATE visual_novels v
    SET ratings_dist    = COALESCE(rc.ratings_dist, '{0,0,0,0,0,0,0,0,0,0}'),
        ratings_count   = COALESCE(rc.ratings_count, 0),
        average_rating  = CASE
          WHEN COALESCE(rc.ratings_count, 0) = 0 THEN #{@prior_mean}
          ELSE (#{@prior_count} * #{@prior_mean} + COALESCE(rc.total_sum, 0))
               / (#{@prior_count} + COALESCE(rc.ratings_count, 0))
        END,
        updated_at      = NOW()
    FROM (SELECT $1::uuid AS visual_novel_id) a
    LEFT JOIN recalced rc ON rc.visual_novel_id = a.visual_novel_id
    WHERE v.id = a.visual_novel_id
    """
  end
end

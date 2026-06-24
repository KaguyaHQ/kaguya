defmodule Kaguya.Tags.TagRelevance do
  @moduledoc """
  Calculates and precomputes tag relevance scores for vn_tags.

  Two ingredients blended together:

    1. **VNDB side** — Bayesian shrinkage on the imported `vndb_avg_score`
       (-3..3) and `vndb_vote_count`. Maps to [0,1].
    2. **Kaguya side** — graded community votes (0..5) aggregated via shrunk
       mean (prior 2.5 = Moderate Element, strength 5 = same evidence-weight
       as the old α+β=10 binary formula). Maps to [0,1].

  Final `relevance_score` ramps from VNDB-only (no Kaguya votes) to
  Kaguya-only (≥ kaguya_ramp_votes). Same shape as before; only the Kaguya
  side changed from Beta-on-binary to shrunk-mean-on-graded.
  """

  require Logger

  alias Kaguya.Repo

  @vndb_profile %{
    # VNDB Bayesian shrinkage
    # 5 votes for 50% trust
    bayesian_m: 5.0,
    # prior mean (skeptical default)
    bayesian_c: 0.7,

    # Kaguya graded shrinkage. Prior is the VNDB-derived score (mapped 0..5),
    # NOT a fixed middle value — that means "no Kaguya votes" leaves the
    # score at vndb_score, and every vote nudges the score IN THE DIRECTION
    # the user voted. Avoids the prior-2.5 trap where voting Main Theme on
    # a tag VNDB already says is strong dragged the score downward.
    # how many "virtual VNDB voters" to anchor against
    kaguya_prior_strength: 5.0,
    # bucket-scale ceiling (0..5)
    kaguya_value_max: 5.0
  }

  @doc """
  VNDB tag relevance helper exposed for ad-hoc callers (analytics, etc.).
  Maps a (avg_vote, vote_count) pair to [0,1] via the same Bayesian
  shrinkage formula used in the bulk SQL recomputes.
  """
  def vndb_relevance(avg_vote, vote_count, prior \\ 10.0)

  def vndb_relevance(nil, _vote_count, _prior), do: 0.5

  def vndb_relevance(avg_vote, vote_count, prior)
      when is_number(avg_vote) and is_number(vote_count) and is_number(prior) do
    v = max(-3.0, min(3.0, avg_vote * 1.0))
    raw = (v + 3.0) / 6.0
    vc = max(0.0, vote_count * 1.0)
    pr = max(0.0, prior * 1.0)

    if vc + pr == 0.0 do
      raw
    else
      (raw * vc + 0.5 * pr) / (vc + pr)
    end
  end

  @doc """
  Recompute relevance scores for all tags on a specific visual novel.
  """
  def recompute_vn_tags_for_visual_novel(visual_novel_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    vn_id_bin = uuid_to_binary(visual_novel_id)

    Repo.query!(
      recompute_sql("WHERE vt.visual_novel_id = $1"),
      recompute_params([vn_id_bin], now)
    )
  end

  @doc """
  Recompute all VN tag relevance scores. Single bulk UPDATE.
  """
  def recompute_all_vn_tags(_opts \\ []) do
    Logger.info("Starting VN tag relevance recomputation (bulk)...")
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    result = Repo.query!(recompute_sql(""), recompute_params([], now), timeout: :infinity)
    Logger.info("VN tag relevance recomputation complete: #{result.num_rows} tags updated")
    :ok
  end

  @doc """
  Recompute VN tag relevance for all VNs that have a specific tag.
  """
  def recompute_vn_tags_for_tag(tag_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tag_id_bin = uuid_to_binary(tag_id)
    Repo.query!(recompute_sql("WHERE vt.tag_id = $1"), recompute_params([tag_id_bin], now))
  end

  # ----------------------------------------------------------------------------
  # Shared SQL — single source of truth for the relevance formula.
  # The three public functions vary only by WHERE clause; everything else
  # (Bayesian shrinkage, graded mean, ramp blend, clamp) is identical.
  # ----------------------------------------------------------------------------

  defp recompute_sql(scope_where) do
    # Param order (after scope-prefix):
    #   $base+1 bayesian_c, $base+2 bayesian_m,
    #   $base+3 kaguya_prior_strength, $base+4 kaguya_value_max, $base+5 now
    base = if scope_where == "", do: 0, else: 1

    """
    WITH base AS (
      SELECT
        vt.visual_novel_id,
        vt.tag_id,

        -- VNDB component: Bayesian shrinkage of normalized avg score, in [0,1]
        (
          (
            (LEAST(3.0, GREATEST(-3.0, COALESCE(vt.vndb_avg_score, 0.0))) + 3.0) / 6.0
            * COALESCE(vt.vndb_vote_count, 0)::float8
            + $#{base + 1}::float8 * $#{base + 2}::float8
          )
          /
          NULLIF(COALESCE(vt.vndb_vote_count, 0)::float8 + $#{base + 2}::float8, 0.0)
        ) AS vndb_score,

        COALESCE(kv.value_sum, 0)::float8 AS k_sum,
        COALESCE(kv.vote_count, 0)::float8 AS k_count
      FROM vn_tags vt
      LEFT JOIN (
        SELECT visual_novel_id, tag_id, COUNT(*) AS vote_count, SUM(value) AS value_sum
        FROM vn_tag_votes
        GROUP BY visual_novel_id, tag_id
      ) kv ON kv.visual_novel_id = vt.visual_novel_id AND kv.tag_id = vt.tag_id
      #{scope_where}
    ),
    scored AS (
      -- Shrink the Kaguya graded mean toward the VNDB-derived score (mapped 0..5).
      -- Effect: no Kaguya votes → result is exactly vndb_score. Each vote nudges
      -- in the direction the user voted, with magnitude that grows as count
      -- overtakes the prior strength.
      SELECT
        visual_novel_id,
        tag_id,
        (
          (k_sum + $#{base + 3}::float8 * vndb_score * $#{base + 4}::float8)
          /
          NULLIF(k_count + $#{base + 3}::float8, 0.0)
        ) / $#{base + 4}::float8 AS final_score
      FROM base
    )
    UPDATE vn_tags vt
    SET relevance_score = GREATEST(0.0, LEAST(1.0, scored.final_score)),
        updated_at = $#{base + 5}
    FROM scored
    WHERE vt.visual_novel_id = scored.visual_novel_id
      AND vt.tag_id = scored.tag_id
    """
  end

  defp recompute_params(scope_args, now) do
    %{
      bayesian_c: c,
      bayesian_m: m,
      kaguya_prior_strength: kps,
      kaguya_value_max: kvm
    } = @vndb_profile

    scope_args ++ [c, m, kps, kvm, now]
  end

  # Converts a UUID to binary format for Postgrex.
  defp uuid_to_binary(uuid) when is_binary(uuid) and byte_size(uuid) == 16, do: uuid
  defp uuid_to_binary(uuid), do: Ecto.UUID.dump!(uuid)
end

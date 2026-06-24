defmodule Kaguya.Sync.DumpSync.Images.CoverSelection do
  @moduledoc """
  Smart cover selection algorithm for VNs.

  Translates the SQL in `priv/repo/scripts/select_best_covers.sql` to Elixir
  queries against the VNDB dump via `DumpSync.query_vndb_raw!/3`.

  Priority order:
    1. Portrait ratio (0.617–0.717) + recent (≥ 20210101) + >4 votes → most voted
    2. Portrait ratio (any date) → most voted
    3. Any ratio → most voted
    4. Fallback: vn.c_image, then vn.image

  Only runs for VNs where `primary_image_id IS NULL` (the delta).
  Returns `%{vndb_vn_id => cv_id}` map.
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync

  @portrait_min 0.617
  @portrait_max 0.717
  @recent_threshold 20_210_101
  @min_votes_for_recent 4

  def run(vndb, vn_mapping) do
    # Only select covers for VNs that don't have one yet
    pending_vndb_ids = pending_vn_vndb_ids(vn_mapping)

    if pending_vndb_ids == [] do
      Logger.info("CoverSelection: no pending VNs")
      %{}
    else
      Logger.info("CoverSelection: selecting covers for #{length(pending_vndb_ids)} VNs")
      do_select(vndb, pending_vndb_ids)
    end
  end

  defp pending_vn_vndb_ids(vn_mapping) do
    vndb_ids = Map.keys(vn_mapping)

    from(vn in Kaguya.VisualNovels.VisualNovel,
      where: is_nil(vn.primary_image_id) and vn.vndb_id in ^vndb_ids,
      select: vn.vndb_id
    )
    |> Repo.all()
  end

  defp do_select(vndb, pending_vndb_ids) do
    # 1. Load cover votes: {vid, img, width, height, ratio, votes}
    cover_votes = load_cover_votes(vndb, pending_vndb_ids)
    # 2. Load release dates: {vid, img, max_released}
    release_dates = load_release_dates(vndb, pending_vndb_ids)
    # 3. Build candidates with tolerance/recency flags
    candidates = build_candidates(cover_votes, release_dates)
    # 4. Apply priority picks
    voted_picks = pick_by_priority(candidates)
    # 5. Fallback for VNs without any votes
    vns_with_votes = candidates |> Enum.map(& &1.vid) |> MapSet.new()
    vns_needing_fallback = Enum.reject(pending_vndb_ids, &MapSet.member?(vns_with_votes, &1))
    fallback_picks = load_fallbacks(vndb, vns_needing_fallback)

    result = Map.merge(fallback_picks, voted_picks)

    log_methods(result, voted_picks, fallback_picks)
    result
  end

  # ── VNDB Queries ─────────────────────────────────────────────────────────

  defp load_cover_votes(vndb, vndb_ids) do
    # Query in batches to avoid parameter limits
    vndb_ids
    |> Enum.chunk_every(5000)
    |> Enum.flat_map(fn chunk ->
      placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

      DumpSync.query_vndb_raw!(
        vndb,
        """
          SELECT viv.vid, viv.img, i.width, i.height,
                 ROUND(i.width::numeric / NULLIF(i.height, 0), 3) AS ratio,
                 COUNT(*) AS votes,
                 i.c_sexual_avg, i.c_votecount
          FROM vn_image_votes viv
          JOIN images i ON i.id = viv.img
          WHERE viv.vid IN (#{placeholders})
          GROUP BY viv.vid, viv.img, i.width, i.height, i.c_sexual_avg, i.c_votecount
        """,
        chunk
      )
    end)
    |> Enum.map(fn [vid, img, width, height, ratio, votes, c_sexual_avg, c_votecount] ->
      %{
        vid: vid,
        img: img,
        width: width,
        height: height,
        ratio: ratio && Decimal.to_float(ratio),
        votes: votes,
        c_sexual_avg: c_sexual_avg,
        c_votecount: c_votecount
      }
    end)
  end

  defp load_release_dates(vndb, vndb_ids) do
    vndb_ids
    |> Enum.chunk_every(5000)
    |> Enum.flat_map(fn chunk ->
      placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

      DumpSync.query_vndb_raw!(
        vndb,
        """
          SELECT rv.vid, ri.img,
                 MAX(r.released) AS max_released,
                 MIN(r.released) AS min_released,
                 COALESCE(
                   MIN(CASE WHEN array_length(ri.lang, 1) = 1 THEN ri.lang[1]::text END),
                   MIN(r.olang::text)
                 ) AS language
          FROM releases_images ri
          JOIN releases r ON r.id = ri.id
          JOIN releases_vn rv ON rv.id = ri.id
          WHERE rv.vid IN (#{placeholders})
            AND ri.img LIKE 'cv%'
          GROUP BY rv.vid, ri.img
        """,
        chunk
      )
    end)
    |> Map.new(fn [vid, img, max_released, min_released, language] ->
      {{vid, img}, %{max_released: max_released, min_released: min_released, language: language}}
    end)
  end

  defp load_fallbacks(vndb, vndb_ids) do
    if vndb_ids == [] do
      %{}
    else
      vndb_ids
      |> Enum.chunk_every(5000)
      |> Enum.flat_map(fn chunk ->
        placeholders = Enum.map_join(1..length(chunk), ", ", &"$#{&1}")

        DumpSync.query_vndb_raw!(
          vndb,
          """
            SELECT v.id,
                   CASE WHEN v.c_image IS NOT NULL THEN v.c_image ELSE v.image END AS img,
                   i.c_sexual_avg, i.c_votecount
            FROM vn v
            LEFT JOIN images i ON i.id = CASE WHEN v.c_image IS NOT NULL THEN v.c_image ELSE v.image END
            WHERE v.id IN (#{placeholders})
              AND (v.c_image IS NOT NULL OR v.image IS NOT NULL)
          """,
          chunk
        )
      end)
      |> Map.new(fn [vid, img, c_sexual_avg, c_votecount] ->
        {vid, %{cv_id: img, vndb_votes: 0, c_sexual_avg: c_sexual_avg, c_votecount: c_votecount}}
      end)
    end
  end

  # ── Candidate Building ──────────────────────────────────────────────────

  defp build_candidates(cover_votes, release_dates) do
    Enum.map(cover_votes, fn cv ->
      rel = Map.get(release_dates, {cv.vid, cv.img}, %{})
      max_released = rel[:max_released] || 0
      ratio = cv.ratio || 0.0

      Map.merge(cv, %{
        max_released: max_released,
        release_date: DumpSync.parse_vndb_date(rel[:min_released]),
        language: rel[:language],
        in_tolerance: ratio >= @portrait_min and ratio <= @portrait_max,
        is_recent: max_released >= @recent_threshold
      })
    end)
  end

  # ── Priority Selection ─────────────────────────────────────────────────

  defp pick_by_priority(candidates) do
    by_vid = Enum.group_by(candidates, & &1.vid)

    Enum.reduce(by_vid, %{}, fn {vid, cands}, acc ->
      picked = pick_one(cands)

      if picked do
        Map.put(acc, vid, %{
          cv_id: picked.img,
          vndb_votes: picked.votes,
          language: picked.language,
          release_date: picked.release_date,
          c_sexual_avg: picked.c_sexual_avg,
          c_votecount: picked.c_votecount
        })
      else
        acc
      end
    end)
  end

  defp pick_one(cands) do
    # P1: portrait + recent + >4 votes
    p1 =
      cands
      |> Enum.filter(&(&1.in_tolerance and &1.is_recent and &1.votes > @min_votes_for_recent))
      |> best_by_votes()

    # P2: portrait (any date)
    # P3: any ratio
    p1 ||
      cands |> Enum.filter(& &1.in_tolerance) |> best_by_votes() ||
      best_by_votes(cands)
  end

  defp best_by_votes([]), do: nil

  defp best_by_votes(cands) do
    # SQL: ORDER BY votes DESC, img ASC → highest votes, lowest img as tiebreaker
    Enum.min_by(cands, fn c -> {-c.votes, c.img} end)
  end

  # ── Logging ────────────────────────────────────────────────────────────

  defp log_methods(result, voted, fallback) do
    Logger.info(
      "CoverSelection: #{map_size(result)} total " <>
        "(#{map_size(voted)} voted, #{map_size(fallback)} fallback)"
    )
  end
end

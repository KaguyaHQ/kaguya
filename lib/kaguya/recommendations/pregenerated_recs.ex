defmodule Kaguya.Recommendations.PregeneratedRecs do
  @moduledoc """
  Pre-generated public recommendations backed by an offline top-25 scoring
  pass against the EASE model.

  ## Why pre-generated

  Recs are scored offline and packed into
  `priv/data/pregenerated_recs.bin`, so a request is just an ETS lookup
  plus a single hydration SQL query. Sub-ms compute, no Nx pass at
  request time.

  Covers the users the offline script could snapshot (uids with >=5
  votes in the source dump, and >=3 vocab-matched prefs). Brand-new
  VNDB users and very light users fall through to `:not_pregenerated`.

  ## Username lookup

  Unlike the other two modules, `recommend/2` also accepts a username —
  the loader populates a `:pregenerated_username_index` ETS table from
  VNDB's `public.users` at generation time. Usernames are lowercased
  at write time so lookups are case-insensitive without a per-request
  `String.downcase/1`.

  ## Pipeline

    1. Normalize ident (trim + downcase).
    2. If it parses as a VNDB uid (`u<n>`), use as-is. Else look up
       username in `:pregenerated_username_index` -> uid, else
       `:not_found`.
    3. Look up uid in `:pregenerated_user_recs` -> packed recs +
       pref_count. If absent, `:not_pregenerated`.
    4. Decode the packed binary -> `[{vid, score}, ...]`.
    5. Apply the caller's `:limit` and hydrate into Kaguya VN rows.

  No caching — ETS lookup is already microsecond-fast, and hydration
  runs one indexed SQL query per request.

  Returns the same `%{items, pref_count, masked_count, tag_counts}`
  shape as the other two modules so the resolver can dispatch uniformly.
  `masked_count` is always 0 (masking happened offline; the caller has
  no insight into the pre-gen mask set) and `tag_counts` is always `[]`
  (guests on this path don't get tag filtering).
  """

  require Logger

  alias Kaguya.Recommendations.Percentiles
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel

  import Ecto.Query, only: [from: 2]

  @recs_table :pregenerated_user_recs
  @username_table :pregenerated_username_index

  # VNDB user ids look like `u12345`. Real ids stay well under 10^10;
  # 10-digit cap is sufficient and attacker-proof.
  @uid_regex ~r/^u\d{1,10}$/

  # Matches `TOP_K` in `priv/recommendations/pregenerate_user_recs.py`.
  # Defensive ceiling on how many decoded recs we hydrate per request —
  # the caller's `:limit` (default 20) is applied on top.
  @max_pregenerated 30

  @doc """
  Look up pre-generated recs by VNDB uid OR username.

  Opts:
    * `:limit` — max rows returned (default 20)

  Returns:
    * `{:ok, %{items: [...], pref_count: n, masked_count: 0, tag_counts: []}}`
    * `{:error, :not_found}` — ident is neither a known uid format nor a
      known username in the snapshot
    * `{:error, :not_pregenerated}` — ident resolves to a uid but that
      uid wasn't scored (below the script's vote floor, or the snapshot
      predates the user signing up)
  """
  def recommend(ident, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    normalized = ident |> to_string() |> String.trim() |> String.downcase()

    with {:ok, uid} <- resolve_to_uid(normalized),
         {:ok, {pref_count, recs}} <- lookup_recs(uid) do
      # Cap at @max_pregenerated (30, matching TOP_K in the Python
      # writer) before hydration. The file today holds 30 recs/user;
      # capping defensively means a future snapshot that accidentally
      # ships more doesn't blow up hydration cost for `limit <= 30`
      # callers. `Enum.take(limit)` below trims to the caller's ask.
      capped = Enum.take(recs, @max_pregenerated)
      items = hydrate_items(capped, limit)

      {:ok,
       %{
         items: items,
         pref_count: pref_count,
         masked_count: 0,
         tag_counts: []
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # ident -> uid
  # ---------------------------------------------------------------------------

  defp resolve_to_uid(""), do: {:error, :not_found}

  defp resolve_to_uid(ident) do
    if Regex.match?(@uid_regex, ident) do
      {:ok, ident}
    else
      lookup_username(ident)
    end
  end

  @doc """
  Resolve a string (uid or username) to a VNDB uid using only the ETS
  username index. Exposed so callers can map VNDB user ids accepting either
  form without calling into `recommend/2`.

  Returns `{:ok, uid}` or `:error` (preserving the no-payload idiom the
  callers already use for local lookups).
  """
  # Called with already-normalized input from the resolver; the
  # trim/downcase here is a cheap safety net for any future direct
  # caller that forgets to pre-normalize.
  def resolve_ident(ident) when is_binary(ident) do
    ident
    |> String.trim()
    |> String.downcase()
    |> do_resolve_ident()
  end

  def resolve_ident(_), do: :error

  defp do_resolve_ident(""), do: :error

  defp do_resolve_ident(normalized) do
    if Regex.match?(@uid_regex, normalized) do
      {:ok, normalized}
    else
      case lookup_username(normalized) do
        {:ok, uid} -> {:ok, uid}
        _ -> :error
      end
    end
  end

  defp lookup_username(username) do
    case safe_lookup(@username_table, username) do
      [{^username, uid}] -> {:ok, uid}
      _ -> {:error, :not_found}
    end
  end

  defp lookup_recs(uid) do
    case safe_lookup(@recs_table, uid) do
      [{^uid, {pref_count, recs}}] when is_list(recs) -> {:ok, {pref_count, recs}}
      _ -> {:error, :not_pregenerated}
    end
  end

  # ETS rescues — if the loader crashed mid-boot or the table was
  # dropped, treat as empty rather than propagating an ArgumentError to
  # the resolver.
  defp safe_lookup(table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError ->
      Logger.warning("[PregeneratedRecs] ETS table #{table} unavailable")
      []
  end

  # ---------------------------------------------------------------------------
  # Hydration — pre-gen rec → Kaguya VN. Pulls VNs both for the rec
  # itself and for each rec's inline `reasons` so the tooltip can render
  # "Because you liked X (72%)" without any follow-up queries. Both rec
  # and reason vndb_ids are collapsed into a single lookup query.
  #
  # Legacy v1 snapshots carry no reasons and no `total_positive_contribution`
  # — those rec maps come through with `reasons: []` / `total_positive_contribution: nil`
  # and the frontend falls back to hiding the tooltip breakdown.
  # ---------------------------------------------------------------------------

  defp hydrate_items(recs, limit) do
    all_vndb_ids =
      recs
      |> Enum.flat_map(fn rec ->
        [rec.vndb_id | Enum.map(rec.reasons, & &1.vndb_id)]
      end)
      |> Enum.uniq()

    vn_lookup = lookup_vns_by_vndb_id(all_vndb_ids)

    recs
    |> Enum.flat_map(fn rec ->
      case Map.fetch(vn_lookup, rec.vndb_id) do
        {:ok, vn} ->
          [
            %{
              visual_novel: vn,
              rank: 0,
              score: rec.score,
              ease_score: rec.score,
              relevance_pct: Percentiles.relevance_pct(rec.score),
              total_positive_contribution: rec.total_positive_contribution,
              because_you_liked: hydrate_reasons(rec.reasons, vn_lookup)
            }
          ]

        :error ->
          []
      end
    end)
    |> Enum.take(limit)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, rank} -> %{item | rank: rank} end)
  end

  # Each reason carries the VNDB user's original signal on the source VN —
  # either a vote (10-100 in VNDB's scale) or a label id (1-5). Map it
  # back to Kaguya's `user_rating` / `user_status` shape so the frontend
  # renders "Because they rated X N★" / status text for guests the same
  # way it does for logged-in users.
  defp hydrate_reasons(reasons, vn_lookup) do
    Enum.flat_map(reasons, fn %{vndb_id: vid, contribution: contribution} = reason ->
      case Map.fetch(vn_lookup, vid) do
        {:ok, vn} ->
          {user_rating, user_status} = reason_signal(reason)

          [
            %{
              visual_novel: vn,
              user_rating: user_rating,
              user_status: user_status,
              contribution: contribution
            }
          ]

        :error ->
          []
      end
    end)
  end

  # VNDB label ids (1-5) → Kaguya reading-status strings the frontend
  # already knows how to render. Label 6 (Blacklist) never reaches us —
  # the pregen script excludes blacklisted vids from prefs.
  @vndb_label_to_status %{
    1 => "currently_reading",
    2 => "read",
    3 => "on_hold",
    4 => "did_not_finish",
    5 => "want_to_read"
  }

  # VNDB stores votes as integers (10 = 1.0, 100 = 10.0). Guests see
  # their VNDB votes on VNDB's native 1-10 scale — the frontend renders
  # "N.N/10" for the guest path instead of Kaguya's 0.5-5.0 half-star
  # format. Keeping the rating in its source scale avoids a round-trip
  # conversion users would have to mentally reverse.
  defp reason_signal(%{vote: vote}) when is_integer(vote) and vote > 0 do
    {vote / 10.0, nil}
  end

  defp reason_signal(%{label_id: label_id}) when is_integer(label_id) and label_id > 0 do
    {nil, Map.get(@vndb_label_to_status, label_id)}
  end

  defp reason_signal(_), do: {nil, nil}

  defp lookup_vns_by_vndb_id([]), do: %{}

  defp lookup_vns_by_vndb_id(vndb_ids) do
    from(vn in VisualNovel, where: vn.vndb_id in ^vndb_ids, select: {vn.vndb_id, vn})
    |> Repo.all()
    |> Map.new()
  end
end

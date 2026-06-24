defmodule Kaguya.Library do
  @moduledoc """
  Viewer-facing VN library aggregation.

  Returns paginated VN + reading status entries. Enrichment fields (rating,
  review, shelves) are loaded through batched helpers when callers need them.
  """

  import Ecto.Query

  alias Kaguya.Pagination
  alias Kaguya.Repo

  alias Kaguya.Shelves
  alias Kaguya.Shelves.{Shelf, ShelfItem, ReadingStatus}
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Reviews.{Rating, Review}

  @tag_relevance_threshold 0.72

  # Length/age bucket CASE expressions shared by group_by and select. Boundaries
  # mirror `length_category_range/1` and `age_rating_range/1`.
  @length_bucket_sql "CASE WHEN ? < 120 THEN 'very_short' WHEN ? < 600 THEN 'short' WHEN ? < 1800 THEN 'medium' WHEN ? < 3000 THEN 'long' ELSE 'very_long' END"
  @age_bucket_sql "CASE WHEN ? < 12 THEN 'all_ages' WHEN ? < 16 THEN '13+' WHEN ? < 18 THEN '16+' ELSE '18+' END"

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  List VNs in a user's library, with hydrated viewer-specific fields.

  Supports:
  - `:status` (optional)
  - `:shelf_slug` (optional)
  - `:search` (optional, title substring)
  - `:sort_by` (optional)
  - `:page`, `:page_size`
  """
  def list_library_visual_novels(user_id, args, opts \\ [])
      when is_binary(user_id) and is_map(args) do
    list_library_pairs(user_id, %{
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 20),
      status: Map.get(args, :status),
      sort_by: Map.get(args, :sort_by),
      search: Map.get(args, :search),
      shelf_slug: Map.get(args, :shelf_slug),
      rating: Map.get(args, :rating),
      tag_slug: Map.get(args, :tag_slug),
      producer_slug: Map.get(args, :producer_slug),
      original_language: Map.get(args, :original_language),
      read_year: Map.get(args, :read_year),
      release_year: Map.get(args, :release_year),
      length_category: Map.get(args, :length_category),
      age_rating: Map.get(args, :age_rating),
      allowed_categories: Keyword.get(opts, :allowed_categories)
    })
  end

  @doc """
  Returns a map of reading status => count for a user's library.

  With no status filter, returns all statuses in one GROUP BY query plus an
  `all` key (everything except not_interested). With a status filter, returns
  just that status's count under its key.
  """
  def library_status_counts(user_id, status \\ nil, opts \\ [])

  def library_status_counts(user_id, nil, opts) do
    allowed = Keyword.get(opts, :allowed_categories)

    counts =
      ReadingStatus
      |> where([rs], rs.user_id == ^user_id)
      |> maybe_filter_category_via_join(allowed)
      |> group_by([rs], rs.status)
      |> select([rs], {rs.status, count(rs.id)})
      |> Repo.all()
      |> Map.new()

    all = counts |> Map.delete(:not_interested) |> Map.values() |> Enum.sum()

    %{
      all: all,
      currently_reading: Map.get(counts, :currently_reading, 0),
      read: Map.get(counts, :read, 0),
      want_to_read: Map.get(counts, :want_to_read, 0),
      on_hold: Map.get(counts, :on_hold, 0),
      did_not_finish: Map.get(counts, :did_not_finish, 0),
      not_interested: Map.get(counts, :not_interested, 0)
    }
  end

  def library_status_counts(user_id, status, opts) do
    allowed = Keyword.get(opts, :allowed_categories)

    count =
      ReadingStatus
      |> where([rs], rs.user_id == ^user_id and rs.status == ^status)
      |> maybe_filter_category_via_join(allowed)
      |> Repo.aggregate(:count, :id)

    %{status => count}
  end

  @doc """
  Compute per-rating counts for a user's library, optionally filtered by status or shelf.

  Returns a 10-element integer list (buckets 0.5..5.0), same format as `User.vn_ratings_dist`.
  """
  def library_ratings_dist(user_id, args \\ %{}, opts \\ []) do
    status = Map.get(args, :status)
    shelf_slug = Map.get(args, :shelf_slug)
    allowed = Keyword.get(opts, :allowed_categories)

    # Group by integer bucket index (round(rating * 2) - 1) to avoid float key comparison
    counts =
      Rating
      |> join(:inner, [r], rs in ReadingStatus,
        on: rs.visual_novel_id == r.visual_novel_id and rs.user_id == r.user_id
      )
      |> where([r, _rs], r.user_id == ^user_id)
      |> maybe_filter_rating_category(allowed)
      |> maybe_scope_dist_to_shelf(user_id, shelf_slug)
      |> maybe_filter_status(status)
      |> group_by([r], fragment("round(?::numeric * 2) - 1", r.rating))
      |> select([r], {fragment("(round(?::numeric * 2) - 1)::integer", r.rating), count(r.id)})
      |> Repo.all()
      |> Map.new()

    # Build 10-bucket array [count_0.5, count_1.0, ..., count_5.0]
    for i <- 0..9 do
      Map.get(counts, i, 0)
    end
  end

  @doc """
  Compute per-length-bucket counts for a user's library, optionally filtered by status or shelf.

  Returns a map of %{"very_short" => n, "short" => n, "medium" => n, "long" => n, "very_long" => n}
  based on VN length_minutes: <2h, 2-10h, 10-30h, 30-50h, 50h+.
  VNs with no length data are excluded.
  """
  def library_length_dist(user_id, args \\ %{}, opts \\ []) do
    status = Map.get(args, :status)
    shelf_slug = Map.get(args, :shelf_slug)
    allowed = Keyword.get(opts, :allowed_categories)

    rows =
      ReadingStatus
      |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
      |> where([rs, _vn], rs.user_id == ^user_id)
      |> where([_rs, vn], not is_nil(vn.length_minutes))
      |> maybe_filter_dist_category(allowed)
      |> maybe_scope_dist_to_shelf(user_id, shelf_slug)
      |> filter_dist_status(status)
      |> group_by(
        [_rs, vn],
        fragment(
          @length_bucket_sql,
          vn.length_minutes,
          vn.length_minutes,
          vn.length_minutes,
          vn.length_minutes
        )
      )
      |> select(
        [rs, vn],
        {fragment(
           @length_bucket_sql,
           vn.length_minutes,
           vn.length_minutes,
           vn.length_minutes,
           vn.length_minutes
         ), count(rs.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      "very_short" => Map.get(rows, "very_short", 0),
      "short" => Map.get(rows, "short", 0),
      "medium" => Map.get(rows, "medium", 0),
      "long" => Map.get(rows, "long", 0),
      "very_long" => Map.get(rows, "very_long", 0)
    }
  end

  @doc """
  Age rating distribution for a user's library VNs.
  Buckets by `min_age`: all_ages (0/nil), 13+ (12–15), 16+ (16–17), 18+ (18+).
  VNs with no `min_age` are excluded.
  """
  def library_age_rating_dist(user_id, args \\ %{}, opts \\ []) do
    status = Map.get(args, :status)
    allowed = Keyword.get(opts, :allowed_categories)

    rows =
      ReadingStatus
      |> join(:inner, [rs], vn in VisualNovel, on: vn.id == rs.visual_novel_id)
      |> where([rs, _vn], rs.user_id == ^user_id)
      |> where([_rs, vn], not is_nil(vn.min_age))
      |> maybe_filter_dist_category(allowed)
      |> filter_dist_status(status)
      |> group_by(
        [_rs, vn],
        fragment(@age_bucket_sql, vn.min_age, vn.min_age, vn.min_age)
      )
      |> select(
        [rs, vn],
        {fragment(@age_bucket_sql, vn.min_age, vn.min_age, vn.min_age), count(rs.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      "all_ages" => Map.get(rows, "all_ages", 0),
      "13+" => Map.get(rows, "13+", 0),
      "16+" => Map.get(rows, "16+", 0),
      "18+" => Map.get(rows, "18+", 0)
    }
  end

  # ============================================================================
  # Query builder
  # ============================================================================

  defp list_library_pairs(
         user_id,
         %{page: page, page_size: page_size, shelf_slug: shelf_slug, sort_by: sort_by} = args
       )
       when not is_nil(shelf_slug) do
    with {:ok, %Shelf{vns_count: total} = shelf} <-
           Shelves.get_shelf_by_slug_for_user(user_id, shelf_slug) do
      query =
        shelf
        |> Ecto.assoc(:visual_novels)
        |> join(:left, [vn], rs in assoc(vn, :reading_statuses),
          as: :reading_status,
          on: rs.user_id == ^user_id
        )
        |> apply_filters(user_id, args)
        |> apply_sort(sort_by, nil)
        |> select([vn, reading_status: rs], {vn, rs})

      # When any filter narrows the set, total differs from shelf.vns_count
      effective_total =
        if has_narrowing_filters?(args), do: Repo.aggregate(query, :count, :id), else: total

      query
      |> paginate_and_hydrate(user_id, page, page_size, effective_total)
    end
  end

  defp list_library_pairs(
         user_id,
         %{page: page, page_size: page_size, sort_by: sort_by} = args
       ) do
    status = Map.get(args, :status)

    base_q =
      VisualNovel
      |> join(:inner, [vn], rs in assoc(vn, :reading_statuses),
        as: :reading_status,
        on: rs.user_id == ^user_id
      )
      |> apply_filters(user_id, args)
      |> maybe_filter_status(status)
      |> apply_sort(sort_by, status)
      |> select([vn, reading_status: rs], {vn, rs})

    # Count is lazy — only runs if the client selects totalCount/totalPages.
    base_q
    |> paginate_and_hydrate(user_id, page, page_size)
  end

  # Shared filter ladder for both list clauses. The two clauses differ only in
  # their base query/join, the status filter (shelf branch omits it), and the
  # sort. `maybe_join_user_rating` MUST run before `maybe_filter_rating` because
  # the latter references the `:user_rating` named binding.
  defp apply_filters(query, user_id, args) do
    sort_by = Map.get(args, :sort_by)
    rating = Map.get(args, :rating)

    query
    |> maybe_filter_category(Map.get(args, :allowed_categories))
    |> maybe_join_user_rating(sort_by, rating, user_id)
    |> maybe_search(Map.get(args, :search))
    |> maybe_filter_rating(rating)
    |> maybe_filter_tag_slug(Map.get(args, :tag_slug))
    |> maybe_filter_producer_slug(Map.get(args, :producer_slug))
    |> maybe_filter_original_language(Map.get(args, :original_language))
    |> maybe_filter_read_year(Map.get(args, :read_year))
    |> maybe_filter_release_year(Map.get(args, :release_year))
    |> maybe_filter_length_category(Map.get(args, :length_category))
    |> maybe_filter_age_rating(Map.get(args, :age_rating))
  end

  # True when any narrowing filter is set, meaning the shelf's cached
  # `vns_count` no longer reflects the filtered result size.
  defp has_narrowing_filters?(args) do
    present?(Map.get(args, :search)) or not is_nil(Map.get(args, :rating)) or
      not is_nil(Map.get(args, :allowed_categories)) or
      not is_nil(Map.get(args, :read_year)) or not is_nil(Map.get(args, :release_year)) or
      Enum.any?(
        [:tag_slug, :producer_slug, :original_language, :length_category, :age_rating],
        &present?(Map.get(args, &1))
      )
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp paginate_and_hydrate(query, user_id, page, page_size, total \\ nil) do
    {pairs, pagination} = Pagination.paginate(query, page, page_size, total)

    entries =
      for {vn, rs} <- pairs do
        %{
          visual_novel: vn,
          reading_status: rs,
          user_id: user_id
        }
      end

    {:ok, {entries, pagination}}
  end

  # nil = no filtering (own library), list = filter by viewer's allowed categories
  # For queries starting from VisualNovel
  defp maybe_filter_category(query, nil), do: query

  defp maybe_filter_category(query, allowed),
    do: where(query, [vn], vn.title_category in ^allowed)

  # For queries starting from ReadingStatus (needs join to VN)
  defp maybe_filter_category_via_join(query, nil), do: query

  defp maybe_filter_category_via_join(query, allowed) do
    from rs in query,
      join: vn in VisualNovel,
      on: vn.id == rs.visual_novel_id,
      where: vn.title_category in ^allowed
  end

  # For queries starting from Rating (needs join to VN)
  defp maybe_filter_rating_category(query, nil), do: query

  defp maybe_filter_rating_category(query, allowed) do
    from r in query,
      join: vn in VisualNovel,
      on: vn.id == r.visual_novel_id,
      where: vn.title_category in ^allowed
  end

  # For distribution queries where VN is the second binding ([_rs, vn]).
  defp maybe_filter_dist_category(query, nil), do: query

  defp maybe_filter_dist_category(query, allowed),
    do: where(query, [_rs, vn], vn.title_category in ^allowed)

  # Status filter for distribution queries where ReadingStatus is the first
  # binding ([rs, _vn]). nil status excludes not_interested.
  defp filter_dist_status(query, nil),
    do: where(query, [rs, _vn], rs.status != :not_interested)

  defp filter_dist_status(query, status),
    do: where(query, [rs, _vn], rs.status == ^status)

  # Scope a distribution query to a custom shelf. Works for any query whose
  # first binding carries `visual_novel_id` (Rating or ReadingStatus). An
  # unresolvable shelf yields an empty result.
  defp maybe_scope_dist_to_shelf(query, user_id, shelf_slug)
       when is_binary(shelf_slug) and shelf_slug != "" do
    case Shelves.get_shelf_by_slug_for_user(user_id, shelf_slug) do
      {:ok, shelf} ->
        join(query, :inner, [x], si in ShelfItem,
          on: si.visual_novel_id == x.visual_novel_id and si.shelf_id == ^shelf.id
        )

      _ ->
        where(query, false)
    end
  end

  defp maybe_scope_dist_to_shelf(query, _user_id, _shelf_slug), do: query

  defp maybe_search(query, term) when term in [nil, ""], do: query

  defp maybe_search(query, term) do
    pattern = "%#{term}%"
    where(query, [vn, _], ilike(vn.title, ^pattern))
  end

  defp maybe_filter_status(query, nil), do: where(query, [_, rs], rs.status != :not_interested)
  defp maybe_filter_status(query, status), do: where(query, [_, rs], rs.status == ^status)

  @doc "Returns tags present in a user's library with VN counts, ordered by count desc."
  def library_tags(user_id, search \\ nil) do
    from(rs in ReadingStatus,
      join: vt in "vn_tags",
      on:
        vt.visual_novel_id == rs.visual_novel_id and
          vt.relevance_score >= ^@tag_relevance_threshold,
      join: t in "tags",
      on: t.id == vt.tag_id,
      where: rs.user_id == ^user_id and rs.status != :not_interested,
      group_by: [vt.tag_id, t.name, t.slug],
      order_by: [desc: count(vt.visual_novel_id)],
      limit: 50,
      select: %{tag_name: t.name, tag_slug: t.slug, count: count(vt.visual_novel_id)}
    )
    |> maybe_search_tag(search)
    |> Repo.all()
  end

  defp maybe_search_tag(query, term) when term in [nil, ""], do: query

  defp maybe_search_tag(query, term) do
    pattern = "%#{term}%"
    where(query, [_rs, _vt, t], ilike(t.name, ^pattern))
  end

  defp maybe_filter_tag_slug(query, slug) when is_binary(slug) and slug != "" do
    tag_id_q = from(t in "tags", where: t.slug == ^slug, select: t.id)

    vn_ids_q =
      from vt in "vn_tags",
        where:
          vt.tag_id in subquery(tag_id_q) and vt.relevance_score >= ^@tag_relevance_threshold,
        select: vt.visual_novel_id

    where(query, [vn], vn.id in subquery(vn_ids_q))
  end

  defp maybe_filter_tag_slug(query, _), do: query

  defp maybe_filter_producer_slug(query, slug) when is_binary(slug) and slug != "" do
    producer_id_q = from(p in "producers", where: p.slug == ^slug, select: p.id)

    # Match the `select_primary` logic used by the VN page and stats: only keep
    # developers from the earliest release for each VN. Ties (multiple devs at
    # the same earliest date) are all kept; if every developer's date is NULL,
    # all are kept too.
    #
    # Implementation note: the original was a correlated `MIN()` subquery
    # evaluated once per candidate VN. For producers with hundreds of dev
    # credits (e.g. `appetite` = 303 VNs) that ballooned to ~95ms. The
    # `RANK() ... NULLS LAST` window function does the same job in one pass
    # over a pre-narrowed scope (~3.5ms — verified via EXPLAIN ANALYZE).
    #
    # NULL semantics with `NULLS LAST` match the original `IS NOT DISTINCT FROM
    # MIN()`:
    #   - mixed dates: only the earliest non-NULL devs get rank=1
    #   - all NULL:    every dev ties at rank=1 → kept
    #   - tied dates:  every dev at the earliest date ties at rank=1 → kept
    candidate_vn_ids_q =
      from vp_t in "vn_producers",
        where:
          vp_t.producer_id in subquery(producer_id_q) and
            vp_t.role in ["developer", "developer_publisher"],
        select: vp_t.visual_novel_id

    ranked_q =
      from vp in "vn_producers",
        where:
          vp.role in ["developer", "developer_publisher"] and
            vp.visual_novel_id in subquery(candidate_vn_ids_q),
        select: %{
          visual_novel_id: vp.visual_novel_id,
          producer_id: vp.producer_id,
          rk:
            fragment(
              "RANK() OVER (PARTITION BY ? ORDER BY ? NULLS LAST)",
              vp.visual_novel_id,
              vp.earliest_release_date
            )
        }

    vn_ids_q =
      from r in subquery(ranked_q),
        where: r.rk == 1 and r.producer_id in subquery(producer_id_q),
        select: r.visual_novel_id

    where(query, [vn], vn.id in subquery(vn_ids_q))
  end

  defp maybe_filter_producer_slug(query, _), do: query

  defp maybe_filter_original_language(query, lang) when is_binary(lang) and lang != "" do
    where(query, [vn], vn.original_language == ^lang)
  end

  defp maybe_filter_original_language(query, _), do: query

  defp maybe_filter_read_year(query, nil), do: query

  defp maybe_filter_read_year(query, year) when is_integer(year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year + 1, 1, 1)

    where(
      query,
      [_vn, rs],
      rs.date_finished >= ^start_date and rs.date_finished < ^end_date
    )
  end

  defp maybe_filter_release_year(query, nil), do: query

  defp maybe_filter_release_year(query, year) when is_integer(year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year + 1, 1, 1)
    where(query, [vn], vn.release_date >= ^start_date and vn.release_date < ^end_date)
  end

  defp maybe_filter_length_category(query, nil), do: query
  defp maybe_filter_length_category(query, ""), do: query

  defp maybe_filter_length_category(query, category) when is_binary(category) do
    {min_mins, max_mins} = length_category_range(category)

    query
    |> where([vn], not is_nil(vn.length_minutes))
    |> where([vn], vn.length_minutes >= ^min_mins and vn.length_minutes < ^max_mins)
  end

  # Same ranges as library_length_dist histogram bucketing
  defp length_category_range("very_short"), do: {0, 120}
  defp length_category_range("short"), do: {120, 600}
  defp length_category_range("medium"), do: {600, 1800}
  defp length_category_range("long"), do: {1800, 3000}
  defp length_category_range("very_long"), do: {3000, 999_999}
  defp length_category_range(_), do: {0, 999_999}

  defp maybe_filter_age_rating(query, nil), do: query
  defp maybe_filter_age_rating(query, ""), do: query

  defp maybe_filter_age_rating(query, "unknown") do
    where(query, [vn], is_nil(vn.min_age))
  end

  defp maybe_filter_age_rating(query, bucket) when is_binary(bucket) do
    {min_age, max_age} = age_rating_range(bucket)

    where(
      query,
      [vn],
      not is_nil(vn.min_age) and vn.min_age >= ^min_age and vn.min_age < ^max_age
    )
  end

  defp age_rating_range("all_ages"), do: {0, 12}
  defp age_rating_range("13+"), do: {12, 16}
  defp age_rating_range("16+"), do: {16, 18}
  defp age_rating_range("18+"), do: {18, 999}
  defp age_rating_range(_), do: {0, 999}

  defp maybe_filter_rating(query, nil), do: query
  defp maybe_filter_rating(query, rating), do: where(query, [user_rating: r], r.rating == ^rating)

  # Sort selection
  defp apply_sort(query, nil, status), do: default_sort(query, status)
  defp apply_sort(query, sort_by, _status), do: custom_sort(query, sort_by)

  defp default_sort(query, :read) do
    order_by(query, [reading_status: rs], desc_nulls_last: rs.date_finished)
  end

  defp default_sort(query, _status) do
    order_by(query, [reading_status: rs], desc: rs.library_added_at)
  end

  defp custom_sort(query, sort_by) when sort_by in [:my_rating_asc, :my_rating_desc] do
    dir = if sort_by == :my_rating_asc, do: :asc, else: :desc_nulls_last
    order_by(query, [user_rating: r], [{^dir, r.rating}])
  end

  defp custom_sort(query, :average_rating_asc), do: order_by(query, [vn], asc: vn.average_rating)

  defp custom_sort(query, :average_rating_desc),
    do: order_by(query, [vn], desc: vn.average_rating)

  defp custom_sort(query, :total_ratings_asc), do: order_by(query, [vn], asc: vn.ratings_count)
  defp custom_sort(query, :total_ratings_desc), do: order_by(query, [vn], desc: vn.ratings_count)
  defp custom_sort(query, :release_date_asc), do: order_by(query, [vn], asc: vn.release_date)

  defp custom_sort(query, :release_date_desc),
    do: order_by(query, [vn], desc_nulls_last: vn.release_date)

  defp custom_sort(query, :date_added_asc),
    do: order_by(query, [reading_status: rs], asc: rs.library_added_at)

  defp custom_sort(query, :date_added_desc),
    do: order_by(query, [reading_status: rs], desc: rs.library_added_at)

  defp custom_sort(query, :date_finished_asc),
    do: order_by(query, [reading_status: rs], asc_nulls_last: rs.date_finished)

  defp custom_sort(query, :date_finished_desc),
    do: order_by(query, [reading_status: rs], desc_nulls_last: rs.date_finished)

  defp custom_sort(query, _), do: order_by(query, [reading_status: rs], desc: rs.library_added_at)

  defp maybe_join_user_rating(query, sort_by, _rating, user_id)
       when sort_by in [:my_rating_asc, :my_rating_desc] do
    join(query, :left, [vn, rs], r in Rating,
      on: r.visual_novel_id == vn.id and r.user_id == ^user_id,
      as: :user_rating
    )
  end

  defp maybe_join_user_rating(query, _sort_by, rating, user_id)
       when not is_nil(rating) do
    join(query, :inner, [vn, rs], r in Rating,
      on: r.visual_novel_id == vn.id and r.user_id == ^user_id,
      as: :user_rating
    )
  end

  defp maybe_join_user_rating(query, _sort_by, _rating, _user_id), do: query

  # ============================================================================
  # Batch-friendly hydration
  # ============================================================================

  @doc "Batch: returns %{vn_id => rating_float} for the given user + VN IDs."
  def batch_ratings_for_user(user_id, vn_ids) do
    vn_ids = Enum.uniq(vn_ids)

    Rating
    |> where([r], r.user_id == ^user_id and r.visual_novel_id in ^vn_ids)
    |> Repo.all()
    |> Map.new(&{&1.visual_novel_id, &1.rating})
  end

  @doc "Batch: returns %{vn_id => %Review{}} for the given user + VN IDs."
  def batch_reviews_for_user(user_id, vn_ids) do
    vn_ids = Enum.uniq(vn_ids)

    Review
    |> where([r], r.user_id == ^user_id and r.visual_novel_id in ^vn_ids)
    |> Repo.all()
    |> Map.new(&{&1.visual_novel_id, &1})
  end

  @doc "Batch: returns %{vn_id => %ReadingStatus{}} for the given user + VN IDs."
  def batch_reading_statuses_for_user(user_id, vn_ids) do
    vn_ids = Enum.uniq(vn_ids)

    ReadingStatus
    |> where([rs], rs.user_id == ^user_id and rs.visual_novel_id in ^vn_ids)
    |> Repo.all()
    |> Map.new(&{&1.visual_novel_id, &1})
  end

  @doc "Batch: returns %{vn_id => [%Shelf{}, ...]} for the given user + VN IDs."
  def batch_shelves_for_user(user_id, vn_ids) do
    vn_ids = Enum.uniq(vn_ids)

    Shelf
    |> join(:inner, [s], si in ShelfItem, on: si.shelf_id == s.id)
    |> where([s, si], s.user_id == ^user_id and si.visual_novel_id in ^vn_ids)
    |> select([s, si], {si.visual_novel_id, s})
    |> Repo.all()
    |> Enum.group_by(fn {vn_id, _} -> vn_id end, fn {_, shelf} -> shelf end)
  end
end

defmodule Kaguya.VisualNovels.Browse do
  @moduledoc """
  Query boundary for the public `/browse` surface.

  The shape lives in the context layer so LiveView and other callers can use
  the same browse query boundary.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel

  @tag_relevance_threshold 0.72
  @max_pages 10

  @cacheable_filter_keys [
    :include_tags,
    :exclude_tags,
    :development_status,
    :length_category,
    :original_languages,
    :available_languages,
    :available_platforms,
    :engines,
    :vndb_rating_gte,
    :vndb_rating_lte,
    :average_rating_gte,
    :average_rating_lte,
    :ratings_count_gte,
    :ratings_count_lte,
    :released_after_year,
    :released_before_year,
    :include_nukige,
    :include_adjacent,
    :has_ero,
    :available_on_stores,
    :free_on_stores,
    :is_avn
  ]

  @doc """
  Lists visual novels for browse grids and explore rows.

  Options:

    * `:page` - 1-based page, capped by callers to product limits.
    * `:page_size` - capped at 100.
    * `:sort_by` - one of the VN browse sort atoms.
    * `:filters` - atom-keyed browse filters.
  """
  def list(opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 20) |> min(100) |> max(1)
    sort_by = Keyword.get(opts, :sort_by)
    filters = Keyword.get(opts, :filters, %{}) || %{}

    cache_key = browse_cache_key(filters, sort_by, page, page_size)

    case Cachex.fetch(:vn_browse_cache, cache_key, fn ->
           {:commit, run_browse_query(page, page_size, sort_by, filters)}
         end) do
      {:ok, result} -> result
      {:commit, result} -> result
      _ -> run_browse_query(page, page_size, sort_by, filters)
    end
  end

  defp browse_cache_key(filters, sort_by, page, page_size) do
    filter_hash = filters |> normalize_filters() |> :erlang.phash2()
    {:vn_browse, filter_hash, sort_by || :default, page, page_size}
  end

  defp normalize_filters(filters) do
    filters
    |> Map.take(@cacheable_filter_keys)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
    |> Enum.sort()
  end

  defp run_browse_query(page, page_size, sort_by, filters) do
    include_tags = Map.get(filters, :include_tags, []) || []
    offset = (page - 1) * page_size

    effective_sort_by =
      if is_nil(sort_by) and include_tags != [], do: :relevance_desc, else: sort_by

    filters =
      if effective_sort_by == :relevance_desc do
        current = Map.get(filters, :ratings_count_gte) || 0
        Map.put(filters, :ratings_count_gte, max(current, 1))
      else
        filters
      end

    query =
      VisualNovel
      |> from(as: :vn)
      |> where([vn], is_nil(vn.hidden_at))
      |> apply_vn_filters_with_relevance(filters, effective_sort_by)
      |> apply_sort_with_relevance(effective_sort_by, include_tags)

    max_count = @max_pages * page_size + 1
    total = fast_count(filters, max_count)

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      items: items,
      pagination: %{
        page: page,
        page_size: page_size,
        total_pages: min(@max_pages, max(1, ceil(total / page_size))),
        total_count: total
      }
    }
  end

  defp fast_count(filters, max_count) when map_size(filters) == 0 do
    from(v in VisualNovel, where: is_nil(v.hidden_at), select: v.id)
    |> filter_by_title_category(filters)
    |> limited_count(max_count)
  end

  defp fast_count(filters, max_count) do
    min_ratings = filters[:ratings_count_gte]

    has_non_tag_filters? =
      not is_nil(filters[:average_rating_gte]) or
        not is_nil(filters[:average_rating_lte]) or
        not is_nil(filters[:ratings_count_lte]) or
        not is_nil(filters[:released_after_year]) or
        not is_nil(filters[:released_before_year]) or
        not is_nil(filters[:vndb_rating_gte]) or
        not is_nil(filters[:vndb_rating_lte]) or
        not is_nil(filters[:development_status]) or
        not is_nil(filters[:length_category]) or
        not is_nil(filters[:original_languages]) or
        not is_nil(filters[:available_languages]) or
        not is_nil(filters[:available_platforms]) or
        not is_nil(filters[:engines]) or
        not is_nil(filters[:has_ero]) or
        not is_nil(filters[:available_on_stores]) or
        not is_nil(filters[:free_on_stores]) or
        not is_nil(filters[:is_avn])

    inc_slugs = Enum.uniq(filters[:include_tags] || [])
    exc_slugs = Enum.uniq(filters[:exclude_tags] || [])

    cond do
      not has_non_tag_filters? and inc_slugs == [] and exc_slugs == [] ->
        from(v in VisualNovel, where: is_nil(v.hidden_at), select: v.id)
        |> filter_by_title_category(filters)
        |> filter_by_ratings_count(filters)
        |> limited_count(max_count)

      not has_non_tag_filters? ->
        fast_count_tags_only(inc_slugs, exc_slugs, max_count, min_ratings, filters)

      true ->
        VisualNovel
        |> from(as: :vn)
        |> where([vn], is_nil(vn.hidden_at))
        |> filter_by_title_category(filters)
        |> filter_by_development_status(filters)
        |> filter_by_length_category(filters)
        |> filter_by_language(filters)
        |> filter_by_vndb_rating(filters)
        |> filter_by_average_rating(filters)
        |> filter_by_ratings_count(filters)
        |> filter_by_release_year(filters)
        |> filter_by_available_languages(filters)
        |> filter_by_available_platforms(filters)
        |> filter_by_engines(filters)
        |> filter_by_has_ero(filters)
        |> filter_by_is_avn(filters)
        |> filter_by_available_stores(filters)
        |> filter_by_free_on_stores(filters)
        |> filter_include_tags_for_count(inc_slugs)
        |> filter_exclude_tags_for_count(exc_slugs)
        |> select([vn], vn.id)
        |> limited_count(max_count)
    end
  end

  defp limited_count(query, max_count) do
    from(sub in subquery(query |> limit(^max_count)), select: count())
    |> Repo.one()
  end

  defp fast_count_tags_only([], [], max_count, _min_ratings, filters) do
    from(v in VisualNovel, where: is_nil(v.hidden_at), select: v.id)
    |> filter_by_title_category(filters)
    |> filter_by_ratings_count(filters)
    |> limited_count(max_count)
  end

  defp fast_count_tags_only(inc_slugs, [], max_count, min_ratings, filters)
       when inc_slugs != [] do
    tag_ids_q = from(t in "tags", where: t.slug in ^inc_slugs, select: t.id)

    from(vt in "vn_tags",
      where:
        vt.tag_id in subquery(tag_ids_q) and
          vt.relevance_score >= ^@tag_relevance_threshold,
      group_by: vt.visual_novel_id,
      having: count(fragment("DISTINCT ?", vt.tag_id)) == ^length(inc_slugs),
      select: vt.visual_novel_id
    )
    |> maybe_filter_category(filters)
    |> maybe_filter_min_ratings(min_ratings)
    |> limited_count(max_count)
  end

  defp fast_count_tags_only([], exc_slugs, max_count, min_ratings, filters)
       when exc_slugs != [] do
    tag_ids_q = from(t in "tags", where: t.slug in ^exc_slugs, select: t.id)

    excluded_vns_q =
      from(vt in "vn_tags",
        where: vt.tag_id in subquery(tag_ids_q),
        select: vt.visual_novel_id,
        distinct: true
      )

    from(v in VisualNovel,
      where: v.id not in subquery(excluded_vns_q),
      where: is_nil(v.hidden_at),
      select: v.id
    )
    |> maybe_filter_category(filters)
    |> maybe_filter_min_ratings(min_ratings)
    |> limited_count(max_count)
  end

  defp fast_count_tags_only(inc_slugs, exc_slugs, max_count, min_ratings, filters) do
    tag_ids_inc_q = from(t in "tags", where: t.slug in ^inc_slugs, select: t.id)

    include_vns_q =
      from(vt in "vn_tags",
        where:
          vt.tag_id in subquery(tag_ids_inc_q) and
            vt.relevance_score >= ^@tag_relevance_threshold,
        group_by: vt.visual_novel_id,
        having: count(fragment("DISTINCT ?", vt.tag_id)) == ^length(inc_slugs),
        select: vt.visual_novel_id
      )

    tag_ids_exc_q = from(t in "tags", where: t.slug in ^exc_slugs, select: t.id)

    exclude_vns_q =
      from(vt in "vn_tags",
        where: vt.tag_id in subquery(tag_ids_exc_q),
        select: vt.visual_novel_id,
        distinct: true
      )

    from(iv in subquery(include_vns_q),
      left_join: ev in subquery(exclude_vns_q),
      on: ev.visual_novel_id == iv.visual_novel_id,
      where: is_nil(ev.visual_novel_id),
      select: iv.visual_novel_id
    )
    |> maybe_filter_category(filters)
    |> maybe_filter_min_ratings(min_ratings)
    |> limited_count(max_count)
  end

  defp filter_include_tags_for_count(query, []), do: query

  defp filter_include_tags_for_count(query, slugs) do
    tag_ids = cached_tag_ids(slugs)

    case length(tag_ids) do
      0 ->
        where(query, false)

      n ->
        ids_q =
          from(vt in "vn_tags",
            where: vt.tag_id in ^tag_ids and vt.relevance_score >= ^@tag_relevance_threshold,
            group_by: vt.visual_novel_id,
            having: count(fragment("DISTINCT ?", vt.tag_id)) == ^n,
            select: vt.visual_novel_id
          )

        where(query, [vn], vn.id in subquery(ids_q))
    end
  end

  defp filter_exclude_tags_for_count(query, []), do: query

  defp filter_exclude_tags_for_count(query, slugs) do
    tag_ids_q = from(t in "tags", where: t.slug in ^slugs, select: t.id)

    where(
      query,
      [vn],
      not exists(
        from(vt in "vn_tags",
          where: vt.visual_novel_id == parent_as(:vn).id and vt.tag_id in subquery(tag_ids_q),
          select: 1
        )
      )
    )
  end

  defp apply_vn_filters_with_relevance(query, filters, _sort_by) when map_size(filters) == 0 do
    filter_by_title_category(query, filters)
  end

  defp apply_vn_filters_with_relevance(query, filters, sort_by) do
    include_tags = Map.get(filters, :include_tags, []) || []

    query
    |> filter_by_title_category(filters)
    |> filter_by_development_status(filters)
    |> filter_by_length_category(filters)
    |> filter_by_language(filters)
    |> filter_by_has_ero(filters)
    |> filter_by_is_avn(filters)
    |> filter_by_vndb_rating(filters)
    |> filter_by_average_rating(filters)
    |> filter_by_ratings_count(filters)
    |> filter_by_release_year(filters)
    |> filter_by_available_languages(filters)
    |> filter_by_available_platforms(filters)
    |> filter_by_engines(filters)
    |> filter_by_available_stores(filters)
    |> filter_by_free_on_stores(filters)
    |> filter_include_tags_with_relevance(include_tags, sort_by)
    |> filter_by_exclude_tags(filters)
  end

  defp should_sort_by_relevance?(sort_by), do: sort_by == :relevance_desc

  defp filter_by_development_status(query, %{development_status: status}) when not is_nil(status),
    do: where(query, [vn], vn.development_status == ^status)

  defp filter_by_development_status(query, _), do: query

  defp filter_by_length_category(query, %{length_category: cat}) when not is_nil(cat),
    do: where(query, [vn], vn.length_category == ^cat)

  defp filter_by_length_category(query, _), do: query

  defp filter_by_language(query, %{original_languages: langs})
       when is_list(langs) and langs != [],
       do: where(query, [vn], vn.original_language in ^langs)

  defp filter_by_language(query, _), do: query

  defp filter_by_has_ero(query, %{has_ero: has_ero}) when is_boolean(has_ero),
    do: where(query, [vn], vn.has_ero == ^has_ero)

  defp filter_by_has_ero(query, _), do: query

  defp filter_by_is_avn(query, %{is_avn: is_avn}) when is_boolean(is_avn),
    do: where(query, [vn], vn.is_avn == ^is_avn)

  defp filter_by_is_avn(query, _), do: query

  defp filter_by_available_languages(query, %{available_languages: langs})
       when is_list(langs) and langs != [] do
    where(
      query,
      [vn],
      exists(
        from(vl in "vn_languages",
          where: vl.visual_novel_id == parent_as(:vn).id and vl.language in ^langs,
          select: 1
        )
      )
    )
  end

  defp filter_by_available_languages(query, _), do: query

  defp filter_by_available_platforms(query, %{available_platforms: plats})
       when is_list(plats) and plats != [] do
    where(
      query,
      [vn],
      exists(
        from(vp in "vn_platforms",
          where: vp.visual_novel_id == parent_as(:vn).id and vp.platform in ^plats,
          select: 1
        )
      )
    )
  end

  defp filter_by_available_platforms(query, _), do: query

  defp filter_by_engines(query, %{engines: engines}) when is_list(engines) and engines != [] do
    where(
      query,
      [vn],
      exists(
        from(ve in "vn_engines",
          where: ve.visual_novel_id == parent_as(:vn).id and ve.engine in ^engines,
          select: 1
        )
      )
    )
  end

  defp filter_by_engines(query, _), do: query

  defp filter_by_available_stores(query, %{available_on_stores: stores})
       when is_list(stores) and stores != [] do
    where(
      query,
      [vn],
      exists(
        from(rel in "vn_release_extlinks",
          join: vr in "vn_releases",
          on: vr.id == rel.vn_release_id,
          where:
            vr.visual_novel_id == parent_as(:vn).id and
              is_nil(vr.hidden_at) and
              rel.site in ^stores,
          select: 1
        )
      )
    )
  end

  defp filter_by_available_stores(query, _), do: query

  defp filter_by_free_on_stores(query, %{free_on_stores: stores})
       when is_list(stores) and stores != [] do
    where(
      query,
      [vn],
      exists(
        from(rel in "vn_release_extlinks",
          join: vr in "vn_releases",
          on: vr.id == rel.vn_release_id,
          where:
            vr.visual_novel_id == parent_as(:vn).id and
              vr.freeware == true and
              is_nil(vr.hidden_at) and
              rel.site in ^stores,
          select: 1
        )
      )
    )
  end

  defp filter_by_free_on_stores(query, _), do: query

  defp filter_by_vndb_rating(query, filters) do
    query
    |> maybe_filter(filters, :vndb_rating_gte, fn q, v -> where(q, [vn], vn.vndb_rating >= ^v) end)
    |> maybe_filter(filters, :vndb_rating_lte, fn q, v -> where(q, [vn], vn.vndb_rating <= ^v) end)
  end

  defp filter_by_average_rating(query, filters) do
    query
    |> maybe_filter(filters, :average_rating_gte, fn q, v ->
      where(q, [vn], vn.average_rating >= ^v)
    end)
    |> maybe_filter(filters, :average_rating_lte, fn q, v ->
      where(q, [vn], vn.average_rating <= ^v)
    end)
  end

  defp filter_by_ratings_count(query, filters) do
    query
    |> maybe_filter(filters, :ratings_count_gte, fn q, v ->
      where(q, [vn], vn.ratings_count >= ^v)
    end)
    |> maybe_filter(filters, :ratings_count_lte, fn q, v ->
      where(q, [vn], vn.ratings_count <= ^v)
    end)
  end

  defp filter_by_release_year(query, filters) do
    query
    |> maybe_filter(filters, :released_after_year, fn q, year ->
      where(q, [vn], vn.release_date >= ^Date.new!(year, 1, 1))
    end)
    |> maybe_filter(filters, :released_before_year, fn q, year ->
      where(q, [vn], vn.release_date <= ^Date.new!(year, 12, 31))
    end)
  end

  defp maybe_filter(query, filters, key, filter_fn) do
    case Map.get(filters, key) do
      nil -> query
      value -> filter_fn.(query, value)
    end
  end

  defp maybe_filter_category(query, filters) do
    allowed = allowed_categories(filters)

    if length(allowed) == 3 do
      query
    else
      from(vn in VisualNovel,
        where: vn.id in subquery(query) and vn.title_category in ^allowed,
        select: vn.id
      )
    end
  end

  defp maybe_filter_min_ratings(query, nil), do: query
  defp maybe_filter_min_ratings(query, min) when min <= 0, do: query

  defp maybe_filter_min_ratings(query, min) do
    from(vn in VisualNovel,
      where: vn.id in subquery(query) and vn.ratings_count >= ^min,
      select: vn.id
    )
  end

  defp cached_tag_ids(slugs) do
    cache_key = {:tag_slugs_to_ids, Enum.sort(slugs)}

    case Cachex.fetch(:kaguya_cache, cache_key, fn ->
           ids = from(t in "tags", where: t.slug in ^slugs, select: t.id) |> Repo.all()
           {:commit, ids, expire: :timer.hours(24)}
         end) do
      {:ok, ids} -> ids
      {:commit, ids} -> ids
      _ -> from(t in "tags", where: t.slug in ^slugs, select: t.id) |> Repo.all()
    end
  end

  defp filter_include_tags_with_relevance(query, nil, _sort_by), do: query
  defp filter_include_tags_with_relevance(query, [], _sort_by), do: query

  defp filter_include_tags_with_relevance(query, slugs, sort_by) when is_list(slugs) do
    slugs = Enum.uniq(slugs)
    tag_ids = cached_tag_ids(slugs)

    case {length(slugs), length(tag_ids)} do
      {_, 0} ->
        where(query, false)

      {1, 1} ->
        [tag_id] = tag_ids

        if should_sort_by_relevance?(sort_by) do
          from(vn in query,
            join: vt in "vn_tags",
            on:
              vt.visual_novel_id == vn.id and vt.tag_id == ^tag_id and
                vt.relevance_score >= ^@tag_relevance_threshold,
            as: :vt_relevance
          )
        else
          where(
            query,
            exists(
              from(vt in "vn_tags",
                where:
                  vt.visual_novel_id == parent_as(:vn).id and vt.tag_id == ^tag_id and
                    vt.relevance_score >= ^@tag_relevance_threshold,
                select: 1
              )
            )
          )
        end

      {n, _} when n > 1 ->
        n = length(tag_ids)

        if should_sort_by_relevance?(sort_by) do
          combined_q =
            from(vt in "vn_tags",
              where: vt.tag_id in ^tag_ids and vt.relevance_score >= ^@tag_relevance_threshold,
              group_by: vt.visual_novel_id,
              having: count(fragment("DISTINCT ?", vt.tag_id)) == ^n,
              select: %{
                visual_novel_id: vt.visual_novel_id,
                avg_relevance: avg(vt.relevance_score)
              }
            )

          from(vn in query,
            join: cr in subquery(combined_q),
            on: cr.visual_novel_id == vn.id,
            as: :combined_relevance
          )
        else
          ids_q =
            from(vt in "vn_tags",
              where: vt.tag_id in ^tag_ids and vt.relevance_score >= ^@tag_relevance_threshold,
              group_by: vt.visual_novel_id,
              having: count(fragment("DISTINCT ?", vt.tag_id)) == ^n,
              select: vt.visual_novel_id
            )

          where(query, [vn], vn.id in subquery(ids_q))
        end
    end
  end

  defp filter_by_exclude_tags(query, %{exclude_tags: slugs})
       when is_list(slugs) and slugs != [] do
    slugs = Enum.uniq(slugs)
    tag_ids_q = from(t in "tags", where: t.slug in ^slugs, select: t.id)

    where(
      query,
      not exists(
        from(vt in "vn_tags",
          where: vt.visual_novel_id == parent_as(:vn).id and vt.tag_id in subquery(tag_ids_q),
          select: 1
        )
      )
    )
  end

  defp filter_by_exclude_tags(query, _), do: query

  defp filter_by_title_category(query, filters) do
    allowed = allowed_categories(filters)

    if length(allowed) == 3 do
      query
    else
      where(query, [vn], vn.title_category in ^allowed)
    end
  end

  defp allowed_categories(filters) do
    [:vn]
    |> maybe_append(:nukige, Map.get(filters, :include_nukige, false))
    |> maybe_append(:adjacent, Map.get(filters, :include_adjacent, false))
  end

  defp maybe_append(list, value, true), do: list ++ [value]
  defp maybe_append(list, _value, _), do: list

  defp apply_sort_with_relevance(query, sort_by, include_tags) do
    cond do
      not should_sort_by_relevance?(sort_by) ->
        apply_sort(query, sort_by)

      include_tags == [] or include_tags == nil ->
        apply_sort(query, nil)

      Ecto.Query.has_named_binding?(query, :vt_relevance) ->
        from([vn, vt_relevance: vt] in query,
          order_by: [desc: vt.relevance_score, asc: fragment("-?", vn.ratings_count), asc: vn.id]
        )

      Ecto.Query.has_named_binding?(query, :combined_relevance) ->
        from([vn, combined_relevance: cr] in query,
          order_by: [desc: cr.avg_relevance, asc: fragment("-?", vn.ratings_count), asc: vn.id]
        )

      true ->
        apply_sort(query, sort_by)
    end
  end

  defp apply_sort(query, nil), do: order_by(query, [vn], desc: vn.average_rating)
  defp apply_sort(query, :average_rating_desc), do: order_by(query, [vn], desc: vn.average_rating)
  defp apply_sort(query, :average_rating_asc), do: order_by(query, [vn], asc: vn.average_rating)

  defp apply_sort(query, :total_ratings_desc),
    do: from(vn in query, order_by: [asc: fragment("-?", vn.ratings_count), asc: vn.id])

  defp apply_sort(query, :total_ratings_asc), do: order_by(query, [vn], asc: vn.ratings_count)
  defp apply_sort(query, :release_date_desc), do: order_by(query, [vn], desc: vn.release_date)
  defp apply_sort(query, :release_date_asc), do: order_by(query, [vn], asc: vn.release_date)
  defp apply_sort(query, _), do: order_by(query, [vn], desc: vn.average_rating)
end

defmodule Kaguya.Series do
  @moduledoc """
  Context for VN series operations.
  """

  @behaviour Kaguya.Revisions.EntityContext

  import Ecto.Query

  alias Kaguya.Pagination
  alias Kaguya.Producers.{Producer, VNProducer, VNSeriesProducer}
  alias Kaguya.Repo
  alias Kaguya.Revisions.Hist.{SeriesHist, SeriesItemHist, SeriesProducerHist}
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.SlugRedirects
  alias Kaguya.VisualNovels.{Series, VNSeriesItem, VisualNovel}

  @editable_groups ~w(general entries producers)
  @hist_fields [
    :name,
    :slug,
    :description,
    :hidden_at,
    :is_locked,
    :source,
    :manual_fields,
    :imported_root_visual_novel_id
  ]
  @field_groups %{
    "general" => [:name, :description],
    "entries" => [:entries],
    "producers" => [:producers],
    "moderation" => [:hidden_at, :is_locked]
  }

  # =============================================================================
  # Read Operations
  # =============================================================================

  def get_series(id, opts \\ []) do
    series_base_query(opts)
    |> where([s], s.id == ^id)
    |> Repo.one()
  end

  def get_series!(id, opts \\ []) do
    get_series(id, opts) || raise Ecto.NoResultsError, queryable: Series
  end

  def get_series_by_slug(slug, opts \\ []) when is_binary(slug) do
    query = series_base_query(opts)

    case Repo.one(from s in query, where: s.slug == ^slug) do
      nil ->
        case SlugRedirects.resolve(:series, slug) do
          nil -> nil
          id -> get_series(id, opts)
        end

      series ->
        series
    end
  end

  def get_series_by_slug!(slug, opts \\ []) do
    get_series_by_slug(slug, opts) || raise Ecto.NoResultsError, queryable: Series
  end

  @doc """
  Lists VNs for a series, ordered by position.
  Returns VNSeriesItem structs with :visual_novel preloaded.
  """
  def list_vns_for_series(%Series{} = series, %{page: page, page_size: page_size}) do
    query =
      from(item in VNSeriesItem,
        where: item.vn_series_id == ^series.id,
        join: vn in assoc(item, :visual_novel),
        order_by: [asc: item.position, asc: item.visual_novel_id],
        preload: [visual_novel: vn]
      )

    {items, pagination} = Pagination.paginate(query, page, page_size)
    {:ok, {items, pagination}}
  end

  def get_series_entry_count(series_id) do
    from(item in VNSeriesItem, where: item.vn_series_id == ^series_id)
    |> Repo.aggregate(:count)
  end

  def get_root_vn(series_id) do
    from(item in VNSeriesItem,
      where: item.vn_series_id == ^series_id,
      join: vn in assoc(item, :visual_novel),
      order_by: [asc: item.position, asc: item.visual_novel_id],
      limit: 1,
      select: vn
    )
    |> Repo.one()
  end

  def get_series_for_vn(vn_id) do
    from(vn in VisualNovel,
      where: vn.id == ^vn_id,
      join: s in assoc(vn, :primary_vn_series),
      where: is_nil(s.hidden_at),
      select: s
    )
    |> Repo.one()
  end

  def list_series_for_vn(vn_id) do
    from(item in VNSeriesItem,
      where: item.visual_novel_id == ^vn_id,
      join: s in assoc(item, :vn_series),
      where: is_nil(s.hidden_at),
      order_by: [asc: item.position, asc: s.name],
      select: %{series: s, position: item.position}
    )
    |> Repo.all()
  end

  def list_producers_for_series(series_id) do
    from(link in VNSeriesProducer,
      join: producer in assoc(link, :producer),
      where: link.vn_series_id == ^series_id,
      where: is_nil(producer.hidden_at),
      order_by: [asc: producer.name],
      select: %{producer: producer, role: link.role}
    )
    |> Repo.all()
  end

  def list_seeded_series do
    from(s in Series,
      where: s.source == :vndb_sync,
      preload: [vn_series_items: ^vn_series_items_preload_query(), series_producers: :producer]
    )
    |> Repo.all()
  end

  def create_seeded_series(attrs, opts \\ []) do
    normalized = Map.new(attrs)

    with {:ok, entries} <- normalize_entries(Map.get(normalized, :entries)),
         {:ok, producers} <- normalize_producers(Map.get(normalized, :producers, [])),
         {:ok, series} <-
           %Series{}
           |> Series.changeset(%{
             name: Map.get(normalized, :name),
             description: Map.get(normalized, :description),
             source: :vndb_sync,
             manual_fields: [],
             imported_root_visual_novel_id: Map.get(normalized, :imported_root_visual_novel_id)
           })
           |> Repo.insert(),
         :ok <- replace_entries(series, entries),
         :ok <- replace_producers(series, producers) do
      {:ok, maybe_reload_seeded_result(series, opts)}
    end
  end

  def sync_seeded_series(series, attrs, opts \\ []) do
    normalized = Map.new(attrs)
    current = series

    general_changed =
      "general" not in (current.manual_fields || []) and
        ((Map.has_key?(normalized, :name) and Map.get(normalized, :name) != current.name) or
           (Map.has_key?(normalized, :description) and
              Map.get(normalized, :description) != current.description))

    attrs_to_apply =
      %{imported_root_visual_novel_id: Map.get(normalized, :imported_root_visual_novel_id)}
      |> maybe_put_seeded_general(current, normalized)

    changed_fields = if general_changed, do: ["general"], else: []

    with {:ok, updated_series} <- current |> Series.changeset(attrs_to_apply) |> Repo.update(),
         {:ok, changed_fields} <-
           maybe_sync_seeded_entries(updated_series, normalized, changed_fields),
         {:ok, changed_fields} <-
           maybe_sync_seeded_producers(updated_series, normalized, changed_fields) do
      {:ok, maybe_reload_seeded_result(updated_series, opts), changed_fields}
    end
  end

  # =============================================================================
  # User Aggregation
  # =============================================================================

  def get_series_read_count(series_id, user_id) do
    from(item in VNSeriesItem,
      where: item.vn_series_id == ^series_id,
      join: status in ReadingStatus,
      on: status.visual_novel_id == item.visual_novel_id and status.user_id == ^user_id,
      where: status.status == :read,
      select: count()
    )
    |> Repo.one() || 0
  end

  def list_user_series(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    cursor = Keyword.get(opts, :cursor)
    sort_by = Keyword.get(opts, :sort_by, :recent)

    activity_query =
      from(item in VNSeriesItem,
        join: status in ReadingStatus,
        on: status.visual_novel_id == item.visual_novel_id and status.user_id == ^user_id,
        group_by: item.vn_series_id,
        select: %{
          vn_series_id: item.vn_series_id,
          read_count: count(fragment("CASE WHEN ? = 'read' THEN 1 END", status.status)),
          last_activity_at: max(status.updated_at)
        }
      )

    base_query =
      from(s in Series,
        join: a in subquery(activity_query),
        on: a.vn_series_id == s.id,
        join:
          total in subquery(
            from(i in VNSeriesItem,
              group_by: i.vn_series_id,
              select: %{vn_series_id: i.vn_series_id, total: count()}
            )
          ),
        on: total.vn_series_id == s.id,
        where: is_nil(s.hidden_at) and a.read_count > 0,
        select: %{
          series: s,
          read_count: a.read_count,
          total_count: total.total,
          last_activity_at: a.last_activity_at
        }
      )

    sorted_query =
      case sort_by do
        :recent -> from([_s, a, _t] in base_query, order_by: [desc: a.last_activity_at])
        :name -> from([s, _a, _t] in base_query, order_by: [asc: s.name])
        _ -> from([_s, a, _t] in base_query, order_by: [desc: a.last_activity_at])
      end

    paginated_query =
      if cursor do
        case decode_cursor(cursor) do
          {:ok, cursor_value} ->
            case sort_by do
              :recent ->
                from([_s, a, _t] in sorted_query, where: a.last_activity_at < ^cursor_value)

              _ ->
                sorted_query
            end

          _ ->
            sorted_query
        end
      else
        sorted_query
      end

    results = paginated_query |> limit(^(limit + 1)) |> Repo.all()

    has_next = length(results) > limit
    items = Enum.take(results, limit)

    next_cursor =
      if has_next and items != [] do
        items |> List.last() |> Map.fetch!(:last_activity_at) |> encode_cursor()
      end

    %{items: items, next_cursor: next_cursor, has_next: has_next}
  end

  # =============================================================================
  # Search
  # =============================================================================

  def search_series(query_string, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)
    normalized_query = String.downcase(String.trim(query_string))
    has_query = normalized_query != ""
    search_term = "%#{query_string}%"
    prefix_term = "#{normalized_query}%"

    series_stats =
      from(item in VNSeriesItem,
        join: vn in assoc(item, :visual_novel),
        group_by: item.vn_series_id,
        select: %{
          vn_series_id: item.vn_series_id,
          entry_count: count(),
          series_popularity:
            max(
              fragment(
                "GREATEST(COALESCE(?, 0), COALESCE(?, 0))",
                vn.ratings_count,
                vn.vndb_vote_count
              )
            ),
          avg_rating: avg(vn.average_rating)
        }
      )

    root_vn_data =
      from(item in VNSeriesItem,
        join: vn in assoc(item, :visual_novel),
        distinct: item.vn_series_id,
        order_by: [asc: item.vn_series_id, asc: item.position, asc: item.visual_novel_id],
        select: %{
          vn_series_id: item.vn_series_id,
          primary_image_url: vn.temp_image_url,
          root_cover_needs_blur:
            fragment(
              "COALESCE(?, false) OR COALESCE(?, false)",
              vn.is_image_nsfw,
              vn.is_image_suggestive
            ),
          root_has_ero:
            fragment(
              "COALESCE(?, false) OR COALESCE(?, false)",
              vn.is_image_nsfw,
              vn.is_image_suggestive
            ),
          root_average_rating: vn.average_rating,
          root_ratings_count: vn.ratings_count,
          root_vndb_vote_count: vn.vndb_vote_count
        }
      )

    query =
      from(s in Series,
        left_join: counts in subquery(series_stats),
        on: counts.vn_series_id == s.id,
        left_join: root in subquery(root_vn_data),
        on: root.vn_series_id == s.id,
        where: is_nil(s.hidden_at) and ilike(s.name, ^search_term),
        select_merge: %{
          entry_count: counts.entry_count,
          primary_image_url: root.primary_image_url,
          root_cover_needs_blur: root.root_cover_needs_blur,
          root_has_ero: root.root_has_ero
        },
        limit: ^page_size,
        offset: ^((page - 1) * page_size)
      )

    query =
      if has_query do
        from([s, counts, _root] in query,
          order_by: [
            asc:
              fragment(
                """
                CASE
                  WHEN lower(?) = ? THEN 0
                  WHEN lower(?) LIKE ? THEN 1
                  ELSE 2
                END
                """,
                s.name,
                ^normalized_query,
                s.name,
                ^prefix_term
              ),
            desc: fragment("COALESCE(?, 0)", counts.series_popularity),
            desc: fragment("COALESCE(?, 0)", counts.avg_rating),
            desc: counts.entry_count,
            asc: s.name
          ]
        )
      else
        from([s, counts, _root] in query,
          order_by: [
            desc: fragment("COALESCE(?, 0)", counts.series_popularity),
            desc: fragment("COALESCE(?, 0)", counts.avg_rating),
            desc: counts.entry_count,
            asc: s.name
          ]
        )
      end

    items = Repo.all(query) |> Repo.preload(series_producers: :producer)

    total =
      from(s in Series, where: is_nil(s.hidden_at) and ilike(s.name, ^search_term))
      |> Repo.aggregate(:count)

    %{
      items: items,
      pagination: %{
        page: page,
        page_size: page_size,
        total_count: total,
        total_pages: ceil(total / page_size)
      }
    }
  end

  # =============================================================================
  # Edit / Revision Support
  # =============================================================================

  def get_for_edit(id) do
    case Repo.get(Series, id) do
      nil -> nil
      series -> preload_for_edit(series)
    end
  end

  def batch_load_for_hist(ids) when is_list(ids) do
    from(s in Series, where: s.id in ^Enum.uniq(ids))
    |> Repo.all()
    |> Repo.preload(
      vn_series_items: vn_series_items_preload_query(),
      series_producers: :producer
    )
  end

  def create_from_edit(attrs) do
    normalized = Map.new(attrs)

    with {:ok, entries} <- normalize_entries(Map.get(normalized, :entries)),
         {:ok, producers} <- normalize_producers(Map.get(normalized, :producers, [])),
         {:ok, series} <-
           %Series{}
           |> Series.changeset(%{
             name: Map.get(normalized, :name),
             description: Map.get(normalized, :description),
             source: :user,
             manual_fields: @editable_groups
           })
           |> Repo.insert(),
         :ok <- replace_entries(series, entries),
         :ok <- replace_producers(series, producers) do
      {:ok, get_for_edit(series.id) || series}
    end
  end

  def apply_edit(series, changes) do
    normalized = Map.new(changes)
    attrs = build_edit_attrs(series, normalized)
    old_slug = series.slug

    with {:ok, updated_series} <- series |> Series.changeset(attrs) |> Repo.update(),
         :ok <- maybe_record_slug_redirect(old_slug, updated_series),
         :ok <- maybe_replace_entries(updated_series, normalized),
         :ok <- maybe_replace_producers(updated_series, normalized) do
      {:ok, get_for_edit(updated_series.id) || updated_series}
    end
  end

  def write_hist(change_id, series) do
    Repo.insert_all(SeriesHist, [series_hist_row(change_id, series)])

    item_rows =
      Enum.map(series.vn_series_items, fn item ->
        %{change_id: change_id, visual_novel_id: item.visual_novel_id, position: item.position}
      end)

    if item_rows != [], do: Repo.insert_all(SeriesItemHist, item_rows)

    producer_rows =
      Enum.map(series.series_producers, fn link ->
        %{change_id: change_id, producer_id: link.producer_id, role: link.role}
      end)

    if producer_rows != [], do: Repo.insert_all(SeriesProducerHist, producer_rows)
  end

  def bulk_write_hist([]), do: :ok

  def bulk_write_hist(pairs) when is_list(pairs) do
    main_rows =
      Enum.map(pairs, fn {change_id, series} ->
        series_hist_row(change_id, series)
      end)

    chunked_insert_all(SeriesHist, main_rows)

    item_rows =
      Enum.flat_map(pairs, fn {change_id, series} ->
        Enum.map(series.vn_series_items, fn item ->
          %{change_id: change_id, visual_novel_id: item.visual_novel_id, position: item.position}
        end)
      end)

    chunked_insert_all(SeriesItemHist, item_rows)

    producer_rows =
      Enum.flat_map(pairs, fn {change_id, series} ->
        Enum.map(series.series_producers, fn link ->
          %{change_id: change_id, producer_id: link.producer_id, role: link.role}
        end)
      end)

    chunked_insert_all(SeriesProducerHist, producer_rows)
    :ok
  end

  def load_hist(change_id) do
    hist = Repo.one(from h in SeriesHist, where: h.change_id == ^change_id)
    entries = load_hist_entries([change_id]) |> Map.get(change_id, [])
    producers = load_hist_producers([change_id]) |> Map.get(change_id, [])
    %{hist: hist, entries: entries, producers: producers}
  end

  def bulk_load_hist([]), do: %{}

  def bulk_load_hist(change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    hists =
      Repo.all(from h in SeriesHist, where: h.change_id in ^ids)
      |> Map.new(&{&1.change_id, &1})

    entries_by_change = load_hist_entries(ids)
    producers_by_change = load_hist_producers(ids)

    Map.new(ids, fn id ->
      {id,
       %{
         hist: Map.get(hists, id),
         entries: Map.get(entries_by_change, id, []),
         producers: Map.get(producers_by_change, id, [])
       }}
    end)
  end

  def apply_hist(series, hist_data) do
    attrs =
      (hist_data.hist || %{})
      |> Map.take(@hist_fields)
      |> normalize_hist_attrs()

    with {:ok, updated_series} <- updated_hist_series(series, attrs),
         :ok <- restore_hist_entries(updated_series, hist_data.entries || []),
         :ok <- restore_hist_producers(updated_series, hist_data.producers || []) do
      {:ok, get_for_edit(updated_series.id) || updated_series}
    end
  end

  def changed_field_groups(series, changes) do
    normalized = Map.new(changes)

    @field_groups
    |> Enum.filter(fn
      {"entries", _fields} ->
        Map.has_key?(normalized, :entries) and
          entries_changed?(series.vn_series_items, Map.get(normalized, :entries))

      {"producers", _fields} ->
        Map.has_key?(normalized, :producers) and
          producers_changed?(series.series_producers, Map.get(normalized, :producers))

      {_group, fields} ->
        Enum.any?(fields, fn field ->
          Map.has_key?(normalized, field) and Map.get(normalized, field) != Map.get(series, field)
        end)
    end)
    |> Enum.map(fn {group, _} -> group end)
    |> Enum.sort()
  end

  def reconcile_primary_series(vn_ids) when is_list(vn_ids) do
    ids = Enum.uniq(Enum.reject(vn_ids, &is_nil/1))
    if ids == [], do: :ok, else: do_reconcile_primary_series(ids)
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp series_base_query(opts) do
    if Keyword.get(opts, :include_hidden, false) do
      Series
    else
      from(s in Series, where: is_nil(s.hidden_at))
    end
  end

  defp preload_for_edit(series) do
    Repo.preload(series,
      vn_series_items: vn_series_items_preload_query(),
      series_producers: :producer
    )
  end

  defp vn_series_items_preload_query do
    from(item in VNSeriesItem,
      order_by: [asc: item.position, asc: item.visual_novel_id],
      preload: [:visual_novel]
    )
  end

  defp build_edit_attrs(series, changes) do
    groups = edited_groups(series, changes)

    changes
    |> Map.take([:name, :description])
    |> Map.put(:manual_fields, merge_manual_fields(series.manual_fields, groups))
  end

  defp edited_groups(series, changes) do
    groups = []

    groups =
      if (Map.has_key?(changes, :name) and Map.get(changes, :name) != series.name) or
           (Map.has_key?(changes, :description) and
              Map.get(changes, :description) != series.description) do
        ["general" | groups]
      else
        groups
      end

    groups =
      if Map.has_key?(changes, :entries) and
           entries_changed?(series.vn_series_items, Map.get(changes, :entries)) do
        ["entries" | groups]
      else
        groups
      end

    groups =
      if Map.has_key?(changes, :producers) and
           producers_changed?(series.series_producers, Map.get(changes, :producers)) do
        ["producers" | groups]
      else
        groups
      end

    groups |> Enum.uniq() |> Enum.sort()
  end

  defp merge_manual_fields(existing, groups) do
    ((existing || []) ++ groups)
    |> Enum.filter(&(&1 in @editable_groups))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp maybe_record_slug_redirect(old_slug, %{slug: new_slug, id: id})
       when is_binary(old_slug) and is_binary(new_slug) and old_slug != new_slug do
    case SlugRedirects.record(:series, old_slug, id) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_record_slug_redirect(_old_slug, _series), do: :ok

  defp maybe_reload_seeded_result(series, opts) do
    if Keyword.get(opts, :reload, true) do
      get_for_edit(series.id) || series
    else
      series
    end
  end

  defp maybe_put_seeded_general(attrs, series, changes) do
    if "general" in (series.manual_fields || []) do
      attrs
    else
      attrs
      |> maybe_put(:name, Map.get(changes, :name))
      |> maybe_put(:description, Map.get(changes, :description))
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_sync_seeded_entries(series, changes, changed_fields) do
    cond do
      not Map.has_key?(changes, :entries) ->
        {:ok, changed_fields}

      "entries" in (series.manual_fields || []) ->
        {:ok, changed_fields}

      true ->
        with {:ok, entries} <- normalize_entries(Map.get(changes, :entries)) do
          if entries_changed_normalized?(series.vn_series_items, entries) do
            :ok = replace_entries(series, entries)
            {:ok, Enum.sort(["entries" | changed_fields])}
          else
            {:ok, changed_fields}
          end
        end
    end
  end

  defp maybe_sync_seeded_producers(series, changes, changed_fields) do
    cond do
      not Map.has_key?(changes, :producers) ->
        {:ok, changed_fields}

      "producers" in (series.manual_fields || []) ->
        {:ok, changed_fields}

      true ->
        with {:ok, producers} <- normalize_producers(Map.get(changes, :producers)) do
          if producers_changed_normalized?(series.series_producers, producers) do
            :ok = replace_producers(series, producers)
            {:ok, Enum.sort(["producers" | changed_fields])}
          else
            {:ok, changed_fields}
          end
        end
    end
  end

  defp maybe_replace_entries(series, changes) do
    case Map.fetch(changes, :entries) do
      :error ->
        :ok

      {:ok, entries} ->
        with {:ok, normalized} <- normalize_entries(entries) do
          replace_entries(series, normalized)
        end
    end
  end

  defp maybe_replace_producers(series, changes) do
    case Map.fetch(changes, :producers) do
      :error ->
        :ok

      {:ok, producers} ->
        with {:ok, normalized} <- normalize_producers(producers) do
          replace_producers(series, normalized)
        end
    end
  end

  defp replace_entries(series, normalized_entries) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    old_items = Repo.all(from item in VNSeriesItem, where: item.vn_series_id == ^series.id)
    old_vn_ids = Enum.map(old_items, & &1.visual_novel_id)
    new_vn_ids = Enum.map(normalized_entries, & &1.visual_novel_id)
    affected_vn_ids = Enum.uniq(old_vn_ids ++ new_vn_ids)

    from(item in VNSeriesItem, where: item.vn_series_id == ^series.id)
    |> Repo.delete_all()

    rows =
      Enum.map(normalized_entries, fn entry ->
        %{
          vn_series_id: series.id,
          visual_novel_id: entry.visual_novel_id,
          position: entry.position,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(VNSeriesItem, rows)

    reconcile_primary_series(affected_vn_ids)
  end

  defp normalize_entries(entries) when is_list(entries) do
    parsed_entries = Enum.map(entries, &normalize_entry/1)

    normalized =
      parsed_entries
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn entry -> {entry.position, entry.visual_novel_id} end)

    cond do
      normalized == [] ->
        {:error, "Series must include at least one visual novel"}

      Enum.any?(parsed_entries, &is_nil/1) ->
        {:error, "Each series entry requires a visual novel and position"}

      Enum.uniq_by(normalized, & &1.visual_novel_id) |> length() != length(normalized) ->
        {:error, "A visual novel can only appear once in a series"}

      vn_count(normalized) != length(normalized) ->
        {:error, "One or more visual novels could not be found"}

      true ->
        {:ok, normalized}
    end
  end

  defp normalize_entries(_), do: {:error, "Series entries are required"}

  defp normalize_entry(entry) when is_map(entry) do
    vn_id = Map.get(entry, :visual_novel_id) || Map.get(entry, "visual_novel_id")
    position = Map.get(entry, :position) || Map.get(entry, "position")

    cond do
      not is_binary(vn_id) -> nil
      is_integer(position) -> %{visual_novel_id: vn_id, position: position * 1.0}
      is_float(position) -> %{visual_novel_id: vn_id, position: position}
      true -> nil
    end
  end

  defp normalize_entry(_), do: nil

  defp normalize_producers(producers) when is_list(producers) do
    parsed = Enum.map(producers, &normalize_producer/1)

    normalized =
      parsed
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn producer -> {producer.role, producer.producer_id} end)

    cond do
      Enum.any?(parsed, &is_nil/1) ->
        {:error, "Each producer entry requires a producer and role"}

      Enum.uniq_by(normalized, & &1.producer_id) |> length() != length(normalized) ->
        {:error, "A producer can only appear once in a series"}

      producer_count(normalized) != length(normalized) ->
        {:error, "One or more producers could not be found"}

      true ->
        {:ok, normalized}
    end
  end

  defp normalize_producers(_), do: {:error, "Invalid producer list"}

  defp normalize_producer(producer) when is_map(producer) do
    producer_id =
      Map.get(producer, :producer_id) ||
        Map.get(producer, "producer_id") ||
        Map.get(producer, :producerId) ||
        Map.get(producer, "producerId")

    role = Map.get(producer, :role) || Map.get(producer, "role")

    normalized_role =
      case role do
        "developer" -> "developer"
        "publisher" -> "publisher"
        "developer_publisher" -> "developer_publisher"
        "both" -> "developer_publisher"
        _ -> nil
      end

    if is_binary(producer_id) and is_binary(normalized_role) do
      %{producer_id: producer_id, role: normalized_role}
    end
  end

  defp normalize_producer(_), do: nil

  defp entries_changed?(existing_items, entries) do
    case normalize_entries(entries) do
      {:ok, normalized} ->
        entries_changed_normalized?(existing_items, normalized)

      _ ->
        true
    end
  end

  defp entries_changed_normalized?(existing_items, normalized_entries) do
    current =
      Enum.map(existing_items, &%{visual_novel_id: &1.visual_novel_id, position: &1.position})

    current != normalized_entries
  end

  defp producers_changed?(existing_links, producers) do
    case normalize_producers(producers) do
      {:ok, normalized} ->
        producers_changed_normalized?(existing_links, normalized)

      _ ->
        true
    end
  end

  defp producers_changed_normalized?(existing_links, normalized_producers) do
    current =
      existing_links
      |> Enum.map(&%{producer_id: &1.producer_id, role: &1.role})
      |> Enum.sort_by(fn producer -> {producer.role, producer.producer_id} end)

    current != normalized_producers
  end

  defp vn_count(entries) do
    ids = Enum.map(entries, & &1.visual_novel_id)

    from(v in VisualNovel, where: v.id in ^ids)
    |> Repo.aggregate(:count)
  end

  defp producer_count(producers) do
    ids = Enum.map(producers, & &1.producer_id)

    from(p in Producer, where: p.id in ^ids)
    |> Repo.aggregate(:count)
  end

  defp normalize_hist_attrs(attrs) do
    attrs
    |> Map.update(:source, nil, &normalize_source/1)
    |> Map.update(:manual_fields, [], &normalize_manual_fields/1)
  end

  defp updated_hist_series(series, attrs) do
    series
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  defp restore_hist_entries(series, entries) do
    normalized =
      entries
      |> Enum.map(fn entry ->
        %{visual_novel_id: Map.get(entry, :visual_novel_id), position: Map.get(entry, :position)}
      end)

    replace_entries(series, normalized)
  end

  defp restore_hist_producers(series, producers) do
    normalized =
      Enum.map(producers, fn producer ->
        %{producer_id: Map.get(producer, :producer_id), role: Map.get(producer, :role)}
      end)

    replace_producers(series, normalized)
  end

  defp load_hist_entries(change_ids) do
    ids = Enum.uniq(change_ids)

    title_map =
      Repo.all(
        from(item in SeriesItemHist,
          where: item.change_id in ^ids,
          select: item.visual_novel_id,
          distinct: true
        )
      )
      |> batch_load_vn_titles()

    Repo.all(
      from(item in SeriesItemHist,
        where: item.change_id in ^ids,
        order_by: [asc: item.change_id, asc: item.position, asc: item.visual_novel_id]
      )
    )
    |> Enum.group_by(& &1.change_id, fn item ->
      item
      |> Map.from_struct()
      |> Map.drop([:__meta__, :change])
      |> Map.put(:visual_novel_title, Map.get(title_map, item.visual_novel_id))
    end)
  end

  defp load_hist_producers(change_ids) do
    ids = Enum.uniq(change_ids)

    producer_names =
      Repo.all(
        from(link in SeriesProducerHist,
          join: producer in Producer,
          on: producer.id == link.producer_id,
          where: link.change_id in ^ids,
          select: {producer.id, producer.name}
        )
      )
      |> Map.new()

    Repo.all(
      from(link in SeriesProducerHist,
        where: link.change_id in ^ids,
        order_by: [asc: link.change_id, asc: link.role, asc: link.producer_id]
      )
    )
    |> Enum.group_by(& &1.change_id, fn link ->
      link
      |> Map.from_struct()
      |> Map.drop([:__meta__, :change])
      |> Map.put(:producer_name, Map.get(producer_names, link.producer_id))
    end)
  end

  defp replace_producers(series, normalized_producers) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(link in VNSeriesProducer, where: link.vn_series_id == ^series.id)
    |> Repo.delete_all()

    rows =
      Enum.map(normalized_producers, fn producer ->
        %{
          vn_series_id: series.id,
          producer_id: producer.producer_id,
          role: producer.role,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(VNSeriesProducer, rows)
    :ok
  end

  defp batch_load_vn_titles([]), do: %{}

  defp batch_load_vn_titles(ids) do
    from(v in VisualNovel, where: v.id in ^ids, select: {v.id, v.title})
    |> Repo.all()
    |> Map.new()
  end

  def producer_links_for_vns(vn_ids) when is_list(vn_ids) do
    ids = Enum.uniq(vn_ids)

    from(link in VNProducer,
      join: producer in assoc(link, :producer),
      where: link.visual_novel_id in ^ids,
      where: is_nil(producer.hidden_at),
      select: %{
        visual_novel_id: link.visual_novel_id,
        producer_id: link.producer_id,
        role: link.role,
        producer: producer
      }
    )
    |> Repo.all()
  end

  def suggested_producers_from_links(vn_ids, links) when is_list(vn_ids) and is_list(links) do
    ids = MapSet.new(vn_ids)
    min_coverage = max(1, trunc(Float.ceil(MapSet.size(ids) * 0.6)))

    links
    |> Enum.filter(&MapSet.member?(ids, &1.visual_novel_id))
    |> Enum.reduce(%{}, fn link, acc ->
      entry =
        Map.get(acc, link.producer_id, %{
          producer_id: link.producer_id,
          name: link.producer.name,
          count: 0,
          roles: MapSet.new()
        })

      Map.put(acc, link.producer_id, %{
        producer_id: link.producer_id,
        name: link.producer.name,
        count: entry.count + 1,
        roles: MapSet.put(entry.roles, link.role)
      })
    end)
    |> Map.values()
    |> Enum.filter(&(&1.count >= min_coverage))
    |> Enum.sort_by(fn entry ->
      {role_priority(entry.roles), -entry.count, entry.name}
    end)
    |> Enum.take(3)
    |> Enum.map(fn entry ->
      %{
        producer_id: entry.producer_id,
        role: merged_role(entry.roles)
      }
    end)
  end

  def suggested_producers_for_vns(vn_ids) when is_list(vn_ids) do
    vn_ids
    |> producer_links_for_vns()
    |> then(&suggested_producers_from_links(vn_ids, &1))
  end

  defp merged_role(roles) do
    cond do
      MapSet.member?(roles, "developer_publisher") ->
        "developer_publisher"

      MapSet.member?(roles, "developer") and MapSet.member?(roles, "publisher") ->
        "developer_publisher"

      MapSet.member?(roles, "developer") ->
        "developer"

      true ->
        "publisher"
    end
  end

  defp role_priority(roles) do
    cond do
      MapSet.member?(roles, "developer_publisher") -> 0
      MapSet.member?(roles, "developer") -> 1
      true -> 2
    end
  end

  defp do_reconcile_primary_series(vn_ids) do
    current_primary =
      from(v in VisualNovel, where: v.id in ^vn_ids, select: {v.id, v.primary_vn_series_id})
      |> Repo.all()
      |> Map.new()

    candidate_rows =
      from(item in VNSeriesItem,
        join: s in Series,
        on: s.id == item.vn_series_id,
        where: item.visual_novel_id in ^vn_ids and is_nil(s.hidden_at),
        order_by: [asc: item.visual_novel_id, asc: item.position, asc: s.inserted_at, asc: s.id],
        select: {item.visual_novel_id, item.vn_series_id, item.position, s.source}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0))

    from(v in VisualNovel, where: v.id in ^vn_ids)
    |> Repo.update_all(set: [primary_vn_series_id: nil, primary_series_position: nil])

    updates =
      Enum.flat_map(vn_ids, fn vn_id ->
        candidates = Map.get(candidate_rows, vn_id, [])

        case pick_primary_candidate(candidates, Map.get(current_primary, vn_id)) do
          nil -> []
          {_vn_id, series_id, position, _source} -> [{vn_id, series_id, position}]
        end
      end)

    update_vns_batch(updates)
  end

  defp pick_primary_candidate([], _current_primary_id), do: nil

  defp pick_primary_candidate(candidates, current_primary_id) do
    Enum.find(candidates, fn {_vn_id, series_id, _position, _source} ->
      series_id == current_primary_id
    end) ||
      Enum.min_by(candidates, fn {_vn_id, series_id, position, source} ->
        source_weight = if source == :user, do: 0, else: 1
        {source_weight, position, series_id}
      end)
  end

  defp update_vns_batch([]), do: :ok

  defp update_vns_batch(updates) do
    updates
    |> Enum.chunk_every(1000)
    |> Enum.each(fn chunk ->
      {vn_ids, series_ids, positions} =
        Enum.reduce(chunk, {[], [], []}, fn {vn_id, series_id, position},
                                            {vn_acc, series_acc, pos_acc} ->
          {[vn_id | vn_acc], [series_id | series_acc], [position | pos_acc]}
        end)

      Repo.query!(
        """
        UPDATE visual_novels AS v
        SET primary_vn_series_id = tmp.series_id,
            primary_series_position = tmp.position,
            updated_at = NOW()
        FROM (
          SELECT
            UNNEST($1::uuid[]) AS vn_id,
            UNNEST($2::uuid[]) AS series_id,
          UNNEST($3::double precision[]) AS position
        ) AS tmp
        WHERE v.id = tmp.vn_id
        """,
        [
          Enum.reverse(vn_ids) |> Enum.map(&Ecto.UUID.dump!/1),
          Enum.reverse(series_ids) |> Enum.map(&Ecto.UUID.dump!/1),
          Enum.reverse(positions)
        ]
      )
    end)

    :ok
  end

  defp normalize_source(source) when source in [:user, :vndb_sync], do: source
  defp normalize_source("user"), do: :user
  defp normalize_source("vndb_sync"), do: :vndb_sync
  defp normalize_source(_), do: :user

  defp normalize_manual_fields(fields) when is_list(fields) do
    fields
    |> Enum.map(&to_string/1)
    |> Enum.filter(&(&1 in @editable_groups))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_manual_fields(_), do: []

  defp series_hist_row(change_id, series) do
    series
    |> Map.take(@hist_fields)
    |> Map.update(:source, nil, &to_string/1)
    |> Map.put(:change_id, change_id)
  end

  defp chunked_insert_all(_module, []), do: :ok

  defp chunked_insert_all(module, rows) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(module, &1))

    :ok
  end

  defp encode_cursor(datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
    |> Base.encode64()
  end

  defp decode_cursor(cursor) do
    with {:ok, decoded} <- Base.decode64(cursor),
         {:ok, datetime, _} <- DateTime.from_iso8601(decoded) do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_cursor}
    end
  end
end

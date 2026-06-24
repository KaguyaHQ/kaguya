defmodule Kaguya.VisualNovels.SeriesGenerator do
  @moduledoc """
  Reconciles VN series from official sequel relations.

  Unlike the original implementation, this path treats `vn_series` as a
  first-class local entity. VNDB relations seed and refresh imported series,
  but they do not delete or reset locally curated data.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Series
  alias Kaguya.VisualNovels.{Relation, VisualNovel}

  require Logger

  @create_summary "Imported from VNDB sequel relations"
  @edit_summary "Updated from VNDB sequel relations"

  @doc """
  Reconcile imported series against the current local series table.

  Returns `{:ok, imported_count}` where `imported_count` is the number of
  relation-derived series components currently seen in VNDB.
  """
  def regenerate do
    Logger.info("Loading sequel relations...")
    relations = load_sequel_relations()
    Logger.info("Found #{length(relations)} official sequel relations")

    Logger.info("Building relation graph...")
    graph = build_undirected_graph(relations)
    components = find_connected_components(graph)
    imported_specs = build_imported_specs(Enum.filter(components, &(length(&1) > 1)), relations)

    Logger.info("Reconciling #{length(imported_specs)} imported series component(s)...")

    existing_series = Series.list_seeded_series()

    {:ok, reconcile_result} =
      Repo.transaction(fn ->
        locked_ids =
          existing_series
          |> Enum.map(& &1.id)
          |> Enum.sort()

        lock_series_entities(locked_ids)

        # Reload once under the advisory locks so reconciliation decisions are
        # based on the latest persisted state, without falling back to
        # per-series `get_for_edit/1` queries.
        existing_series = Series.list_seeded_series()

        newly_seen_ids =
          existing_series
          |> Enum.map(& &1.id)
          |> Enum.reject(&(&1 in locked_ids))
          |> Enum.sort()

        lock_series_entities(newly_seen_ids)
        existing_series = Series.list_seeded_series()

        {matches, new_specs, unmatched_existing} =
          match_imported_specs(imported_specs, existing_series)

        stale_series = Enum.filter(unmatched_existing, &stale_imported_series?/1)

        case ensure_existing_create_revisions(existing_series) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        updated =
          Enum.reduce(matches, [], fn {spec, series}, acc ->
            case Series.sync_seeded_series(series, spec_to_attrs(spec), reload: false) do
              {:ok, _updated_series, []} -> acc
              {:ok, updated_series, changed_fields} -> [{updated_series.id, changed_fields} | acc]
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        created =
          Enum.reduce(new_specs, [], fn spec, acc ->
            case Series.create_seeded_series(spec_to_attrs(spec), reload: false) do
              {:ok, created_series} -> [created_series.id | acc]
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        hidden = hide_stale_imported_series(stale_series)

        revision_entries =
          Enum.map(updated, fn {series_id, changed_fields} ->
            %{
              entity_type: :series,
              entity_id: series_id,
              action: :edit,
              source: :vndb_sync,
              changed_fields: changed_fields,
              summary: @edit_summary
            }
          end)

        create_entries =
          Enum.map(created, fn series_id ->
            %{
              entity_type: :series,
              entity_id: series_id,
              action: :create,
              source: :vndb_sync,
              changed_fields: [],
              summary: @create_summary
            }
          end)

        hide_entries =
          Enum.map(hidden, fn series_id ->
            %{
              entity_type: :series,
              entity_id: series_id,
              action: :hide,
              source: :vndb_sync,
              changed_fields: ["moderation"],
              summary:
                "Hidden because the imported VNDB series no longer matches current sequel relations"
            }
          end)

        case write_revision_entries(create_entries ++ revision_entries ++ hide_entries) do
          :ok -> %{updated: updated, created: created, hidden: hidden}
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    Logger.info(
      "Series reconciliation complete: #{length(imported_specs)} imported, " <>
        "#{length(reconcile_result.created)} created, #{length(reconcile_result.updated)} updated, " <>
        "#{length(reconcile_result.hidden)} hidden"
    )

    {:ok, length(imported_specs)}
  end

  @doc """
  Preview imported series without writing to the database.
  """
  def preview do
    relations = load_sequel_relations()
    graph = build_undirected_graph(relations)

    components =
      graph
      |> find_connected_components()
      |> Enum.filter(&(length(&1) > 1))

    build_imported_specs(components, relations)
    |> Enum.map(fn spec -> {spec.name, spec.entries} end)
  end

  def load_sequel_relations do
    from(r in Relation,
      where: r.relation_type == "sequel",
      where: r.is_official == true,
      select: %{from_id: r.visual_novel_id, to_id: r.related_vn_id}
    )
    |> Repo.all()
  end

  def build_undirected_graph(relations) do
    Enum.reduce(relations, %{}, fn %{from_id: from, to_id: to}, acc ->
      acc
      |> Map.update(from, MapSet.new([to]), &MapSet.put(&1, to))
      |> Map.update(to, MapSet.new([from]), &MapSet.put(&1, from))
    end)
  end

  def find_connected_components(graph) do
    {components, _visited} =
      Enum.reduce(Map.keys(graph), {[], MapSet.new()}, fn node, {comps, visited} ->
        if MapSet.member?(visited, node) do
          {comps, visited}
        else
          {component, visited} = bfs(node, graph, visited)
          {[component | comps], visited}
        end
      end)

    components
  end

  def build_sequel_map(relations) do
    Enum.reduce(relations, %{}, fn %{from_id: from, to_id: to}, acc ->
      Map.update(acc, from, [to], &[to | &1])
    end)
  end

  def find_root(vn_ids, sequel_map, vns_map) do
    vn_id_set = MapSet.new(vn_ids)

    sequel_targets =
      sequel_map
      |> Enum.flat_map(fn {from, to_list} ->
        if from in vn_id_set, do: Enum.filter(to_list, &(&1 in vn_id_set)), else: []
      end)
      |> MapSet.new()

    root_candidates =
      vn_ids
      |> Enum.filter(fn id -> id not in sequel_targets end)
      |> Enum.map(&Map.get(vns_map, &1))
      |> Enum.reject(&is_nil/1)

    root_candidates
    |> Enum.min_by(fn vn -> vn.release_date || ~D[9999-12-31] end, fn -> nil end)
    |> case do
      nil -> vns_map |> Map.values() |> hd()
      vn -> vn
    end
  end

  def order_by_sequel_chain(vns_map, sequel_map, root) do
    {result, _visited} = traverse_sequels(root.id, vns_map, sequel_map, MapSet.new())
    result
  end

  defp build_imported_specs(components, relations) do
    sequel_map = build_sequel_map(relations)
    all_vn_ids = components |> List.flatten() |> Enum.uniq()

    global_vns_map =
      all_vn_ids
      |> load_vns_map()

    producer_links = Series.producer_links_for_vns(all_vn_ids)

    Enum.map(components, fn vn_ids ->
      vns_map = Map.take(global_vns_map, vn_ids)
      root = find_root(vn_ids, sequel_map, vns_map)
      ordered = order_by_sequel_chain(vns_map, sequel_map, root)

      %{
        name: root.title,
        imported_root_visual_novel_id: root.id,
        entries:
          ordered
          |> Enum.with_index(1)
          |> Enum.map(fn {vn, position} ->
            %{visual_novel_id: vn.id, position: position * 1.0}
          end),
        producers: Series.suggested_producers_from_links(vn_ids, producer_links),
        member_set: MapSet.new(vn_ids)
      }
    end)
  end

  defp match_imported_specs(imported_specs, existing_series) do
    imported_specs = Enum.sort_by(imported_specs, fn spec -> -MapSet.size(spec.member_set) end)

    {matches, unmatched_existing, unmatched_imported} =
      Enum.reduce(imported_specs, {[], existing_series, []}, fn spec,
                                                                {matches_acc, existing_acc,
                                                                 imported_acc} ->
        case find_best_match(spec, existing_acc) do
          nil ->
            {matches_acc, existing_acc, [spec | imported_acc]}

          matched_series ->
            {[
               {spec, matched_series}
               | matches_acc
             ], Enum.reject(existing_acc, &(&1.id == matched_series.id)), imported_acc}
        end
      end)

    {Enum.reverse(matches), Enum.reverse(unmatched_imported), unmatched_existing}
  end

  defp find_best_match(_spec, []), do: nil

  defp find_best_match(spec, existing_series) do
    spec_size = MapSet.size(spec.member_set)

    existing_series
    |> Enum.map(fn series ->
      existing_set =
        series.vn_series_items
        |> Enum.map(& &1.visual_novel_id)
        |> MapSet.new()

      overlap = MapSet.intersection(spec.member_set, existing_set) |> MapSet.size()
      ratio = if spec_size == 0, do: 0.0, else: overlap / spec_size

      root_bonus =
        if series.imported_root_visual_novel_id == spec.imported_root_visual_novel_id,
          do: 1,
          else: 0

      {series, overlap, ratio, root_bonus}
    end)
    |> Enum.filter(fn {_series, overlap, ratio, _root_bonus} -> overlap > 0 and ratio >= 0.6 end)
    |> Enum.max_by(
      fn {_series, overlap, ratio, root_bonus} -> {ratio, overlap, root_bonus} end,
      fn -> nil end
    )
    |> case do
      nil -> nil
      {series, _overlap, _ratio, _root_bonus} -> series
    end
  end

  defp write_revision_entries([]), do: :ok

  defp write_revision_entries(entries) do
    case Revisions.bulk_create_system_changes(entries, advisory_locks: false) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_existing_create_revisions(existing_series) do
    existing_ids = Enum.map(existing_series, & &1.id)

    existing_create_ids =
      from(c in Kaguya.Revisions.Change,
        where: c.entity_type == :series and c.action == :create and c.entity_id in ^existing_ids,
        select: c.entity_id
      )
      |> Repo.all()
      |> MapSet.new()

    entries =
      existing_series
      |> Enum.reject(fn series -> MapSet.member?(existing_create_ids, series.id) end)
      |> Enum.map(fn series ->
        %{
          entity_type: :series,
          entity_id: series.id,
          action: :create,
          source: :vndb_sync,
          changed_fields: [],
          summary: @create_summary
        }
      end)

    write_revision_entries(entries)
  end

  defp lock_series_entities([]), do: :ok

  defp lock_series_entities(series_ids) do
    keys =
      series_ids
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&"series:#{&1}")

    Repo.query!(
      """
      SELECT pg_advisory_xact_lock(hashtext(k))
      FROM unnest($1::text[]) AS locks(k)
      """,
      [keys]
    )

    :ok
  end

  defp stale_imported_series?(series) do
    series.source == :vndb_sync and
      "entries" not in (series.manual_fields || []) and
      is_nil(series.hidden_at)
  end

  defp hide_stale_imported_series([]), do: []

  defp hide_stale_imported_series(series_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    series_ids = Enum.map(series_list, & &1.id)

    affected_vn_ids =
      series_list
      |> Enum.flat_map(fn series -> Enum.map(series.vn_series_items, & &1.visual_novel_id) end)
      |> Enum.uniq()

    {count, _} =
      from(s in Kaguya.VisualNovels.Series, where: s.id in ^series_ids and is_nil(s.hidden_at))
      |> Repo.update_all(set: [hidden_at: now])

    if count > 0, do: Series.reconcile_primary_series(affected_vn_ids)
    if count > 0, do: series_ids, else: []
  end

  defp spec_to_attrs(spec) do
    %{
      name: spec.name,
      description: nil,
      imported_root_visual_novel_id: spec.imported_root_visual_novel_id,
      entries: spec.entries,
      producers: spec.producers
    }
  end

  defp load_vns_map(vn_ids) do
    vn_ids
    |> Enum.chunk_every(500)
    |> Enum.reduce(%{}, fn chunk, acc ->
      vns = from(v in VisualNovel, where: v.id in ^chunk) |> Repo.all()
      Map.merge(acc, Map.new(vns, &{&1.id, &1}))
    end)
  end

  defp bfs(start, graph, visited), do: bfs_loop([start], graph, visited, [])

  defp bfs_loop([], _graph, visited, component), do: {component, visited}

  defp bfs_loop([node | rest], graph, visited, component) do
    if MapSet.member?(visited, node) do
      bfs_loop(rest, graph, visited, component)
    else
      visited = MapSet.put(visited, node)
      neighbors = Map.get(graph, node, MapSet.new()) |> MapSet.to_list()
      bfs_loop(rest ++ neighbors, graph, visited, [node | component])
    end
  end

  defp traverse_sequels(current_id, vns_map, sequel_map, visited) do
    if MapSet.member?(visited, current_id) do
      {[], visited}
    else
      current_vn = Map.get(vns_map, current_id)
      visited = MapSet.put(visited, current_id)

      sequels =
        Map.get(sequel_map, current_id, [])
        |> Enum.map(&Map.get(vns_map, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(&compare_dates/2)

      {sequel_results, visited} =
        Enum.reduce(sequels, {[], visited}, fn sequel, {acc, vis} ->
          {results, new_vis} = traverse_sequels(sequel.id, vns_map, sequel_map, vis)
          {acc ++ results, new_vis}
        end)

      result = if current_vn, do: [current_vn | sequel_results], else: sequel_results
      {result, visited}
    end
  end

  defp compare_dates(a, b) do
    case {a.release_date, b.release_date} do
      {nil, nil} -> true
      {nil, _} -> false
      {_, nil} -> true
      {d1, d2} -> Date.compare(d1, d2) != :gt
    end
  end
end

defmodule Kaguya.Lists.Layout do
  @moduledoc """
  Tier / grid layout engine for VN lists: persisting `display_mode`, tier
  definitions, and ordered list-item membership. Read helpers for tiers and
  list items live here too so they sit alongside the writes that maintain
  them.

  `Kaguya.Lists` delegates the public read APIs (`list_tiers_for_list`,
  `list_vns_for_list`, `batch_*`) and orchestrates the higher-level write
  flows (`create_list`, `update_list`, `add_vns_to_list`, etc.) on top of
  the primitives exposed here.
  """

  import Ecto.Query

  alias Kaguya.Lists.{List, ListItem, ListTier}
  alias Kaguya.Pagination
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel

  @default_tiers [
    {"S", "#f87171"},
    {"A", "#fb923c"},
    {"B", "#facc15"},
    {"C", "#4ade80"},
    {"D", "#60a5fa"}
  ]

  # Canonical 8-4-4-4-12 hex UUID string. `Ecto.UUID.cast/1` is intentionally
  # *not* used here: it accepts any 16-byte binary as a raw UUID (so the
  # client-side temp id "tier-masterpiece" round-trips through cast). The check
  # needs to recognise only DB-issued UUID *strings*.
  @uuid_string_pattern ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  # ============================================================================
  # Tier Reads
  # ============================================================================

  @doc """
  Lists tiers for a list in display order.
  """
  def list_tiers_for_list(%{id: list_id}), do: list_tiers_for_list(list_id)

  def list_tiers_for_list(list_id) do
    {:ok,
     Repo.all(
       from(t in ListTier,
         where: t.list_id == ^list_id,
         order_by: [asc: t.position, asc: t.id]
       )
     )}
  end

  @doc """
  Batch-loads tiers for multiple lists.
  """
  def batch_list_tiers_for_lists(list_ids) when is_list(list_ids) do
    ids = Enum.uniq(list_ids)

    Repo.all(
      from(t in ListTier,
        where: t.list_id in ^ids,
        order_by: [asc: t.position, asc: t.id]
      )
    )
    |> Enum.group_by(& &1.list_id)
    |> then(fn grouped -> Map.new(ids, &{&1, Map.get(grouped, &1, [])}) end)
  end

  # ============================================================================
  # VN-in-list Reads
  # ============================================================================

  @doc """
  Lists VNs in a list with pagination.
  """
  def list_vns_for_list(%List{id: list_id, vns_count: vns_count}, page, page_size, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)

    query =
      from vn in VisualNovel,
        join: vl in ListItem,
        on: vl.visual_novel_id == vn.id,
        where: vl.list_id == ^list_id,
        order_by: [asc: vl.position],
        select: {vn, vl.position, vl.tier_id, vl.tier_position}

    query = if allowed, do: where(query, [vn], vn.title_category in ^allowed), else: query
    total = if allowed, do: nil, else: vns_count

    {vns, pagination} = Pagination.paginate(query, page, page_size, total)
    {:ok, %{items: map_vn_tuples(vns), pagination: pagination}}
  end

  @doc """
  Lists all VNs for a list (unpaginated).
  Useful for editing flows and tier-mode rendering (tier boards can't be split
  across pages — the bottom tiers would silently disappear).

  Accepts `:allowed_categories` to scope by `title_category` for safe-mode
  viewers; pass `nil` (or omit) for the owner / editor flow.
  """
  def list_all_vns_for_list(%{id: list_id}, opts \\ []) do
    allowed = Keyword.get(opts, :allowed_categories)
    vn_tuples = Repo.all(vns_query_for_list(list_id, allowed))
    {:ok, map_vn_tuples(vn_tuples)}
  end

  defp vns_query_for_list(list_id, allowed_categories) do
    query =
      from(vn in VisualNovel,
        join: vl in ListItem,
        on: vl.visual_novel_id == vn.id,
        where: vl.list_id == ^list_id,
        order_by: [asc: vl.position],
        select: {vn, vl.position, vl.tier_id, vl.tier_position}
      )

    if allowed_categories,
      do: where(query, [vn], vn.title_category in ^allowed_categories),
      else: query
  end

  @doc """
  Batch-fetches the first `page_size` VNs for multiple lists in one query.
  Returns a map of list_id => %{items: [...], pagination: %{...}}.
  """
  def batch_list_vns_for_lists(list_tuples, page_size) do
    list_map = Map.new(list_tuples, fn {list_id, vns_count} -> {list_id, vns_count} end)
    list_ids = Map.keys(list_map)

    if list_ids == [] do
      %{}
    else
      ranked =
        from(li in ListItem,
          where: li.list_id in ^list_ids,
          windows: [w: [partition_by: li.list_id, order_by: li.position]],
          select: %{
            list_id: li.list_id,
            visual_novel_id: li.visual_novel_id,
            position: li.position,
            tier_id: li.tier_id,
            tier_position: li.tier_position,
            rn: row_number() |> over(:w)
          }
        )

      results =
        from(r in subquery(ranked),
          join: vn in VisualNovel,
          on: vn.id == r.visual_novel_id,
          where: r.rn <= ^page_size,
          order_by: [asc: r.list_id, asc: r.position],
          select: {r.list_id, r.position, r.tier_id, r.tier_position, vn}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0))
        |> Map.new(fn {list_id, rows} ->
          items =
            Enum.map(rows, fn {_lid, position, tier_id, tier_position, vn} ->
              %{
                visual_novel: vn,
                position: position,
                tier_id: tier_id,
                tier_position: tier_position
              }
            end)

          vns_count = Map.get(list_map, list_id, 0)
          total_pages = div(vns_count + page_size - 1, page_size)

          {list_id,
           %{
             items: items,
             pagination: %{
               page: 1,
               page_size: page_size,
               total_count: vns_count,
               total_pages: total_pages
             }
           }}
        end)

      Map.new(list_ids, fn id ->
        {id,
         Map.get(results, id, %{
           items: [],
           pagination: %{page: 1, page_size: page_size, total_count: 0, total_pages: 0}
         })}
      end)
    end
  end

  defp map_vn_tuples(vn_tuples) do
    Enum.map(vn_tuples, fn {vn, position, tier_id, tier_position} ->
      %{
        visual_novel: vn,
        position: position,
        tier_id: tier_id,
        tier_position: tier_position
      }
    end)
  end

  # ============================================================================
  # Items Engine
  # ============================================================================

  @doc """
  Appends `item_ids` to the end of a list, then bumps the parent list's
  `vns_count` / `updated_at` / `last_activity_at` by the number actually
  inserted. Conflicts (already-present VNs) are silently dropped.
  """
  def add_items_to_list(_list_id, item_ids) when not is_list(item_ids) or item_ids == [],
    do: {:ok, 0}

  def add_items_to_list(list_id, item_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    max_pos =
      from(j in ListItem,
        where: j.list_id == ^list_id,
        select: max(j.position)
      )
      |> Repo.one() || 0

    entries =
      item_ids
      |> Enum.with_index(max_pos + 1)
      |> Enum.map(fn {item_id, pos} ->
        %{
          list_id: list_id,
          visual_novel_id: item_id,
          position: pos,
          inserted_at: now,
          updated_at: now
        }
      end)

    {num_inserted, _} = Repo.insert_all(ListItem, entries, on_conflict: :nothing)

    if num_inserted > 0 do
      Repo.update_all(
        from(l in List, where: l.id == ^list_id),
        inc: [vns_count: num_inserted],
        set: [updated_at: now, last_activity_at: now]
      )
    end

    {:ok, num_inserted}
  end

  @doc """
  Removes the given VN ids from a list and decrements `vns_count`.
  """
  def remove_items_from_list(_list_id, item_ids)
      when not is_list(item_ids) or item_ids == [],
      do: {:ok, 0}

  def remove_items_from_list(list_id, item_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {num_deleted, _} =
      from(j in ListItem,
        where: j.list_id == ^list_id and j.visual_novel_id in ^item_ids
      )
      |> Repo.delete_all()

    if num_deleted > 0 do
      Repo.update_all(
        from(l in List, where: l.id == ^list_id),
        inc: [vns_count: -num_deleted],
        set: [updated_at: now, last_activity_at: now]
      )
    end

    {:ok, num_deleted}
  end

  @doc """
  Replace the entire ordered list membership with the provided ordered IDs.

  Opens its own `Repo.transact`. For callers already inside a transaction,
  use `set_list_items_in_transaction/2`.
  """
  def set_list_items(list_id, ordered_item_ids) when is_list(ordered_item_ids) do
    do_set_list_items(list_id, ordered_item_ids, true)
  end

  @doc """
  Same as `set_list_items/2` but assumes the caller already opened a
  `Repo.transact` block — does not open a nested one.
  """
  def set_list_items_in_transaction(list_id, ordered_item_ids)
      when is_list(ordered_item_ids) do
    do_set_list_items(list_id, ordered_item_ids, false)
  end

  defp do_set_list_items(list_id, ordered_item_ids, open_transaction?) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    runner =
      if open_transaction? do
        fn fun -> Repo.transact(fun) end
      else
        fn fun -> fun.() end
      end

    runner.(fn ->
      previous_tiers = previous_item_tier_map(list_id)

      entries =
        ordered_item_ids
        |> Enum.reject(&is_nil/1)
        |> Enum.with_index(1)
        |> Enum.map(fn {item_id, position} ->
          previous = Map.get(previous_tiers, item_id, %{})

          %{
            list_id: list_id,
            visual_novel_id: item_id,
            position: position,
            tier_id: Map.get(previous, :tier_id),
            tier_position: Map.get(previous, :tier_position),
            inserted_at: now,
            updated_at: now
          }
        end)

      with {:ok, true} <- replace_list_items(list_id, entries) do
        new_count = length(entries)

        Repo.update_all(
          from(l in List, where: l.id == ^list_id),
          set: [vns_count: new_count, updated_at: now, last_activity_at: now]
        )

        {:ok, true}
      end
    end)
  end

  defp replace_list_items(list_id, entries) when is_list(entries) do
    if entries != [] do
      Repo.insert_all(
        ListItem,
        entries,
        on_conflict: {:replace, [:position, :tier_id, :tier_position, :updated_at]},
        conflict_target: [:list_id, :visual_novel_id]
      )
    end

    kept_ids = Enum.map(entries, & &1.visual_novel_id)

    delete_query = from(j in ListItem, where: j.list_id == ^list_id)

    delete_query =
      if kept_ids == [] do
        delete_query
      else
        from(j in delete_query, where: j.visual_novel_id not in ^kept_ids)
      end

    Repo.delete_all(delete_query)

    {:ok, true}
  end

  # ============================================================================
  # Layout Save (display_mode + tiers + items in one transaction)
  # ============================================================================

  @doc """
  Atomically saves a list's display mode, tier definitions, and full VN layout.

  Tier-list saves reject duplicate VN placements. Grid saves keep the flat
  `position` order while preserving tier placement fields for mode switching.
  """
  def save_list_layout(list_id, user_id, attrs) when is_map(attrs) do
    Repo.transact(fn ->
      defer_list_tier_position_constraint()

      with {:ok, display_mode} <- normalize_display_mode(Map.get(attrs, :display_mode)),
           %List{} = list <- lock_list_for_owner(list_id, user_id),
           tier_attrs <- Map.get(attrs, :tiers, :omitted),
           item_attrs <- Map.get(attrs, :items, []),
           {:ok, item_attrs} <- validate_layout_items(item_attrs),
           :ok <- validate_item_positions(item_attrs),
           {:ok, vn_ids} <- item_visual_novel_ids(item_attrs),
           {:ok, _vn_ids} <- Kaguya.Lists.ensure_visual_novels_exist(vn_ids),
           {:ok, layout_tiers} <- save_layout_tiers(list.id, display_mode, tier_attrs),
           {:ok, entries} <-
             build_layout_item_entries(list.id, display_mode, layout_tiers, item_attrs),
           {:ok, true} <- replace_list_items(list.id, entries),
           {:ok, updated} <- update_list_layout_metadata(list, display_mode, length(entries)) do
        {:ok, updated}
      else
        nil -> {:error, :not_found}
        error -> error
      end
    end)
  end

  @doc """
  For tier-mode lists with no tiers yet, seeds the default S/A/B/C/D set.
  No-op for grid lists.
  """
  def maybe_ensure_default_tiers(%List{display_mode: "tier", id: list_id}) do
    case Repo.aggregate(from(t in ListTier, where: t.list_id == ^list_id), :count, :id) do
      0 -> save_layout_tiers(list_id, "tier", [])
      _ -> list_tiers_for_list(list_id)
    end
  end

  def maybe_ensure_default_tiers(_list), do: {:ok, []}

  defp normalize_display_mode(:grid), do: {:ok, "grid"}
  defp normalize_display_mode(:tier), do: {:ok, "tier"}
  defp normalize_display_mode("grid"), do: {:ok, "grid"}
  defp normalize_display_mode("tier"), do: {:ok, "tier"}
  defp normalize_display_mode(nil), do: {:ok, "grid"}
  defp normalize_display_mode(_), do: {:error, :invalid_display_mode}

  defp lock_list_for_owner(list_id, user_id) do
    Repo.one(
      from(l in List,
        where: l.id == ^list_id and l.user_id == ^user_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp defer_list_tier_position_constraint do
    Repo.query!("SET CONSTRAINTS list_tiers_list_id_position_unique DEFERRED")
  end

  defp validate_layout_items(items) when is_list(items), do: {:ok, items}
  defp validate_layout_items(_), do: {:error, :invalid_list_items}

  defp validate_item_positions(items) do
    invalid? =
      Enum.any?(items, fn item ->
        invalid_optional_positive_integer?(Map.get(item, :position)) or
          invalid_optional_positive_integer?(Map.get(item, :tier_position))
      end)

    if invalid?, do: {:error, :invalid_position}, else: :ok
  end

  defp invalid_optional_positive_integer?(nil), do: false
  defp invalid_optional_positive_integer?(value) when is_integer(value), do: value < 1
  defp invalid_optional_positive_integer?(_), do: true

  defp item_visual_novel_ids(items) do
    ids = Enum.map(items, &Map.get(&1, :visual_novel_id))

    cond do
      Enum.any?(ids, &is_nil/1) ->
        {:error, :missing_visual_novel_id}

      length(ids) != length(Enum.uniq(ids)) ->
        {:error, :duplicate_visual_novel}

      true ->
        {:ok, ids}
    end
  end

  defp save_layout_tiers(list_id, "grid", :omitted) do
    with {:ok, tiers} <- list_tiers_for_list(list_id), do: {:ok, layout_tiers_result(tiers)}
  end

  defp save_layout_tiers(list_id, "grid", tier_attrs) when is_list(tier_attrs) do
    if tier_attrs == [] do
      with {:ok, tiers} <- list_tiers_for_list(list_id) do
        {:ok, layout_tiers_result(tiers)}
      end
    else
      save_layout_tiers(list_id, "tier", tier_attrs)
    end
  end

  defp save_layout_tiers(list_id, "tier", :omitted) do
    with {:ok, tiers} <- list_tiers_for_list(list_id) do
      case tiers do
        [] -> save_layout_tiers(list_id, "tier", [])
        tiers -> {:ok, layout_tiers_result(tiers)}
      end
    end
  end

  defp save_layout_tiers(list_id, "tier", tier_attrs) when is_list(tier_attrs) do
    attrs = if tier_attrs == [], do: default_tier_attrs(), else: tier_attrs

    with :ok <- validate_unique_tier_positions(attrs),
         :ok <- validate_unique_tier_ids(attrs) do
      existing = Repo.all(from(t in ListTier, where: t.list_id == ^list_id))
      existing_by_id = Map.new(existing, &{&1.id, &1})
      submitted_ids = attrs |> Enum.map(&db_tier_id/1) |> Enum.reject(&is_nil/1)

      with :ok <- ensure_tier_ids_belong_to_list(submitted_ids, list_id) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        saved =
          Enum.reduce_while(attrs, {:ok, []}, fn attrs, {:ok, acc} ->
            attrs = Map.put(attrs, :list_id, list_id)
            changeset_attrs = Map.drop(attrs, [:id, "id"])

            result =
              case Map.get(attrs, :id) do
                nil ->
                  %ListTier{} |> ListTier.changeset(changeset_attrs) |> Repo.insert()

                id ->
                  case Map.get(existing_by_id, id) do
                    nil ->
                      if binary_id?(id) do
                        %ListTier{id: id} |> ListTier.changeset(changeset_attrs) |> Repo.insert()
                      else
                        %ListTier{} |> ListTier.changeset(changeset_attrs) |> Repo.insert()
                      end

                    %ListTier{} = tier ->
                      tier |> ListTier.changeset(changeset_attrs) |> Repo.update()
                  end
              end

            case result do
              {:ok, tier} -> {:cont, {:ok, [tier | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        with {:ok, saved_tiers} <- saved do
          saved_tiers = Enum.reverse(saved_tiers)
          saved_ids = Enum.map(saved_tiers, & &1.id)

          id_map =
            attrs
            |> Enum.zip(saved_tiers)
            |> Map.new(fn {attrs, tier} -> {Map.get(attrs, :id, tier.id), tier.id} end)
            |> Map.merge(Map.new(saved_tiers, &{&1.id, &1.id}))

          from(li in ListItem,
            where: li.list_id == ^list_id and li.tier_id not in ^saved_ids
          )
          |> Repo.update_all(set: [tier_id: nil, tier_position: nil, updated_at: now])

          from(t in ListTier,
            where: t.list_id == ^list_id and t.id not in ^saved_ids
          )
          |> Repo.delete_all()

          {:ok, %{tiers: Enum.sort_by(saved_tiers, &{&1.position, &1.id}), id_map: id_map}}
        end
      end
    end
  end

  defp save_layout_tiers(_list_id, "tier", _), do: {:error, :invalid_tiers}

  defp layout_tiers_result(tiers), do: %{tiers: tiers, id_map: Map.new(tiers, &{&1.id, &1.id})}

  defp validate_unique_tier_positions(attrs) do
    values = Enum.map(attrs, &Map.get(&1, :position))

    if length(values) == length(Enum.uniq(values)),
      do: :ok,
      else: {:error, :duplicate_tier_position}
  end

  defp validate_unique_tier_ids(attrs) do
    ids = attrs |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_tier_id}
  end

  defp db_tier_id(%{id: id}) when is_binary(id) do
    if binary_id?(id), do: id, else: nil
  end

  defp db_tier_id(_), do: nil

  defp binary_id?(id) when is_binary(id), do: Regex.match?(@uuid_string_pattern, id)
  defp binary_id?(_), do: false

  defp ensure_tier_ids_belong_to_list([], _list_id), do: :ok

  defp ensure_tier_ids_belong_to_list(ids, list_id) do
    foreign_count =
      Repo.aggregate(
        from(t in ListTier, where: t.id in ^ids and t.list_id != ^list_id),
        :count,
        :id
      )

    if foreign_count == 0, do: :ok, else: {:error, :tier_not_found}
  end

  defp default_tier_attrs do
    @default_tiers
    |> Enum.with_index(1)
    |> Enum.map(fn {{label, color}, position} ->
      %{label: label, color: color, position: position}
    end)
  end

  defp build_layout_item_entries(list_id, "grid", layout_tiers, items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    previous_tiers = previous_item_tier_map(list_id)
    tiers = Map.get(layout_tiers, :tiers, [])
    id_map = Map.get(layout_tiers, :id_map, %{})
    tier_ids = MapSet.new(Enum.map(tiers, & &1.id))

    enriched_items =
      items
      |> Enum.map(fn item ->
        visual_novel_id = Map.fetch!(item, :visual_novel_id)
        previous = Map.get(previous_tiers, visual_novel_id, %{})

        tier_id =
          item
          |> item_field_or_previous(:tier_id, previous)
          |> resolve_tier_ref(id_map)

        item
        |> Map.put(:tier_id, tier_id)
        |> Map.put(:tier_position, item_field_or_previous(item, :tier_position, previous))
      end)

    entries =
      enriched_items
      |> order_grid_items()
      |> Enum.with_index(1)
      |> Enum.map(fn {item, position} ->
        visual_novel_id = Map.fetch!(item, :visual_novel_id)

        %{
          list_id: list_id,
          visual_novel_id: visual_novel_id,
          position: position,
          tier_id: Map.get(item, :tier_id),
          tier_position: Map.get(item, :tier_position),
          inserted_at: now,
          updated_at: now
        }
      end)

    with :ok <- validate_item_tier_references(entries, tier_ids),
         :ok <- validate_unique_tier_positions_within_items(entries) do
      {:ok, entries}
    end
  end

  defp build_layout_item_entries(list_id, "tier", layout_tiers, items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    tiers = Map.get(layout_tiers, :tiers, [])
    id_map = Map.get(layout_tiers, :id_map, %{})
    tier_ids = MapSet.new(Enum.map(tiers, & &1.id))
    previous_tiers = previous_item_tier_map(list_id)

    enriched_items =
      Enum.map(items, fn item ->
        visual_novel_id = Map.fetch!(item, :visual_novel_id)
        previous = Map.get(previous_tiers, visual_novel_id, %{})

        tier_id =
          item
          |> item_field_or_previous(:tier_id, previous)
          |> resolve_tier_ref(id_map)

        item
        |> Map.put(:tier_id, tier_id)
        |> Map.put(:tier_position, item_field_or_previous(item, :tier_position, previous))
      end)

    with :ok <- validate_item_tier_references(enriched_items, tier_ids),
         :ok <- validate_unique_tier_positions_within_items(enriched_items) do
      entries =
        enriched_items
        |> order_tier_items(tiers, %{})
        |> normalize_item_tier_positions()
        |> Enum.with_index(1)
        |> Enum.map(fn {item, position} ->
          %{
            list_id: list_id,
            visual_novel_id: Map.fetch!(item, :visual_novel_id),
            position: position,
            tier_id: Map.get(item, :tier_id),
            tier_position: Map.get(item, :tier_position),
            inserted_at: now,
            updated_at: now
          }
        end)

      {:ok, entries}
    end
  end

  defp previous_item_tier_map(list_id) do
    Repo.all(
      from(li in ListItem,
        where: li.list_id == ^list_id,
        select: {li.visual_novel_id, %{tier_id: li.tier_id, tier_position: li.tier_position}}
      )
    )
    |> Map.new()
  end

  defp item_field_or_previous(item, field, previous) do
    if Map.has_key?(item, field), do: Map.get(item, field), else: Map.get(previous, field)
  end

  defp validate_item_tier_references(items, tier_ids, id_map \\ %{}) do
    invalid? =
      Enum.any?(items, fn item ->
        tier_id = resolve_tier_ref(Map.get(item, :tier_id), id_map)
        not is_nil(tier_id) and not MapSet.member?(tier_ids, tier_id)
      end)

    if invalid?, do: {:error, :tier_not_found}, else: :ok
  end

  defp resolve_tier_ref(nil, _id_map), do: nil
  defp resolve_tier_ref(tier_id, id_map), do: Map.get(id_map, tier_id, tier_id)

  defp validate_unique_tier_positions_within_items(items) do
    duplicate? =
      items
      |> Enum.reject(&(is_nil(Map.get(&1, :tier_id)) or is_nil(Map.get(&1, :tier_position))))
      |> Enum.group_by(&Map.get(&1, :tier_id), &Map.get(&1, :tier_position))
      |> Enum.any?(fn {_tier_id, positions} ->
        length(positions) != length(Enum.uniq(positions))
      end)

    if duplicate?, do: {:error, :duplicate_tier_position}, else: :ok
  end

  defp order_grid_items(items) do
    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, idx} -> {Map.get(item, :position) || idx + 1, idx} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp order_tier_items(items, tiers, id_map) do
    tier_order =
      tiers
      |> Enum.with_index()
      |> Map.new(fn {tier, idx} -> {tier.id, {tier.position, idx}} end)

    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, idx} ->
      case resolve_tier_ref(Map.get(item, :tier_id), id_map) do
        nil ->
          {{999_999, 999_999},
           Map.get(item, :tier_position) || Map.get(item, :position) || idx + 1, idx}

        tier_id ->
          {Map.get(tier_order, tier_id, {999_998, 999_998}),
           Map.get(item, :tier_position) || Map.get(item, :position) || idx + 1, idx}
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp normalize_item_tier_positions(items) do
    {normalized, _counts} =
      Enum.map_reduce(items, %{}, fn item, counts ->
        case Map.get(item, :tier_id) do
          nil ->
            {Map.put(item, :tier_position, nil), counts}

          tier_id ->
            position = Map.get(counts, tier_id, 0) + 1

            {Map.put(item, :tier_position, position), Map.put(counts, tier_id, position)}
        end
      end)

    normalized
  end

  defp update_list_layout_metadata(list, display_mode, count) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    list
    |> Ecto.Changeset.change(%{
      display_mode: display_mode,
      vns_count: count,
      updated_at: now,
      last_activity_at: now
    })
    |> Repo.update()
  end
end

defmodule Kaguya.Lists.Layout do
  @moduledoc """
  Persistence for list layouts: `display_mode`, tier definitions, and ordered
  item membership. Read helpers for tiers and items live here too so they sit
  alongside the writes that maintain them.

  A list holds one kind of item, chosen by `lists.item_type`:

    * `"vn"` — rows in `list_items`, keyed by `visual_novel_id`
    * `"character"` — rows in `list_character_items`, keyed by `character_id`

  Ordering and validation rules are shared and live in `Kaguya.Lists.Placement`;
  this module only maps item types to their tables.

  `Kaguya.Lists` delegates the public read APIs and orchestrates the
  higher-level write flows (`create_list`, `update_list`, `add_vns_to_list`,
  etc.) on top of the primitives exposed here.
  """

  import Ecto.Query

  alias Kaguya.Characters.Character
  alias Kaguya.Lists.{List, ListCharacterItem, ListItem, ListTier, Placement}
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
  # Character-in-list Reads
  # ============================================================================

  @doc """
  Lists every character in a character list with its placement, in flat order.
  Hidden characters are left out.
  """
  def list_all_characters_for_list(%{id: list_id}) do
    rows =
      Repo.all(
        from(c in Character,
          join: li in ListCharacterItem,
          on: li.character_id == c.id,
          where: li.list_id == ^list_id and is_nil(c.hidden_at),
          order_by: [asc: li.position],
          select: %{
            character: c,
            position: li.position,
            tier_id: li.tier_id,
            tier_position: li.tier_position
          }
        )
      )

    {:ok, rows}
  end

  @doc """
  Batch-fetches the first `limit` characters for multiple character lists in
  one query. Returns `list_id => [%Character{}]` in list order.
  """
  def batch_list_characters_for_lists([], _limit), do: %{}

  def batch_list_characters_for_lists(list_ids, limit) when is_list(list_ids) do
    ranked =
      from(li in ListCharacterItem,
        join: c in Character,
        on: c.id == li.character_id,
        where: li.list_id in ^list_ids and is_nil(c.hidden_at),
        windows: [w: [partition_by: li.list_id, order_by: li.position]],
        select: %{
          list_id: li.list_id,
          character_id: li.character_id,
          rn: row_number() |> over(:w)
        }
      )

    grouped =
      from(r in subquery(ranked),
        join: c in Character,
        on: c.id == r.character_id,
        where: r.rn <= ^limit,
        order_by: [asc: r.list_id, asc: r.rn],
        select: {r.list_id, c}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(list_ids, &{&1, Map.get(grouped, &1, [])})
  end

  # ============================================================================
  # Item Types
  # ============================================================================

  @doc """
  The payload key that identifies an item for a list's item type
  (`:visual_novel_id` or `:character_id`).
  """
  def item_key(%List{item_type: item_type}), do: item_key(item_type)
  def item_key("vn"), do: :visual_novel_id
  def item_key("character"), do: :character_id

  defp item_schema("vn"), do: ListItem
  defp item_schema("character"), do: ListCharacterItem

  @doc """
  Checks that every id refers to an existing item of the given type.
  Hidden characters count as missing, since they can't be shown.
  """
  def ensure_items_exist(_item_type, []), do: {:ok, []}

  def ensure_items_exist(item_type, ids) when is_list(ids) do
    found = item_type |> existing_items_query(ids) |> Repo.all() |> MapSet.new()

    if Enum.all?(ids, &MapSet.member?(found, &1)),
      do: {:ok, ids},
      else: {:error, :unknown_items}
  end

  defp existing_items_query("vn", ids),
    do: from(vn in VisualNovel, where: vn.id in ^ids, select: vn.id)

  defp existing_items_query("character", ids),
    do: from(c in Character, where: c.id in ^ids and is_nil(c.hidden_at), select: c.id)

  # ============================================================================
  # Items Engine
  # ============================================================================

  @doc """
  Appends `item_ids` to the end of a list, then bumps the parent list's
  `vns_count` / `updated_at` / `last_activity_at` by the number actually
  inserted. Conflicts (already-present items) are silently dropped.
  """
  def add_items_to_list(_list, item_ids) when not is_list(item_ids) or item_ids == [],
    do: {:ok, 0}

  def add_items_to_list(%List{id: list_id, item_type: item_type}, item_ids) do
    schema = item_schema(item_type)
    key = item_key(item_type)
    now = now()

    max_pos =
      from(j in schema, where: j.list_id == ^list_id, select: max(j.position))
      |> Repo.one() || 0

    entries =
      item_ids
      |> Enum.with_index(max_pos + 1)
      |> Enum.map(fn {item_id, pos} ->
        %{key => item_id, list_id: list_id, position: pos, inserted_at: now, updated_at: now}
      end)

    {num_inserted, _} = Repo.insert_all(schema, entries, on_conflict: :nothing)

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
  Removes the given item ids from a list and decrements `vns_count`.
  """
  def remove_items_from_list(_list, item_ids) when not is_list(item_ids) or item_ids == [],
    do: {:ok, 0}

  def remove_items_from_list(%List{id: list_id, item_type: item_type}, item_ids) do
    key = item_key(item_type)
    now = now()

    {num_deleted, _} =
      from(j in item_schema(item_type),
        where: j.list_id == ^list_id and field(j, ^key) in ^item_ids
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
  Replaces the entire ordered membership with the provided ordered ids,
  keeping each item's saved tier placement.
  """
  def set_list_items(%List{} = list, ordered_item_ids) when is_list(ordered_item_ids) do
    Repo.transact(fn ->
      items = Placement.reorder(ordered_item_ids, previous_placements(list))

      with {:ok, true} <- replace_items(list, items) do
        update_counts(list.id, length(items))
        {:ok, true}
      end
    end)
  end

  # ============================================================================
  # Layout Save (display_mode + tiers + items in one transaction)
  # ============================================================================

  @doc """
  Atomically saves a list's display mode, tier definitions, and full layout.

  Items are keyed by `item_key/1` for the list's item type. Duplicate items
  are rejected. Grid saves keep the flat `position` order while preserving
  tier placement fields for mode switching. Character lists are always tier
  lists and save only placed characters (`{:error, :no_ranked_items}` when
  none are).
  """
  def save_list_layout(list_id, user_id, attrs) when is_map(attrs) do
    Repo.transact(fn ->
      defer_list_tier_position_constraint()

      with {:ok, requested_mode} <- normalize_display_mode(Map.get(attrs, :display_mode)),
           %List{} = list <- lock_list_for_owner(list_id, user_id),
           display_mode = display_mode_for(list, requested_mode),
           {:ok, items} <- placement_items(list, Map.get(attrs, :items, [])),
           {:ok, item_ids} <- Placement.validate_items(items),
           {:ok, _ids} <- ensure_items_exist(list.item_type, item_ids),
           {:ok, layout_tiers} <-
             save_layout_tiers(list.id, display_mode, Map.get(attrs, :tiers, :omitted)),
           # Read saved placements only after tiers are written, so items in a
           # removed tier fall back to "unplaced" rather than a dead tier id.
           {:ok, arranged} <-
             Placement.arrange(display_mode, items, previous_placements(list), layout_tiers),
           {:ok, kept} <- keep_saved_items(list, arranged),
           {:ok, true} <- replace_items(list, kept) do
        update_list_layout_metadata(list, display_mode, length(kept))
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

  # Character lists are tier lists only.
  defp display_mode_for(%List{item_type: "character"}, _requested), do: "tier"
  defp display_mode_for(_list, requested), do: requested

  # A character list's unranked pool is scratch space, as on most tier list
  # sites: only characters placed in a tier are saved. Dropping the rest here
  # keeps every reader (counts, thumbnails, SEO) in step with the page.
  # Unplaced items sort last, so the kept positions stay contiguous. VN lists
  # keep unplaced items, since they show in grid mode.
  defp keep_saved_items(%List{item_type: "character"}, items) do
    case Enum.reject(items, &is_nil(&1.tier_id)) do
      [] -> {:error, :no_ranked_items}
      placed -> {:ok, placed}
    end
  end

  defp keep_saved_items(_list, items), do: {:ok, items}

  # Converts payload items (keyed by `:visual_novel_id` / `:character_id`) into
  # Placement's `:item_id` shape, keeping only the fields that were submitted
  # so omitted tier fields fall back to saved placement.
  defp placement_items(list, items) when is_list(items) do
    key = item_key(list)

    {:ok,
     Enum.map(items, fn item ->
       item
       |> Map.take([:position, :tier_id, :tier_position])
       |> Map.put(:item_id, Map.get(item, key))
     end)}
  end

  defp placement_items(_list, _items), do: {:error, :invalid_list_items}

  defp previous_placements(%List{id: list_id, item_type: item_type}) do
    key = item_key(item_type)

    Repo.all(
      from(li in item_schema(item_type),
        where: li.list_id == ^list_id,
        select: {field(li, ^key), %{tier_id: li.tier_id, tier_position: li.tier_position}}
      )
    )
    |> Map.new()
  end

  defp replace_items(%List{id: list_id, item_type: item_type}, items) do
    schema = item_schema(item_type)
    key = item_key(item_type)
    now = now()

    entries =
      Enum.map(items, fn item ->
        %{
          key => item.item_id,
          list_id: list_id,
          position: item.position,
          tier_id: item.tier_id,
          tier_position: item.tier_position,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [] do
      Repo.insert_all(schema, entries,
        on_conflict: {:replace, [:position, :tier_id, :tier_position, :updated_at]},
        conflict_target: [:list_id, key]
      )
    end

    kept_ids = Enum.map(items, & &1.item_id)

    from(j in schema, where: j.list_id == ^list_id and field(j, ^key) not in ^kept_ids)
    |> Repo.delete_all()

    {:ok, true}
  end

  defp update_counts(list_id, count) do
    now = now()

    Repo.update_all(
      from(l in List, where: l.id == ^list_id),
      set: [vns_count: count, updated_at: now, last_activity_at: now]
    )
  end

  defp normalize_display_mode(mode) when mode in [:grid, "grid", nil], do: {:ok, "grid"}
  defp normalize_display_mode(mode) when mode in [:tier, "tier"], do: {:ok, "tier"}
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

  # ============================================================================
  # Tier Writes
  # ============================================================================

  # Grid saves only touch tiers when the payload carries a tier set (so tier
  # edits made while viewing the grid are kept); otherwise saved tiers stay.
  defp save_layout_tiers(list_id, "grid", tier_attrs) when tier_attrs in [:omitted, []] do
    with {:ok, tiers} <- list_tiers_for_list(list_id), do: {:ok, layout_tiers_result(tiers)}
  end

  defp save_layout_tiers(list_id, "grid", tier_attrs) when is_list(tier_attrs),
    do: write_tiers(list_id, tier_attrs)

  defp save_layout_tiers(list_id, "tier", :omitted) do
    case list_tiers_for_list(list_id) do
      {:ok, []} -> write_tiers(list_id, default_tier_attrs())
      {:ok, tiers} -> {:ok, layout_tiers_result(tiers)}
    end
  end

  defp save_layout_tiers(list_id, "tier", []), do: write_tiers(list_id, default_tier_attrs())

  defp save_layout_tiers(list_id, "tier", tier_attrs) when is_list(tier_attrs),
    do: write_tiers(list_id, tier_attrs)

  defp save_layout_tiers(_list_id, _mode, _tier_attrs), do: {:error, :invalid_tiers}

  defp write_tiers(list_id, attrs) do
    with :ok <- validate_unique_tier_positions(attrs),
         :ok <- validate_unique_tier_ids(attrs),
         submitted_ids = attrs |> Enum.map(&db_tier_id/1) |> Enum.reject(&is_nil/1),
         :ok <- ensure_tier_ids_belong_to_list(submitted_ids, list_id),
         existing_by_id =
           Repo.all(from(t in ListTier, where: t.list_id == ^list_id)) |> Map.new(&{&1.id, &1}),
         {:ok, saved_tiers} <- persist_layout_tiers(attrs, list_id, existing_by_id) do
      finish_layout_tiers(list_id, attrs, Enum.reverse(saved_tiers))
    end
  end

  defp persist_layout_tiers(attrs, list_id, existing_by_id) do
    Enum.reduce_while(attrs, {:ok, []}, fn attrs, {:ok, acc} ->
      case persist_layout_tier(attrs, list_id, existing_by_id) do
        {:ok, tier} -> {:cont, {:ok, [tier | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_layout_tier(attrs, list_id, existing_by_id) do
    changeset_attrs = attrs |> Map.put(:list_id, list_id) |> Map.drop([:id, "id"])
    id = Map.get(attrs, :id)

    case Map.get(existing_by_id, id) do
      %ListTier{} = tier ->
        tier |> ListTier.changeset(changeset_attrs) |> Repo.update()

      nil ->
        tier = if binary_id?(id), do: %ListTier{id: id}, else: %ListTier{}
        tier |> ListTier.changeset(changeset_attrs) |> Repo.insert()
    end
  end

  # Removes tiers that were dropped from the payload. Their items are
  # unassigned (in both item tables) rather than lost.
  defp finish_layout_tiers(list_id, attrs, saved_tiers) do
    saved_ids = Enum.map(saved_tiers, & &1.id)
    now = now()

    id_map =
      attrs
      |> Enum.zip(saved_tiers)
      |> Map.new(fn {attrs, tier} -> {Map.get(attrs, :id, tier.id), tier.id} end)
      |> Map.merge(Map.new(saved_tiers, &{&1.id, &1.id}))

    for schema <- [ListItem, ListCharacterItem] do
      from(li in schema, where: li.list_id == ^list_id and li.tier_id not in ^saved_ids)
      |> Repo.update_all(set: [tier_id: nil, tier_position: nil, updated_at: now])
    end

    from(t in ListTier, where: t.list_id == ^list_id and t.id not in ^saved_ids)
    |> Repo.delete_all()

    {:ok, %{tiers: Enum.sort_by(saved_tiers, &{&1.position, &1.id}), id_map: id_map}}
  end

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

  defp db_tier_id(%{id: id}) when is_binary(id), do: if(binary_id?(id), do: id)
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

  defp update_list_layout_metadata(list, display_mode, count) do
    now = now()

    list
    |> Ecto.Changeset.change(%{
      display_mode: display_mode,
      vns_count: count,
      updated_at: now,
      last_activity_at: now
    })
    |> Repo.update()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

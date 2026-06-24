defmodule Kaguya.Revisions.Diff do
  @moduledoc """
  Turns `_hist` snapshots into UI-friendly shapes: a serialized snapshot map
  and a field-level diff between two revisions.

  Pure functions — no Repo access. Callers (`Kaguya.Revisions`) load the hist
  data; this module only reshapes it. Reference enrichment (UUIDs → titles,
  image ids → URLs) is a separate concern handled by
  `Kaguya.Revisions.Enrichment`.

  Diffs are identity-aware: sub-entity rows are matched by their natural key
  (e.g. `cover_id` for covers, `lang` for titles) so a single-field edit shows
  as one `changed` row, not as a remove + add pair.
  """

  # Natural keys for stable identity-aware sub-entity diffing. The map key is
  # the field name as it appears in the load_hist result; the value is the
  # list of fields that uniquely identify a row within a single parent.
  #
  # IMPORTANT: each natural key must match the *DB-enforced* uniqueness on the
  # corresponding live table, not just the fields that "feel" identifying.
  # Including a mutable property in the key (e.g. `relation_type`) breaks
  # `changed`-row detection — an edit to that field becomes a remove+add.
  @sub_entity_keys %{
    # vn_titles PK: (visual_novel_id, lang)
    "titles" => [:lang],
    # vn_relations PK: (visual_novel_id, related_vn_id) — relation_type is a
    # mutable property of the row, NOT part of the identity
    "relations" => [:related_vn_id],
    # screenshot_id / cover_id / image_id are globally unique UUIDs
    "screenshots" => [:screenshot_id],
    "covers" => [:cover_id],
    "images" => [:image_id],
    # vn_characters PK: (visual_novel_id, character_id) — each side picks the
    # field that varies within its parent
    "characters" => [:character_id],
    "appearances" => [:visual_novel_id],
    "entries" => [:visual_novel_id],
    # vn_series_producers PK: (vn_series_id, producer_id)
    "producers" => [:producer_id],
    # vn_external_links PK: (vn_id, site)
    "external_links" => [:site],
    # producer_external_links PK: (producer_id, site)
    "links" => [:site],
    # vn_release_extlinks unique: (vn_release_id, site, url)
    "extlinks" => [:site, :url]
  }

  @doc """
  Serializes a hist payload (structs + sub-collections) into a plain map tree
  suitable for the frontend, dropping Ecto bookkeeping fields.
  """
  def serialize_hist(hist_data) when is_map(hist_data) do
    Map.new(hist_data, fn
      {k, v} when is_list(v) -> {k, Enum.map(v, &struct_to_map/1)}
      {k, v} when is_struct(v) -> {k, struct_to_map(v)}
      {k, v} -> {k, v}
    end)
  end

  def serialize_hist(nil), do: nil

  @doc """
  Computes the field-level diff between a previous and current hist payload.
  Returns `[]` when there is no previous revision. Scalar fields produce
  `%{field, old, new}` (or `%{field, added, removed}` for list-valued
  columns); sub-collections produce `%{field, added, removed, changed}`.
  """
  def compute_diff(nil, _current), do: []

  def compute_diff(previous, current) do
    scalar_diffs = scalar_field_diffs(previous.hist, current.hist)

    sub_entity_keys =
      (Map.keys(previous) ++ Map.keys(current)) |> Enum.uniq() |> List.delete(:hist)

    sub_diffs =
      Enum.flat_map(sub_entity_keys, fn key ->
        field_name = to_string(key)
        old_items = Map.get(previous, key, []) |> Enum.map(&struct_to_map/1)
        new_items = Map.get(current, key, []) |> Enum.map(&struct_to_map/1)
        sub_entity_diff(field_name, old_items, new_items)
      end)

    scalar_diffs ++ sub_diffs
  end

  defp struct_to_map(nil), do: nil

  defp struct_to_map(map) when is_map(map) and not is_struct(map), do: map

  defp struct_to_map(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__, :change, :change_id])
  end

  defp scalar_field_diffs(prev_hist, curr_hist) do
    old_map = struct_to_map(prev_hist) || %{}
    new_map = struct_to_map(curr_hist) || %{}

    (Map.keys(old_map) ++ Map.keys(new_map))
    |> Enum.uniq()
    |> Enum.filter(fn key -> Map.get(old_map, key) != Map.get(new_map, key) end)
    |> Enum.map(fn key ->
      old_val = Map.get(old_map, key)
      new_val = Map.get(new_map, key)

      if is_list(old_val) || is_list(new_val) do
        old_set = MapSet.new(old_val || [])
        new_set = MapSet.new(new_val || [])

        %{
          field: to_string(key),
          added: MapSet.difference(new_set, old_set) |> MapSet.to_list(),
          removed: MapSet.difference(old_set, new_set) |> MapSet.to_list()
        }
      else
        %{field: to_string(key), old: old_val, new: new_val}
      end
    end)
  end

  defp sub_entity_diff(_field_name, [], []), do: []

  defp sub_entity_diff(field_name, old_items, new_items) do
    case Map.get(@sub_entity_keys, field_name) do
      nil ->
        # Unknown collection — fall back to set-based added/removed diff.
        old_set = MapSet.new(old_items)
        new_set = MapSet.new(new_items)

        if MapSet.equal?(old_set, new_set) do
          []
        else
          [
            %{
              field: field_name,
              added: MapSet.difference(new_set, old_set) |> MapSet.to_list(),
              removed: MapSet.difference(old_set, new_set) |> MapSet.to_list(),
              changed: []
            }
          ]
        end

      key_fields ->
        identity_aware_diff(field_name, old_items, new_items, key_fields)
    end
  end

  defp identity_aware_diff(field_name, old_items, new_items, key_fields) do
    old_by_key = Map.new(old_items, &{row_key(&1, key_fields), &1})
    new_by_key = Map.new(new_items, &{row_key(&1, key_fields), &1})

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added =
      MapSet.difference(new_keys, old_keys)
      |> Enum.map(&Map.fetch!(new_by_key, &1))

    removed =
      MapSet.difference(old_keys, new_keys)
      |> Enum.map(&Map.fetch!(old_by_key, &1))

    changed =
      MapSet.intersection(old_keys, new_keys)
      |> Enum.flat_map(fn k ->
        old_row = Map.fetch!(old_by_key, k)
        new_row = Map.fetch!(new_by_key, k)
        field_diffs = row_field_diffs(old_row, new_row, key_fields)

        case field_diffs do
          [] -> []
          fields -> [%{key: serialize_row_key(k), old: old_row, new: new_row, fields: fields}]
        end
      end)

    if added == [] and removed == [] and changed == [] do
      []
    else
      [%{field: field_name, added: added, removed: removed, changed: changed}]
    end
  end

  defp row_key(row, key_fields), do: Enum.map(key_fields, &Map.get(row, &1))

  defp serialize_row_key([single]), do: single
  defp serialize_row_key(list), do: list

  defp row_field_diffs(old_row, new_row, key_fields) do
    ignore = MapSet.new(key_fields)

    (Map.keys(old_row) ++ Map.keys(new_row))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(ignore, &1))
    |> Enum.filter(fn k -> Map.get(old_row, k) != Map.get(new_row, k) end)
    |> Enum.map(fn k ->
      %{field: to_string(k), old: Map.get(old_row, k), new: Map.get(new_row, k)}
    end)
  end
end

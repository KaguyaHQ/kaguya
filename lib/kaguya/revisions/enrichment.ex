defmodule Kaguya.Revisions.Enrichment do
  @moduledoc """
  Decorates serialized revision snapshots and diffs with human-readable
  labels: reference UUIDs become titles/names, and image ids gain public URLs.

  Two entry points:

    * `enrich_one/4` — enrich a single revision's `{current, previous, diff}`,
      issuing its own lookup queries.
    * `enrich_many/1` — enrich a whole batch in one set of lookup queries,
      collecting every referenced id across the batch first. Used by the
      activity-feed diff loader to avoid per-change N+1 lookups.

  Snapshot/diff shapes are produced upstream by `Kaguya.Revisions.Diff`; this
  module never touches `_hist` structs directly.
  """

  import Ecto.Query
  alias Kaguya.Repo

  # Per-entity-type list of {field_in_main_hist, url_field, image_type, variant_suffix}.
  # url_field is the atom we set on the hist map so the frontend can read the
  # public URL alongside the id. Kept as a compile-time literal — never derive
  # it with String.to_atom on a runtime string.
  @image_main_fields %{
    visual_novel: [
      {:primary_image_id, :primary_image_id_url, :vn_cover, "256w"},
      {:featured_screenshot_id, :featured_screenshot_id_url, :vn_screenshot, "640w"}
    ],
    character: [
      {:primary_image_id, :primary_image_id_url, :character, "240w"}
    ],
    producer: [
      {:primary_image_id, :primary_image_id_url, :producer, "120w"}
    ],
    release: []
  }

  # Per-collection-name {snapshot_key_atom, id_field, image_type, variant_suffix}.
  # The string key matches the diff `field` name exposed to the UI; the
  # snapshot_key_atom is the corresponding key on the in-memory snapshot map.
  # Kept as a compile-time literal — never derive it with String.to_atom on
  # a runtime string.
  @image_sub_fields %{
    "covers" => {:covers, :cover_id, :vn_cover, "256w"},
    "screenshots" => {:screenshots, :screenshot_id, :vn_screenshot, "640w"},
    "images" => {:images, :image_id, :character, "240w"}
  }

  @doc """
  Enriches a single revision's snapshots + diff, loading its own lookups.
  """
  def enrich_one(entity_type, current, previous, diff) do
    {vn_ids, char_ids, producer_ids} = collect_reference_ids(current, previous, diff)
    lookups = load_lookups(vn_ids, char_ids, producer_ids)

    {current, previous, diff} = enrich_relations(current, previous, diff, lookups)
    enrich_images(entity_type, current, previous, diff)
  end

  @doc """
  Enriches a batch of revisions sharing one set of lookup queries.

  `entries` is a list of `{key, entity_type, current, previous, diff}`.
  Returns `%{key => {current, previous, diff}}`.
  """
  def enrich_many([]), do: %{}

  def enrich_many(entries) do
    {vn_ids, char_ids, producer_ids} =
      Enum.reduce(entries, {MapSet.new(), MapSet.new(), MapSet.new()}, fn
        {_key, _type, current, previous, diff}, {vn_acc, char_acc, producer_acc} ->
          {vns, chars, producers} = collect_reference_ids(current, previous, diff)

          {
            MapSet.union(vn_acc, MapSet.new(vns)),
            MapSet.union(char_acc, MapSet.new(chars)),
            MapSet.union(producer_acc, MapSet.new(producers))
          }
      end)

    lookups =
      load_lookups(MapSet.to_list(vn_ids), MapSet.to_list(char_ids), MapSet.to_list(producer_ids))

    Map.new(entries, fn {key, entity_type, current, previous, diff} ->
      {current, previous, diff} = enrich_relations(current, previous, diff, lookups)
      {current, previous, diff} = enrich_images(entity_type, current, previous, diff)
      {key, {current, previous, diff}}
    end)
  end

  # ============================================================================
  # Reference enrichment — resolves UUIDs to human-readable labels.
  # ============================================================================

  # Each underlying table is loaded once; `related_vn_id` and
  # `visual_novel_id` both resolve against the same VN title map.
  defp load_lookups(vn_ids, char_ids, producer_ids) do
    %{
      vn: batch_load(Kaguya.VisualNovels.VisualNovel, :title, vn_ids),
      char: batch_load(Kaguya.Characters.Character, :name, char_ids),
      producer: batch_load(Kaguya.Producers.Producer, :name, producer_ids)
    }
  end

  defp batch_load(_schema, _field, []), do: %{}

  defp batch_load(schema, field, ids) do
    from(e in schema, where: e.id in ^ids, select: {e.id, field(e, ^field)})
    |> Repo.all()
    |> Map.new()
  end

  defp enrich_relations(current, previous, diff, %{vn: vn, char: char, producer: producer}) do
    if vn == %{} and char == %{} and producer == %{} do
      {current, previous, diff}
    else
      # `appearances`/`entries` live on character revisions where
      # visual_novel_id is the child; `characters` lives on VN revisions where
      # character_id is the child — each side resolves the other's label.
      injectors = %{
        relations: &Map.put(&1, :related_vn_title, Map.get(vn, get_id(&1, :related_vn_id))),
        appearances: &Map.put(&1, :visual_novel_title, Map.get(vn, get_id(&1, :visual_novel_id))),
        entries: &Map.put(&1, :visual_novel_title, Map.get(vn, get_id(&1, :visual_novel_id))),
        characters: &Map.put(&1, :character_name, Map.get(char, get_id(&1, :character_id))),
        producers: &Map.put(&1, :producer_name, Map.get(producer, get_id(&1, :producer_id)))
      }

      enrich_snapshot = fn
        nil ->
          nil

        snap ->
          Enum.reduce(injectors, snap, fn {key, fun}, acc -> update_collection(acc, key, fun) end)
      end

      # Diff entries carry the collection name as a string `:field`; one table
      # dispatches all five instead of a clause per collection.
      diff_injectors = Map.new(injectors, fn {key, fun} -> {to_string(key), fun} end)

      enriched_diff =
        Enum.map(diff, fn %{field: field} = d ->
          case Map.get(diff_injectors, field) do
            nil -> d
            fun -> enrich_collection_entry(d, fun)
          end
        end)

      {enrich_snapshot.(current), enrich_snapshot.(previous), enriched_diff}
    end
  end

  defp collect_reference_ids(current, previous, diff) do
    snaps = [current, previous]

    vn_ids =
      Enum.flat_map(snaps, fn snap ->
        ids_in(snap, :relations, :related_vn_id) ++
          ids_in(snap, :appearances, :visual_novel_id) ++
          ids_in(snap, :entries, :visual_novel_id)
      end)

    char_ids = Enum.flat_map(snaps, &ids_in(&1, :characters, :character_id))
    producer_ids = Enum.flat_map(snaps, &ids_in(&1, :producers, :producer_id))

    diff_items =
      diff
      |> Enum.filter(&(&1.field in ~w(relations appearances entries characters producers)))
      |> Enum.flat_map(&collect_diff_items/1)

    diff_vn_ids =
      Enum.map(diff_items, &(get_id(&1, :related_vn_id) || get_id(&1, :visual_novel_id)))

    diff_char_ids = Enum.map(diff_items, &get_id(&1, :character_id))
    diff_producer_ids = Enum.map(diff_items, &get_id(&1, :producer_id))

    {
      uniq_compact(vn_ids ++ diff_vn_ids),
      uniq_compact(char_ids ++ diff_char_ids),
      uniq_compact(producer_ids ++ diff_producer_ids)
    }
  end

  defp ids_in(snap, key, field) do
    case snap && Map.get(snap, key) do
      list when is_list(list) -> Enum.map(list, &get_id(&1, field))
      _ -> []
    end
  end

  # Snapshot/diff rows reach us either atom-keyed (in-memory) or string-keyed
  # (post-JSON round-trip); read both so a single missed key can't silently
  # drop an enrichment.
  defp get_id(item, field), do: item[field] || item[Atom.to_string(field)]

  defp uniq_compact(ids), do: ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp enrich_collection_entry(d, fun) do
    d
    |> Map.update(:added, [], fn items -> Enum.map(items || [], fun) end)
    |> Map.update(:removed, [], fn items -> Enum.map(items || [], fun) end)
    |> Map.update(:changed, [], fn items ->
      Enum.map(items || [], fn change ->
        # `:old` and `:new` are always populated by the diff engine —
        # use Map.update! to fail loudly if the structural invariant breaks.
        change
        |> Map.update!(:old, fun)
        |> Map.update!(:new, fun)
      end)
    end)
  end

  defp update_collection(snap, key, fun) do
    case Map.get(snap, key) do
      nil -> snap
      list when is_list(list) -> Map.put(snap, key, Enum.map(list, fun))
    end
  end

  # ============================================================================
  # Image URL enrichment
  # ============================================================================

  defp enrich_images(entity_type, current, previous, diff) do
    main_fields = Map.get(@image_main_fields, entity_type, [])

    current = enrich_snapshot_images(current, main_fields)
    previous = enrich_snapshot_images(previous, main_fields)
    diff = Enum.map(diff, &enrich_diff_images/1)

    {current, previous, diff}
  end

  defp enrich_snapshot_images(nil, _main_fields), do: nil

  defp enrich_snapshot_images(snapshot, main_fields) do
    snapshot
    |> enrich_main_image_fields(main_fields)
    |> enrich_sub_image_collections()
  end

  defp enrich_main_image_fields(snapshot, main_fields) do
    # Main image fields (primary_image_id, featured_screenshot_id, ...) live
    # on the inner :hist map, not on the outer snapshot. Walk into :hist,
    # add the url siblings, then put the enriched hist back.
    case Map.get(snapshot, :hist) do
      nil ->
        snapshot

      hist ->
        enriched_hist =
          Enum.reduce(main_fields, hist, fn {id_field, url_field, image_type, suffix}, acc ->
            case Map.get(acc, id_field) do
              nil -> acc
              id -> Map.put(acc, url_field, image_url(image_type, id, suffix))
            end
          end)

        Map.put(snapshot, :hist, enriched_hist)
    end
  end

  defp enrich_sub_image_collections(snapshot) do
    Enum.reduce(@image_sub_fields, snapshot, fn {_field_name, {key, id_field, image_type, suffix}},
                                                acc ->
      case Map.get(acc, key) do
        nil ->
          acc

        list when is_list(list) ->
          enriched = Enum.map(list, &add_url_to_row(&1, id_field, image_type, suffix))
          Map.put(acc, key, enriched)
      end
    end)
  end

  defp add_url_to_row(row, id_field, image_type, suffix) do
    case Map.get(row, id_field) do
      nil -> row
      id -> Map.put(row, :url, image_url(image_type, id, suffix))
    end
  end

  # Sub-collection rows get URLs injected directly onto each row map (which
  # passes through to the frontend as JSON). Main scalar image fields like
  # primary_image_id are not enriched on the diff entry; the frontend reads
  # main image URLs from the snapshot's :hist map instead, which is enriched
  # by enrich_main_image_fields/2 above.
  defp enrich_diff_images(%{field: field} = d) do
    case Map.get(@image_sub_fields, field) do
      nil ->
        d

      {_snapshot_key, id_field, image_type, suffix} ->
        enrich_sub_image_diff(d, id_field, image_type, suffix)
    end
  end

  defp enrich_sub_image_diff(d, id_field, image_type, suffix) do
    enrich = &add_url_to_row(&1, id_field, image_type, suffix)

    d
    |> Map.update(:added, [], fn items -> Enum.map(items || [], enrich) end)
    |> Map.update(:removed, [], fn items -> Enum.map(items || [], enrich) end)
    |> Map.update(:changed, [], fn items ->
      Enum.map(items || [], fn change ->
        # `:old` and `:new` are always populated by the diff engine.
        change
        |> Map.update!(:old, enrich)
        |> Map.update!(:new, enrich)
      end)
    end)
  end

  defp image_url(type, id, suffix) do
    Kaguya.Images.url_for_key(Kaguya.Images.key(type, id, suffix))
  end

  defp collect_diff_items(d) do
    (d[:added] || []) ++
      (d[:removed] || []) ++
      Enum.flat_map(d[:changed] || [], fn c ->
        [c[:old], c[:new]] |> Enum.reject(&is_nil/1)
      end)
  end
end

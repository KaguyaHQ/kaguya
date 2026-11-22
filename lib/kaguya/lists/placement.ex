defmodule Kaguya.Lists.Placement do
  @moduledoc """
  Pure ordering and validation rules for list layouts.

  Works on plain item maps with `:item_id`, `:position`, `:tier_id`, and
  `:tier_position`, so it is shared by every list item type (VNs, characters)
  and knows nothing about tables. `Kaguya.Lists.Layout` handles persistence.
  """

  @type item :: %{
          required(:item_id) => term(),
          optional(:position) => pos_integer() | nil,
          optional(:tier_id) => term(),
          optional(:tier_position) => pos_integer() | nil
        }

  @doc """
  Checks submitted items before anything is written: positions must be
  positive integers when present, and every item needs a unique `:item_id`.
  Returns the item ids in submitted order.
  """
  def validate_items(items) when is_list(items) do
    ids = Enum.map(items, &Map.get(&1, :item_id))

    cond do
      Enum.any?(items, &invalid_positions?/1) -> {:error, :invalid_position}
      Enum.any?(ids, &is_nil/1) -> {:error, :missing_item_id}
      length(ids) != length(Enum.uniq(ids)) -> {:error, :duplicate_item}
      true -> {:ok, ids}
    end
  end

  def validate_items(_items), do: {:error, :invalid_list_items}

  @doc """
  Resolves final placement for every item and assigns flat `:position`s.

    * `previous` maps item id => `%{tier_id, tier_position}` already stored, so
      fields omitted from a payload keep their saved value (this is what lets
      grid ⇄ tier switches restore placements).
    * `tiers` are the saved tiers, `id_map` maps submitted (possibly temporary)
      tier ids to saved ids.

  Grid mode keeps the submitted flat order. Tier mode orders by tier, then by
  position within the tier, and renumbers `:tier_position` from 1. Unplaced
  items go last.
  """
  def arrange(display_mode, items, previous, %{tiers: tiers, id_map: id_map})
      when display_mode in ["grid", "tier"] do
    items = Enum.map(items, &with_tier_placement(&1, Map.get(previous, &1.item_id, %{}), id_map))
    tier_ids = MapSet.new(tiers, & &1.id)

    with :ok <- validate_tier_references(items, tier_ids),
         :ok <- validate_unique_tier_positions(items) do
      {:ok, display_mode |> order(items, tiers) |> assign_positions()}
    end
  end

  @doc """
  Re-numbers a flat ordered id list, carrying over saved tier placement.
  """
  def reorder(ordered_ids, previous) do
    ordered_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {item_id, position} ->
      saved = Map.get(previous, item_id, %{})

      %{
        item_id: item_id,
        position: position,
        tier_id: Map.get(saved, :tier_id),
        tier_position: Map.get(saved, :tier_position)
      }
    end)
  end

  defp invalid_positions?(item) do
    invalid_optional_positive_integer?(Map.get(item, :position)) or
      invalid_optional_positive_integer?(Map.get(item, :tier_position))
  end

  defp invalid_optional_positive_integer?(nil), do: false
  defp invalid_optional_positive_integer?(value) when is_integer(value), do: value < 1
  defp invalid_optional_positive_integer?(_), do: true

  defp with_tier_placement(item, saved, id_map) do
    tier_id = field_or_saved(item, :tier_id, saved)

    item
    |> Map.put(:tier_id, if(tier_id, do: Map.get(id_map, tier_id, tier_id)))
    |> Map.put(:tier_position, field_or_saved(item, :tier_position, saved))
  end

  defp field_or_saved(item, field, saved) do
    if Map.has_key?(item, field), do: Map.get(item, field), else: Map.get(saved, field)
  end

  defp validate_tier_references(items, tier_ids) do
    if Enum.all?(items, &(is_nil(&1.tier_id) or MapSet.member?(tier_ids, &1.tier_id))),
      do: :ok,
      else: {:error, :tier_not_found}
  end

  defp validate_unique_tier_positions(items) do
    duplicate? =
      items
      |> Enum.reject(&(is_nil(&1.tier_id) or is_nil(&1.tier_position)))
      |> Enum.group_by(& &1.tier_id, & &1.tier_position)
      |> Enum.any?(fn {_tier_id, positions} ->
        length(positions) != length(Enum.uniq(positions))
      end)

    if duplicate?, do: {:error, :duplicate_tier_position}, else: :ok
  end

  defp order("grid", items, _tiers) do
    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, idx} -> {Map.get(item, :position) || idx + 1, idx} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp order("tier", items, tiers) do
    tier_rank =
      tiers |> Enum.with_index() |> Map.new(fn {t, idx} -> {t.id, {t.position, idx}} end)

    unplaced = {999_999, 999_999}

    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, idx} ->
      rank = if item.tier_id, do: Map.fetch!(tier_rank, item.tier_id), else: unplaced
      {rank, item.tier_position || Map.get(item, :position) || idx + 1, idx}
    end)
    |> Enum.map(&elem(&1, 0))
    |> renumber_tier_positions()
  end

  defp renumber_tier_positions(items) do
    {items, _counts} =
      Enum.map_reduce(items, %{}, fn
        %{tier_id: nil} = item, counts ->
          {%{item | tier_position: nil}, counts}

        %{tier_id: tier_id} = item, counts ->
          position = Map.get(counts, tier_id, 0) + 1
          {%{item | tier_position: position}, Map.put(counts, tier_id, position)}
      end)

    items
  end

  defp assign_positions(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, position} ->
      %{
        item_id: item.item_id,
        position: position,
        tier_id: item.tier_id,
        tier_position: item.tier_position
      }
    end)
  end
end

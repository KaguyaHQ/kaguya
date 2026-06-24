defmodule Kaguya.Uploads.Helpers.VndbPrefetcher do
  @moduledoc """
  Preloads lookup tables into the accumulator so row-parsers can work
  without per-row DB hits.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.{VisualNovel, BannedVndbId}

  # Pattern to match VNDB IDs in text (v123, v123.4, c456, etc.)
  # Supports optional .# suffix for sub-items
  @vndb_id_pattern ~r/\b([vcprsud])(\d+)(?:\.\d+)?\b/

  @doc """
  Prefetches all VN data needed for import in a single query.

  Collects IDs from:
  - VN entries in the import (vndb_id field)
  - Reviews (vndb_id field)
  - VN ID references in review texts (v123, etc.)

  Returns updated accumulator with:
  - `:vn_map` - Map of vndb_id (string like "v25288") → visual_novel_id (uuid)
  - `:vn_link_map` - Map of numeric vndb_id (string like "25288") → %{slug: string, title: string}
  """
  def prefetch(acc, vns, reviews \\ []) do
    # Collect vndb_ids from VN entries
    vn_ids_from_vns =
      vns
      |> Enum.map(& &1.vndb_id)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    # Collect from reviews (vndb_id field)
    vn_ids_from_reviews =
      reviews
      |> Enum.map(& &1.vndb_id)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    # Extract vndb_ids from review texts (for VN ID linking)
    vn_ids_from_text =
      reviews
      |> Enum.flat_map(fn review ->
        extract_vn_ids_from_text(review.text)
      end)

    # Combine all and dedupe (all in "v25288" format)
    all_vndb_ids =
      (vn_ids_from_vns ++ vn_ids_from_reviews ++ vn_ids_from_text)
      |> Enum.uniq()

    # Single query to fetch id, slug, title, and image fields
    {vn_map, vn_link_map, vn_detail_map} =
      if all_vndb_ids == [] do
        {%{}, %{}, %{}}
      else
        results =
          VisualNovel
          |> where([v], v.vndb_id in ^all_vndb_ids)
          |> select(
            [v],
            {v.vndb_id, v.id, v.slug, v.title, v.primary_image_id, v.temp_image_url,
             v.release_date, v.is_image_nsfw, v.is_image_suggestive}
          )
          |> Repo.all()

        # Build all maps from single query results
        vn_map =
          results
          |> Enum.map(fn {vndb_id, id, _slug, _title, _img, _tmp, _rd, _nsfw, _sug} ->
            {vndb_id, id}
          end)
          |> Map.new()

        vn_link_map =
          results
          |> Enum.map(fn {vndb_id, _id, slug, title, _img, _tmp, _rd, _nsfw, _sug} ->
            {strip_v_prefix(vndb_id), %{slug: slug, title: title}}
          end)
          |> Map.new()

        vn_detail_map =
          results
          |> Enum.map(fn {_vndb_id, id, slug, title, img_id, tmp_url, release_date, nsfw,
                          suggestive} ->
            {id,
             %{
               slug: slug,
               title: title,
               primary_image_id: img_id,
               temp_image_url: tmp_url,
               release_date: release_date,
               is_image_nsfw: nsfw,
               is_image_suggestive: suggestive
             }}
          end)
          |> Map.new()

        {vn_map, vn_link_map, vn_detail_map}
      end

    # Only check banned status for IDs not found in our database
    missing_vndb_ids = all_vndb_ids -- Map.keys(vn_map)

    banned_map =
      if missing_vndb_ids == [] do
        %{}
      else
        BannedVndbId
        |> where([b], b.vndb_id in ^missing_vndb_ids)
        |> select([b], {b.vndb_id, b.title})
        |> Repo.all()
        |> Map.new()
      end

    acc
    |> Map.put(:vn_map, vn_map)
    |> Map.put(:vn_link_map, vn_link_map)
    |> Map.put(:vn_detail_map, vn_detail_map)
    |> Map.put(:banned_map, banned_map)
  end

  # Extract VN IDs from text, returns base "v25288" format for DB query
  # (strips .# suffix since DB only stores base IDs)
  defp extract_vn_ids_from_text(nil), do: []
  defp extract_vn_ids_from_text(""), do: []

  defp extract_vn_ids_from_text(text) do
    @vndb_id_pattern
    |> Regex.scan(text)
    |> Enum.filter(fn [_, type, _id] -> type == "v" end)
    |> Enum.map(fn [_full_match, type, id] -> "#{type}#{id}" end)
  end

  # Strip "v" prefix from vndb_id (handles both "v123" and "123" formats)
  defp strip_v_prefix("v" <> id), do: id
  defp strip_v_prefix(id), do: id
end

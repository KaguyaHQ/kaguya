defmodule Kaguya.Sync.DumpSync.Images.ImageMapping do
  @moduledoc """
  Manages UUID assignments for VNDB image IDs.

  Fresh ETS table each run for fast concurrent reads during processing.
  `export/0` writes a rich mapping (with dimensions and relationships)
  for cross-env import via `priv/repo/scripts/images/import_image_mapping.exs`.

  Each run starts fresh — only the current run's assignments are tracked,
  keeping exports delta-only for periodic syncs.
  """

  require Logger

  @table :image_id_mapping
  @export_path "priv/image_id_mapping.json"

  @doc """
  Create a fresh ETS table for this run's UUID assignments.
  """
  def start do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
  end

  @doc """
  Delete the ETS table.
  """
  def stop do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  end

  @doc """
  Look up or create a UUID for the given VNDB image ID.

  ETS hit → return existing UUID.
  ETS miss → generate UUIDv7, insert, return.
  """
  def get_or_create(vndb_id) do
    case :ets.lookup(@table, vndb_id) do
      [{^vndb_id, uuid}] ->
        uuid

      [] ->
        uuid = UUIDv7.generate()

        # insert_new returns false if another process inserted first.
        # Always read back the winner to handle races.
        :ets.insert_new(@table, {vndb_id, uuid})
        [{^vndb_id, winner}] = :ets.lookup(@table, vndb_id)
        winner
    end
  end

  @doc """
  Export only the records processed this run (IDs in ETS) with dimensions
  and relationships from the DB, for cross-env import.
  """
  def export(path \\ @export_path) do
    import Ecto.Query

    alias Kaguya.Repo

    # Only export records whose IDs were generated this run
    current_ids =
      @table
      |> :ets.tab2list()
      |> Map.new()
      |> Map.values()
      |> MapSet.new()

    # Load primary_image_ids to distinguish primary covers from alt covers
    primary_image_ids =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: vn.primary_image_id in ^MapSet.to_list(current_ids),
        select: vn.primary_image_id
      )
      |> Repo.all()
      |> MapSet.new()

    all_covers =
      from(img in Kaguya.VisualNovels.Image,
        join: vn in assoc(img, :visual_novel),
        where: img.id in ^MapSet.to_list(current_ids),
        select: %{
          vndb_cv_id: img.vndb_cv_id,
          id: img.id,
          width: img.width,
          height: img.height,
          vndb_vn_id: vn.vndb_id,
          vndb_votes: img.vndb_votes,
          language: img.language,
          release_date: img.release_date,
          is_image_nsfw: img.is_image_nsfw,
          is_image_suggestive: img.is_image_suggestive
        }
      )
      |> Repo.all()

    {primary_list, alt_list} =
      Enum.split_with(all_covers, fn row -> MapSet.member?(primary_image_ids, row.id) end)

    covers =
      Map.new(primary_list, fn row ->
        {row.id,
         %{
           "vndb_cv_id" => row.vndb_cv_id,
           "width" => row.width,
           "height" => row.height,
           "vndb_vn_id" => row.vndb_vn_id
         }}
      end)

    alt_covers =
      Map.new(alt_list, fn row ->
        {row.id,
         %{
           "vndb_cv_id" => row.vndb_cv_id,
           "width" => row.width,
           "height" => row.height,
           "vndb_vn_id" => row.vndb_vn_id,
           "vndb_votes" => row.vndb_votes,
           "language" => row.language,
           "release_date" => row.release_date && Date.to_iso8601(row.release_date),
           "is_image_nsfw" => row.is_image_nsfw,
           "is_image_suggestive" => row.is_image_suggestive
         }}
      end)

    characters =
      from(img in Kaguya.Characters.CharacterImage,
        join: c in assoc(img, :character),
        where: img.id in ^MapSet.to_list(current_ids),
        select: %{
          vndb_image_id: c.vndb_image_id,
          id: img.id,
          width: img.width,
          height: img.height,
          vndb_char_id: c.vndb_id
        }
      )
      |> Repo.all()
      |> Map.new(fn row ->
        {row.vndb_image_id,
         %{
           "id" => row.id,
           "width" => row.width,
           "height" => row.height,
           "vndb_char_id" => row.vndb_char_id
         }}
      end)

    screenshots =
      from(s in Kaguya.Screenshots.Screenshot,
        join: vn in assoc(s, :visual_novel),
        where: s.id in ^MapSet.to_list(current_ids),
        select: %{
          vndb_sf_id: s.vndb_sf_id,
          id: s.id,
          width: s.width,
          height: s.height,
          vndb_vn_id: vn.vndb_id
        }
      )
      |> Repo.all()
      |> Map.new(fn row ->
        {row.vndb_sf_id,
         %{
           "id" => row.id,
           "width" => row.width,
           "height" => row.height,
           "vndb_vn_id" => row.vndb_vn_id
         }}
      end)

    # Export featured_screenshot_id for VNs that have one set and the screenshot
    # was processed this run (its ID is in ETS)
    current_id_list = MapSet.to_list(current_ids)

    featured =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        where: vn.featured_screenshot_id in ^current_id_list,
        select: {vn.vndb_id, vn.featured_screenshot_id}
      )
      |> Repo.all()
      |> Map.new(fn {vndb_id, screenshot_id} -> {vndb_id, screenshot_id} end)

    full = %{
      "covers" => covers,
      "alt_covers" => alt_covers,
      "characters" => characters,
      "screenshots" => screenshots,
      "featured" => featured
    }

    json = Jason.encode!(full, pretty: true)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, json)

    Logger.info(
      "ImageMapping: exported #{map_size(covers)} covers, #{map_size(alt_covers)} alt covers, " <>
        "#{map_size(characters)} characters, #{map_size(screenshots)} screenshots, " <>
        "#{map_size(featured)} featured to #{path}"
    )

    :ok
  end
end

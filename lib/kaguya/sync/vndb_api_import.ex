defmodule Kaguya.Sync.VndbApiImport do
  @moduledoc """
  On-demand single VN import from VNDB.

  Accepts a VNDB ID ("v17") or URL ("https://vndb.org/v17").
  Fetches VN + characters + tags + relations + developers + releases,
  indexes in Meilisearch, and returns the complete VN.
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.{VndbApiClient, VndbFieldMapper, VndbEnrichment}
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle, BannedVndbId}

  @vndb_id_regex ~r/^v\d+$/
  @vndb_url_regex ~r{(?:https?://)?vndb\.org/(v\d+)}

  @doc """
  Import a single VN by VNDB ID or URL.
  Synchronous — fetches, enriches, indexes, returns complete VN.
  """
  def import_vn(input) do
    with {:ok, vndb_id} <- parse_vndb_input(input),
         :ok <- check_not_banned(vndb_id),
         nil <- Repo.one(from v in VisualNovel, where: v.vndb_id == ^vndb_id),
         {:ok, vn_data} <- VndbApiClient.get_vn(vndb_id, throttle: false),
         {:ok, vn} <- insert_vn(vndb_id, vn_data) do
      enrich_and_index_vn(vn, vn_data)
      create_initial_revision(vn)
      {:ok, Repo.preload(vn, [:vn_producers])}
    else
      %VisualNovel{} = existing -> {:ok, existing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_vndb_input(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      Regex.match?(@vndb_id_regex, input) ->
        {:ok, input}

      match = Regex.run(@vndb_url_regex, input) ->
        {:ok, Enum.at(match, 1)}

      true ->
        {:error, :invalid_vndb_id}
    end
  end

  defp parse_vndb_input(_), do: {:error, :invalid_vndb_id}

  defp check_not_banned(vndb_id) do
    if Repo.exists?(from b in BannedVndbId, where: b.vndb_id == ^vndb_id),
      do: {:error, :banned},
      else: :ok
  end

  defp insert_vn(vndb_id, vn_data) do
    {is_nsfw, is_suggestive} = VndbFieldMapper.image_flags_from_vn(vn_data)

    title =
      VndbFieldMapper.resolve_title(vn_data["titles"], vn_data["olang"]) || vn_data["title"] ||
        "Untitled"

    aliases = VndbFieldMapper.parse_latin_aliases(vn_data["aliases"])

    attrs = %{
      title: title,
      aliases: aliases,
      description: VndbFieldMapper.clean_description(vn_data["description"]),
      vndb_id: vndb_id,
      development_status: VndbFieldMapper.map_development_status(vn_data["devstatus"]),
      length_minutes: vn_data["length_minutes"],
      length_category:
        VndbFieldMapper.map_length_category(vn_data["length"]) ||
          VndbFieldMapper.length_category_from_minutes(vn_data["length_minutes"]),
      original_language: vn_data["olang"],
      release_date: VndbFieldMapper.parse_api_release_date(vn_data["released"]),
      is_image_nsfw: is_nsfw,
      is_image_suggestive: is_suggestive,
      vndb_rating: VndbFieldMapper.convert_api_rating(vn_data["average"]),
      vndb_vote_count: vn_data["votecount"],
      temp_image_url: VndbFieldMapper.image_url_from_vn(vn_data),
      title_category: :vn
    }

    case %VisualNovel{} |> VisualNovel.changeset(attrs) |> Repo.insert() do
      {:ok, vn} ->
        upsert_vn_titles(vn.id, vn_data["titles"] || [])
        {:ok, vn}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :vndb_id) or Keyword.has_key?(errors, :slug) do
          case Repo.one(from v in VisualNovel, where: v.vndb_id == ^vndb_id) do
            %VisualNovel{} = existing -> {:ok, existing}
            nil -> {:error, changeset}
          end
        else
          {:error, changeset}
        end
    end
  end

  defp upsert_vn_titles(vn_uuid, titles) do
    rows =
      Enum.map(titles, fn t ->
        %{
          id: UUIDv7.generate(),
          visual_novel_id: vn_uuid,
          lang: t["lang"],
          official: t["official"] == true,
          title: t["title"] || "Unknown",
          latin: t["latin"]
        }
      end)

    if rows != [] do
      Repo.insert_all(VNTitle, rows,
        on_conflict: {:replace, [:official, :title, :latin]},
        conflict_target: [:visual_novel_id, :lang]
      )
    end
  end

  defp enrich_and_index_vn(vn, vn_data) do
    vn_id_map = %{vn.vndb_id => vn.id}
    VndbEnrichment.enrich_vns([vn_data], vn_id_map, [vn.vndb_id], throttle: false)
    Logger.info("[VndbImport] Import complete for #{vn.vndb_id}")
  end

  defp create_initial_revision(vn) do
    Kaguya.Revisions.create_system_change(:visual_novel, vn.id, "Imported from VNDB",
      source: :vndb_sync
    )
  rescue
    e ->
      Logger.warning(
        "[VndbImport] Failed to create revision for #{vn.vndb_id}: #{Exception.message(e)}"
      )
  end
end

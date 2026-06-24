defmodule Kaguya.Sync.VndbEnrichment do
  @moduledoc """
  Shared enrichment logic for VNDB data.

  Used by both VndbApiImport (on-demand, single VN) and VndbSync (weekly, bulk).
  All functions accept lists and work efficiently at any scale.

  Entry point: `enrich_vns/4` — orchestrates all enrichment steps:
    - `import_*` functions write already-fetched data to DB
    - `fetch_and_import_*` functions call VNDB API first, then write to DB
    - Indexes VNs and characters in Meilisearch
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Sync.{VndbApiClient, VndbFieldMapper, VndbStorefrontMapper}
  alias Kaguya.VisualNovels.{VisualNovel, VNTag, Relation}
  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Producers.{Producer, ProducerExternalLink, VNProducer}
  alias Kaguya.Releases.{Release, ReleaseExtlink, ReleaseTitleHelper}
  alias Kaguya.Tags.Tag
  alias Kaguya.Utils.SlugUtils
  alias Kaguya.SearchIndex

  @chunk_size 500

  # ── Main Orchestration ──────────────────────────────────────────────────

  @doc """
  Enrich VNs with all related data and index in Meilisearch.

  Imports tags, relations, and developers from already-fetched VN data.
  Fetches characters and releases from VNDB API, then imports them.
  Indexes VNs and characters in Meilisearch.

  Returns `%{tags: count, chars: count}`.

  Options:
    - `:throttle` — throttle API calls (default: true)
  """
  def enrich_vns(vn_data_list, vn_id_map, vndb_ids, opts \\ []) do
    # Import from already-fetched VN data (no additional API calls)
    tags_count =
      safe_enrich("tags", fn ->
        import_tags(vn_data_list, vn_id_map, opts)
      end)

    safe_enrich("relations", fn ->
      import_relations(vn_data_list, vn_id_map)
    end)

    safe_enrich("developers", fn ->
      import_developers(vn_data_list, vn_id_map)
    end)

    # Fetch from VNDB API, then import to DB
    chars_result =
      safe_enrich("characters", fn ->
        fetch_and_import_characters(vndb_ids, vn_id_map, opts)
      end)

    {chars_count, char_vndb_ids} = chars_result || {0, []}

    safe_enrich("releases", fn ->
      fetch_and_import_releases(vndb_ids, vn_id_map, opts)
    end)

    # Collect producer vndb_ids from the VN data for Meilisearch indexing
    producer_vndb_ids =
      vn_data_list
      |> Enum.flat_map(fn vn -> Enum.map(vn["developers"] || [], & &1["id"]) end)
      |> Enum.uniq()

    # Index in Meilisearch
    index_vns(vndb_ids)
    index_characters(char_vndb_ids)
    index_producers(producer_vndb_ids)

    %{tags: tags_count || 0, chars: chars_count}
  end

  # ── Fetch + Import (requires VNDB API call) ─────────────────────────────

  defp fetch_and_import_characters(vndb_ids, vn_id_map, opts) do
    case VndbApiClient.list_characters_for_vns(vndb_ids, opts) do
      {:ok, characters} ->
        import_characters(characters, vn_id_map)

      {:error, reason} ->
        Logger.error("[VndbEnrichment] Failed to fetch characters: #{inspect(reason)}")
        {0, []}
    end
  end

  defp fetch_and_import_releases(vndb_ids, vn_id_map, opts) do
    case VndbApiClient.list_releases_for_vns(vndb_ids, opts) do
      {:ok, releases} ->
        import_releases(releases, vndb_ids, vn_id_map)

      {:error, reason} ->
        Logger.warning("[VndbEnrichment] Failed to fetch releases: #{inspect(reason)}")
    end
  end

  # ── Import (data already fetched) ───────────────────────────────────────

  # ── Tags ──────────────────────────────────────────────────────────────────

  @doc """
  Import tags from VN API response data.
  Auto-creates missing tags via VNDB API when needed.

  Options:
    - `:throttle` — throttle tag auto-creation API calls (default: true)
  """
  def import_tags(vn_data_list, vn_id_map, opts \\ [])
  def import_tags([], _vn_id_map, _opts), do: 0

  def import_tags(vn_data_list, vn_id_map, opts) do
    now = now()

    explicit_useless = MapSet.new(Kaguya.Sync.DumpSync.Tags.explicit_useless_tags())

    # Collect {vn_uuid, tag_api_data} for all relevant tags
    tag_pairs =
      Enum.flat_map(vn_data_list, fn vn ->
        case Map.get(vn_id_map, vn["id"]) do
          nil ->
            []

          vn_uuid ->
            (vn["tags"] || [])
            |> Enum.filter(&VndbFieldMapper.relevant_tag?(&1["rating"]))
            |> Enum.reject(&MapSet.member?(explicit_useless, &1["id"]))
            |> Enum.map(&{vn_uuid, &1})
        end
      end)

    if tag_pairs == [] do
      0
    else
      needed_vndb_ids = tag_pairs |> Enum.map(fn {_, t} -> t["id"] end) |> Enum.uniq()

      tag_map =
        Repo.all(
          from t in Tag, where: t.vndb_tag_id in ^needed_vndb_ids, select: {t.vndb_tag_id, t.id}
        )
        |> Map.new()

      # Auto-create tags not yet in our DB. Explicit useless tags are filtered above;
      # hierarchy-based useless tags rely on the next full dump sync to clean up.
      missing_ids = Enum.reject(needed_vndb_ids, &Map.has_key?(tag_map, &1))

      tag_map =
        if missing_ids != [], do: auto_create_tags(missing_ids, tag_map, opts), else: tag_map

      rows =
        Enum.flat_map(tag_pairs, fn {vn_uuid, t} ->
          case Map.get(tag_map, t["id"]) do
            nil ->
              []

            tag_id ->
              [
                %{
                  visual_novel_id: vn_uuid,
                  tag_id: tag_id,
                  vndb_vote_count: 0,
                  vndb_avg_score: t["rating"] && t["rating"] * 1.0,
                  relevance_score: 0.0,
                  spoiler_level: VndbFieldMapper.map_spoiler_level(t["spoiler"] || 0),
                  inserted_at: now,
                  updated_at: now
                }
              ]
          end
        end)

      chunked_insert(VNTag, rows,
        on_conflict: {:replace, [:vndb_avg_score, :spoiler_level, :updated_at]},
        conflict_target: {:unsafe_fragment, "ON CONSTRAINT vn_tags_pkey"}
      )
    end
  end

  defp auto_create_tags(missing_ids, tag_map, opts) do
    throttle = Keyword.get(opts, :throttle, true)

    case VndbApiClient.get_tags_by_ids(missing_ids, throttle: throttle) do
      {:ok, api_tags} when api_tags != [] ->
        now = now()

        tag_rows =
          Enum.map(api_tags, fn t ->
            %{
              id: UUIDv7.generate(),
              vndb_tag_id: t["id"],
              name: VndbFieldMapper.sanitize_utf8(t["name"]) || "Unknown Tag",
              slug: "placeholder-#{t["id"]}",
              description: VndbFieldMapper.clean_description(t["description"]),
              category: VndbFieldMapper.map_tag_category(t["category"]),
              source: "vndb",
              inserted_at: now,
              updated_at: now
            }
          end)

        slugged =
          SlugUtils.build_unique_slugs(tag_rows, Tag, :slug, & &1.name)
          |> Enum.map(fn row -> row |> Map.put(:slug, row._slug) |> Map.delete(:_slug) end)

        Repo.insert_all(Tag, slugged, on_conflict: :nothing, conflict_target: [:vndb_tag_id])

        # Reload to get IDs (handles race conditions)
        new_tags =
          Repo.all(
            from t in Tag, where: t.vndb_tag_id in ^missing_ids, select: {t.vndb_tag_id, t.id}
          )
          |> Map.new()

        Map.merge(tag_map, new_tags)

      _ ->
        Logger.warning(
          "[VndbEnrichment] Failed to fetch #{length(missing_ids)} missing tags from API"
        )

        tag_map
    end
  end

  # ── Characters ────────────────────────────────────────────────────────────

  @character_replace_fields [
    :name,
    :description,
    :sex,
    :spoiler_sex,
    :gender,
    :spoiler_gender,
    :blood_type,
    :height,
    :weight,
    :age,
    :birthday,
    :bust,
    :waist,
    :hip,
    :cup_size,
    :temp_image_url,
    :is_image_nsfw,
    :is_image_suggestive,
    :slug,
    :updated_at
  ]

  @doc """
  Import characters from API response data.
  Returns `{upserted_count, char_vndb_ids}`.
  """
  def import_characters([], _vn_id_map), do: {0, []}

  def import_characters(characters, vn_id_map) do
    now = now()

    char_rows = Enum.map(characters, &build_character_row(&1, now))

    slugged =
      SlugUtils.build_unique_slugs(char_rows, Character, :slug, & &1.name)
      |> Enum.map(fn row -> row |> Map.put(:slug, row._slug) |> Map.delete(:_slug) end)

    count =
      chunked_insert(Character, slugged,
        on_conflict: {:replace, @character_replace_fields},
        conflict_target: [:vndb_id]
      )

    # Build char vndb_id → uuid map (scoped to these characters)
    char_vndb_ids = Enum.map(characters, & &1["id"])

    char_id_map =
      Repo.all(from c in Character, where: c.vndb_id in ^char_vndb_ids, select: {c.vndb_id, c.id})
      |> Map.new()

    # Build VN-character junction rows
    junction_rows =
      Enum.flat_map(characters, fn char ->
        case Map.get(char_id_map, char["id"]) do
          nil ->
            []

          char_uuid ->
            (char["vns"] || [])
            |> Enum.flat_map(fn va ->
              case Map.get(vn_id_map, va["id"]) do
                nil ->
                  []

                vn_uuid ->
                  [
                    %{
                      character_id: char_uuid,
                      visual_novel_id: vn_uuid,
                      role: VndbFieldMapper.map_character_role(va["role"]),
                      spoiler_level: va["spoiler"] || 0,
                      inserted_at: now,
                      updated_at: now
                    }
                  ]
              end
            end)
        end
      end)

    chunked_insert(VNCharacter, junction_rows,
      on_conflict: {:replace, [:role, :spoiler_level, :updated_at]},
      conflict_target: [:visual_novel_id, :character_id]
    )

    {count, char_vndb_ids}
  end

  defp build_character_row(char, now) do
    name = VndbFieldMapper.sanitize_utf8(char["name"]) || char["original"] || "Unknown"
    {sex, spoiler_sex} = VndbFieldMapper.parse_api_sex_field(char["sex"])
    {gender, spoiler_gender} = VndbFieldMapper.parse_api_gender_field(char["gender"])
    {is_nsfw, is_suggestive} = VndbFieldMapper.image_flags_from_image(char["image"])

    %{
      id: UUIDv7.generate(),
      vndb_id: char["id"],
      name: name,
      description: VndbFieldMapper.clean_description(char["description"]),
      sex: sex,
      spoiler_sex: spoiler_sex,
      gender: gender,
      spoiler_gender: spoiler_gender,
      blood_type: VndbFieldMapper.map_blood_type(char["blood_type"]),
      height: VndbFieldMapper.nullify_zero(char["height"]),
      weight: char["weight"],
      age: char["age"],
      birthday: VndbFieldMapper.parse_birthday(char["birthday"]),
      bust: VndbFieldMapper.nullify_zero(char["bust"]),
      waist: VndbFieldMapper.nullify_zero(char["waist"]),
      hip: VndbFieldMapper.nullify_zero(char["hips"]),
      cup_size: VndbFieldMapper.nullify_empty(char["cup"]),
      temp_image_url: VndbFieldMapper.image_url_from_image(char["image"]),
      is_image_nsfw: is_nsfw,
      is_image_suggestive: is_suggestive,
      inserted_at: now,
      updated_at: now
    }
  end

  # ── Relations ─────────────────────────────────────────────────────────────

  @doc """
  Import VN relations from API response data.
  Looks up related VNs in the DB if not already in vn_id_map.
  """
  def import_relations([], _vn_id_map), do: 0

  def import_relations(vn_data_list, vn_id_map) do
    now = now()

    # Collect related vndb_ids not in the provided map
    all_related_vndb_ids =
      Enum.flat_map(vn_data_list, fn vn ->
        (vn["relations"] || []) |> Enum.map(& &1["id"])
      end)
      |> Enum.uniq()

    missing = Enum.reject(all_related_vndb_ids, &Map.has_key?(vn_id_map, &1))

    full_id_map =
      if missing != [] do
        extra =
          Repo.all(from v in VisualNovel, where: v.vndb_id in ^missing, select: {v.vndb_id, v.id})
          |> Map.new()

        Map.merge(vn_id_map, extra)
      else
        vn_id_map
      end

    rows =
      Enum.flat_map(vn_data_list, fn vn ->
        case Map.get(full_id_map, vn["id"]) do
          nil ->
            []

          vn_uuid ->
            (vn["relations"] || [])
            |> Enum.flat_map(fn rel ->
              case Map.get(full_id_map, rel["id"]) do
                nil ->
                  []

                related_vn_id ->
                  [
                    %{
                      visual_novel_id: vn_uuid,
                      related_vn_id: related_vn_id,
                      relation_type: VndbFieldMapper.map_relation_type(rel["relation"]),
                      is_official: rel["relation_official"] == true,
                      inserted_at: now,
                      updated_at: now
                    }
                  ]
              end
            end)
        end
      end)

    chunked_insert(Relation, rows,
      on_conflict: {:replace, [:relation_type, :is_official, :updated_at]},
      conflict_target: [:visual_novel_id, :related_vn_id]
    )
  end

  # ── Developers ────────────────────────────────────────────────────────────

  @doc """
  Import developers from VN API response data.
  Auto-creates missing producers, enriches existing ones, upserts extlinks.
  """
  def import_developers([], _vn_id_map), do: 0

  def import_developers(vn_data_list, vn_id_map) do
    now = now()

    # Collect {vn_uuid, developer_api_data} pairs
    dev_pairs =
      Enum.flat_map(vn_data_list, fn vn ->
        case Map.get(vn_id_map, vn["id"]) do
          nil -> []
          vn_uuid -> (vn["developers"] || []) |> Enum.map(&{vn_uuid, &1})
        end
      end)

    if dev_pairs == [] do
      0
    else
      all_devs = dev_pairs |> Enum.map(fn {_, dev} -> dev end) |> Enum.uniq_by(& &1["id"])
      dev_vndb_ids = Enum.map(all_devs, & &1["id"])

      existing_map =
        Repo.all(from p in Producer, where: p.vndb_id in ^dev_vndb_ids, select: {p.vndb_id, p.id})
        |> Map.new()

      # Auto-create missing producers
      missing_devs = Enum.reject(all_devs, &Map.has_key?(existing_map, &1["id"]))

      new_map =
        if missing_devs != [] do
          create_missing_producers(missing_devs, now)
        else
          %{}
        end

      producer_id_map = Map.merge(existing_map, new_map)

      # Enrich existing producers with latest data
      enrich_existing_producers(all_devs, existing_map, now)

      # Build developer junction rows
      junction_rows =
        Enum.flat_map(dev_pairs, fn {vn_uuid, dev} ->
          case Map.get(producer_id_map, dev["id"]) do
            nil ->
              []

            producer_id ->
              [
                %{
                  visual_novel_id: vn_uuid,
                  producer_id: producer_id,
                  role: "developer",
                  inserted_at: now,
                  updated_at: now
                }
              ]
          end
        end)

      chunked_insert(VNProducer, junction_rows,
        on_conflict: {:replace, [:role, :updated_at]},
        conflict_target: [:visual_novel_id, :producer_id]
      )

      # Upsert extlinks for all producers
      upsert_producer_extlinks(all_devs, producer_id_map, now)

      length(junction_rows)
    end
  end

  defp create_missing_producers(missing_devs, now) do
    new_rows =
      Enum.map(missing_devs, fn dev ->
        %{
          id: UUIDv7.generate(),
          vndb_id: dev["id"],
          name:
            VndbFieldMapper.sanitize_utf8(dev["name"]) || dev["original"] || "Unknown Producer",
          description: VndbFieldMapper.clean_description(dev["description"]),
          producer_type: VndbFieldMapper.map_producer_type(dev["type"]),
          language: dev["lang"],
          slug: "placeholder-#{dev["id"]}",
          inserted_at: now,
          updated_at: now
        }
      end)

    slugged =
      SlugUtils.build_unique_slugs(new_rows, Producer, :slug, & &1.name)
      |> Enum.map(fn row -> row |> Map.put(:slug, row._slug) |> Map.delete(:_slug) end)

    Repo.insert_all(Producer, slugged, on_conflict: :nothing, conflict_target: [:vndb_id])

    # Reload to get IDs (handles race conditions)
    new_vndb_ids = Enum.map(missing_devs, & &1["id"])

    Repo.all(from p in Producer, where: p.vndb_id in ^new_vndb_ids, select: {p.vndb_id, p.id})
    |> Map.new()
  end

  defp enrich_existing_producers(developers, existing_map, now) do
    Enum.each(developers, fn dev ->
      case Map.get(existing_map, dev["id"]) do
        nil ->
          :ok

        producer_id ->
          from(p in Producer, where: p.id == ^producer_id)
          |> Repo.update_all(
            set: [
              description: VndbFieldMapper.clean_description(dev["description"]),
              producer_type: VndbFieldMapper.map_producer_type(dev["type"]),
              language: dev["lang"],
              updated_at: now
            ]
          )
      end
    end)
  end

  defp upsert_producer_extlinks(developers, producer_id_map, now) do
    rows =
      Enum.flat_map(developers, fn dev ->
        producer_id = Map.get(producer_id_map, dev["id"])

        if producer_id do
          (dev["extlinks"] || [])
          |> Enum.map(fn link ->
            %{
              producer_id: producer_id,
              site: link["name"],
              value: String.slice(link["url"] || "", 0, 1000),
              inserted_at: now,
              updated_at: now
            }
          end)
        else
          []
        end
      end)
      |> Enum.uniq_by(fn r -> {r.producer_id, r.site} end)

    if rows != [] do
      Repo.insert_all(ProducerExternalLink, rows,
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: [:producer_id, :site]
      )
    end
  end

  # ── Releases ──────────────────────────────────────────────────────────────

  @doc """
  Import releases: update has_ero/min_age for specified VNs, link publishers,
  and upsert vn_releases + vn_release_extlinks rows.

  - `releases` — already-fetched release API data
  - `vndb_ids` — which VNs to update has_ero/min_age for
  - `vn_id_map` — vndb_id → uuid mapping (used for publisher junctions)
  """
  def import_releases([], _vndb_ids, _vn_id_map), do: :ok

  def import_releases(releases, vndb_ids, vn_id_map) do
    now = now()

    # Group releases by VN
    vn_release_map =
      Enum.reduce(releases, %{}, fn rel, acc ->
        vn_ids = Enum.map(rel["vns"] || [], & &1["id"])

        Enum.reduce(vn_ids, acc, fn vid, inner ->
          Map.update(inner, vid, [rel], &[rel | &1])
        end)
      end)

    # Update has_ero and min_age per VN
    Enum.each(vndb_ids, fn vndb_id ->
      vn_uuid = Map.get(vn_id_map, vndb_id)
      rels = Map.get(vn_release_map, vndb_id, [])

      if vn_uuid && rels != [] do
        has_ero = Enum.any?(rels, & &1["has_ero"])

        min_age =
          rels
          |> Enum.map(& &1["minage"])
          |> Enum.reject(&is_nil/1)
          |> Enum.max(fn -> nil end)

        from(v in VisualNovel, where: v.id == ^vn_uuid)
        |> Repo.update_all(set: [has_ero: has_ero, min_age: min_age, updated_at: now])
      end
    end)

    # Link publishers from releases
    process_publishers(releases, vn_id_map, now)

    # Upsert vn_releases and vn_release_extlinks
    upsert_vn_releases(releases, vn_id_map, now)
  end

  defp process_publishers(releases, vn_id_map, now) do
    publisher_vndb_ids =
      releases
      |> Enum.flat_map(fn r -> r["producers"] || [] end)
      |> Enum.filter(& &1["publisher"])
      |> Enum.map(& &1["id"])
      |> Enum.uniq()

    if publisher_vndb_ids != [] do
      producer_map =
        Repo.all(
          from p in Producer, where: p.vndb_id in ^publisher_vndb_ids, select: {p.vndb_id, p.id}
        )
        |> Map.new()

      junction_rows =
        releases
        |> Enum.flat_map(fn rel ->
          vn_vndb_ids = Enum.map(rel["vns"] || [], & &1["id"])

          pub_ids =
            (rel["producers"] || [])
            |> Enum.filter(& &1["publisher"])
            |> Enum.map(& &1["id"])

          for vndb_id <- vn_vndb_ids,
              vn_uuid = Map.get(vn_id_map, vndb_id),
              vn_uuid != nil,
              pub_vndb_id <- pub_ids,
              producer_id = Map.get(producer_map, pub_vndb_id),
              producer_id != nil do
            %{
              visual_novel_id: vn_uuid,
              producer_id: producer_id,
              role: "publisher",
              inserted_at: now,
              updated_at: now
            }
          end
        end)
        |> Enum.uniq_by(fn r -> {r.visual_novel_id, r.producer_id} end)

      if junction_rows != [] do
        Repo.insert_all(VNProducer, junction_rows,
          on_conflict: :nothing,
          conflict_target: [:visual_novel_id, :producer_id]
        )
      end
    end
  end

  # ── VN Releases (detail-level) ───────────────────────────────────────────

  @vn_release_replace_fields [
    :title,
    :display_title,
    :latin_title,
    :original_language,
    :release_date,
    :release_type,
    :patch,
    :freeware,
    :official,
    :has_ero,
    :uncensored,
    :voiced,
    :minage,
    :engine,
    :platforms,
    :languages,
    :mtl_languages,
    :producers,
    :notes,
    :reso_x,
    :reso_y,
    :media,
    :updated_at
  ]

  defp upsert_vn_releases(releases, vn_id_map, now) do
    # Load VN titles for display_title computation
    vn_uuids = Map.values(vn_id_map)

    vn_titles =
      from(v in VisualNovel,
        where: v.id in ^vn_uuids,
        preload: [:vn_titles]
      )
      |> Repo.all()
      |> Map.new(fn v ->
        ja_latin =
          Enum.find_value(v.vn_titles, fn t ->
            if t.lang == "ja" and t.latin != nil, do: t.latin
          end)

        {v.id, {v.title, ja_latin}}
      end)

    release_rows =
      Enum.flat_map(releases, fn rel ->
        vn_entries = rel["vns"] || []

        Enum.flat_map(vn_entries, fn vn_entry ->
          vid = vn_entry["id"]

          case Map.get(vn_id_map, vid) do
            nil ->
              []

            vn_uuid ->
              title = resolve_api_release_title(rel)
              latin_title = rel["title"]
              latin_title = if latin_title && latin_title != title, do: latin_title, else: nil

              {vn_title, vn_latin_title} = Map.get(vn_titles, vn_uuid, {nil, nil})

              display_title =
                if vn_title,
                  do: ReleaseTitleHelper.compute_display_title(title, vn_title, vn_latin_title),
                  else: title

              producers_json =
                (rel["producers"] || [])
                |> Enum.map(fn p ->
                  %{
                    "vndb_id" => p["id"],
                    "name" => p["name"] || p["id"],
                    "developer" => p["developer"] == true,
                    "publisher" => p["publisher"] == true
                  }
                end)

              [
                %{
                  id: UUIDv7.generate(),
                  vndb_id: rel["id"],
                  visual_novel_id: vn_uuid,
                  title: title || "Unknown",
                  display_title: display_title,
                  latin_title: latin_title,
                  original_language: rel["olang"],
                  release_date: parse_api_release_date(rel["released"]),
                  release_type: vn_entry["rtype"] || "complete",
                  patch: rel["patch"] == true,
                  freeware: rel["freeware"] == true,
                  official: rel["official"] != false,
                  has_ero: rel["has_ero"] == true,
                  uncensored: rel["uncensored"],
                  voiced: rel["voiced"],
                  minage: rel["minage"],
                  engine: rel["engine"],
                  platforms: rel["platforms"] || [],
                  languages: rel["languages"] || [],
                  mtl_languages: extract_mtl_languages(rel),
                  producers: producers_json,
                  notes: VndbFieldMapper.clean_release_notes(rel["notes"]),
                  reso_x: if(is_integer(rel["reso_x"]) && rel["reso_x"] > 0, do: rel["reso_x"]),
                  reso_y: if(is_integer(rel["reso_y"]) && rel["reso_y"] > 0, do: rel["reso_y"]),
                  media:
                    Enum.map(rel["media"] || [], fn m ->
                      %{
                        "medium" => m["medium"],
                        "label" => VndbStorefrontMapper.media_label(m["medium"]),
                        "qty" => m["qty"]
                      }
                    end),
                  inserted_at: now,
                  updated_at: now
                }
              ]
          end
        end)
      end)

    if release_rows != [] do
      chunked_insert(Release, release_rows,
        on_conflict: {:replace, @vn_release_replace_fields},
        conflict_target: [:vndb_id, :visual_novel_id]
      )

      # Now upsert extlinks
      upsert_release_extlinks(releases, vn_id_map, now)
    end
  end

  defp upsert_release_extlinks(releases, vn_id_map, now) do
    # Build lookup: {vndb_release_id, vn_uuid} → release_uuid
    all_vndb_ids = Enum.map(releases, & &1["id"])

    release_uuid_map =
      from(r in Release,
        where: r.vndb_id in ^all_vndb_ids,
        select: {r.vndb_id, r.visual_novel_id, r.id}
      )
      |> Repo.all()
      |> Enum.map(fn {vndb_id, vn_uuid, uuid} -> {{vndb_id, vn_uuid}, uuid} end)
      |> Map.new()

    extlink_rows =
      Enum.flat_map(releases, fn rel ->
        extlinks = rel["extlinks"] || []
        vn_entries = rel["vns"] || []

        Enum.flat_map(vn_entries, fn vn_entry ->
          vid = vn_entry["id"]
          vn_uuid = Map.get(vn_id_map, vid)

          case vn_uuid && Map.get(release_uuid_map, {rel["id"], vn_uuid}) do
            nil ->
              []

            release_uuid ->
              Enum.flat_map(extlinks, fn link ->
                site = link["name"] || link["label"]
                url = link["url"]

                if site && url do
                  label = VndbStorefrontMapper.label(site)

                  base = [
                    %{
                      id: UUIDv7.generate(),
                      vn_release_id: release_uuid,
                      site: site,
                      label: label,
                      url: String.slice(url, 0, 2000),
                      inserted_at: now,
                      updated_at: now
                    }
                  ]

                  # Generate synthetic SteamDB link from Steam URL
                  if site == "steam" do
                    case Regex.run(~r"/app/(\d+)", url) do
                      [_, app_id] ->
                        base ++
                          [
                            %{
                              id: UUIDv7.generate(),
                              vn_release_id: release_uuid,
                              site: "steamdb",
                              label: "SteamDB",
                              url: "https://steamdb.info/app/#{app_id}",
                              inserted_at: now,
                              updated_at: now
                            }
                          ]

                      _ ->
                        base
                    end
                  else
                    base
                  end
                else
                  []
                end
              end)
          end
        end)
      end)
      |> Enum.uniq_by(fn r -> {r.vn_release_id, r.site, r.url} end)

    if extlink_rows != [] do
      chunked_insert(ReleaseExtlink, extlink_rows,
        on_conflict: {:replace, [:label, :updated_at]},
        conflict_target: [:vn_release_id, :site, :url]
      )
    end
  end

  defp resolve_api_release_title(rel) do
    # API returns `title` as the main display title
    # Also check titles array for olang match
    api_title = rel["title"]
    titles = rel["titles"] || []
    olang = rel["olang"]

    olang_entry = Enum.find(titles, fn t -> t["lang"] == olang end)

    cond do
      olang_entry && olang_entry["latin"] -> olang_entry["latin"]
      olang_entry && olang_entry["title"] -> olang_entry["title"]
      api_title -> api_title
      true -> "Unknown"
    end
  end

  defp parse_api_release_date(nil), do: nil

  defp parse_api_release_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_api_release_date(_), do: nil

  defp extract_mtl_languages(rel) do
    (rel["titles"] || [])
    |> Enum.filter(& &1["mtl"])
    |> Enum.map(& &1["lang"])
    |> Enum.uniq()
  end

  # ── Search Indexing ──────────────────────────────────────────────────────

  defp index_vns(vndb_ids) do
    vns =
      from(v in VisualNovel,
        where: v.vndb_id in ^vndb_ids,
        preload: [:primary_image, :vn_titles, vn_producers: :producer]
      )
      |> Repo.all()

    if vns != [] do
      SearchIndex.index_visual_novels(vns)
    end
  rescue
    e ->
      Logger.warning("[VndbEnrichment] Meilisearch VN indexing failed: #{Exception.message(e)}")
  end

  defp index_characters([]), do: :ok

  defp index_characters(char_vndb_ids) do
    chars = Repo.all(from c in Character, where: c.vndb_id in ^char_vndb_ids)

    if chars != [] do
      SearchIndex.index_characters(chars)
    end
  rescue
    e ->
      Logger.warning(
        "[VndbEnrichment] Meilisearch character indexing failed: #{Exception.message(e)}"
      )
  end

  defp index_producers([]), do: :ok

  defp index_producers(producer_vndb_ids) do
    producers = Repo.all(from p in Producer, where: p.vndb_id in ^producer_vndb_ids)

    if producers != [] do
      SearchIndex.index_producers(producers)
    end
  rescue
    e ->
      Logger.warning(
        "[VndbEnrichment] Meilisearch producer indexing failed: #{Exception.message(e)}"
      )
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp safe_enrich(phase, fun) do
    fun.()
  rescue
    e ->
      Logger.error("[VndbEnrichment] #{phase} failed: #{Exception.message(e)}")
      nil
  end

  defp chunked_insert(_schema, [], _opts), do: 0

  defp chunked_insert(schema, rows, opts) do
    rows
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} = Repo.insert_all(schema, chunk, opts)
      acc + count
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

defmodule Kaguya.Releases do
  @moduledoc """
  Context for release edit/revision support.
  """

  @behaviour Kaguya.Revisions.EntityContext

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Releases.{Release, ReleaseExtlink}
  alias Kaguya.Producers.VNProducer
  alias Kaguya.Sync.VndbStorefrontMapper

  # ============================================================================
  # Edit / Revision Support
  # ============================================================================

  def get_for_edit(id) do
    case Repo.get(Release, id) do
      nil -> nil
      release -> Repo.preload(release, :extlinks)
    end
  end

  @doc """
  Batch-loads the curated storefront links used by the VN page's Available on row.

  The source of truth is release extlinks, but the UI wants one representative
  link per storefront family (for example one DLsite link regardless of whether
  the best candidate came from `dlsite` or `dlsiteen`).
  """
  def batch_load_available_on_links(_key, vn_ids) when is_list(vn_ids) do
    normalized_ids_by_input =
      vn_ids
      |> Map.new(fn vn_id -> {vn_id, normalize_batch_uuid(vn_id)} end)

    normalized_vn_ids =
      normalized_ids_by_input
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    rows =
      from(r in Release,
        join: e in assoc(r, :extlinks),
        where: r.visual_novel_id in ^normalized_vn_ids,
        where: is_nil(r.hidden_at),
        where: r.patch == false,
        where: e.site in ^VndbStorefrontMapper.available_on_sites(),
        where: not is_nil(e.url),
        select: %{
          visual_novel_id: r.visual_novel_id,
          site: e.site,
          url: e.url,
          official: r.official,
          freeware: r.freeware,
          release_type: r.release_type,
          release_date: r.release_date,
          languages: r.languages,
          mtl_languages: r.mtl_languages
        }
      )
      |> Repo.all()

    links_by_vn =
      rows
      |> Enum.group_by(& &1.visual_novel_id)
      |> Map.new(fn {vn_id, release_rows} ->
        {vn_id, pick_available_on_links(release_rows)}
      end)

    Map.new(vn_ids, fn vn_id ->
      normalized_vn_id = Map.get(normalized_ids_by_input, vn_id)
      {vn_id, Map.get(links_by_vn, normalized_vn_id, [])}
    end)
  end

  defp normalize_batch_uuid(id) when is_binary(id) and byte_size(id) == 16 do
    case Ecto.UUID.load(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_batch_uuid(id) when is_binary(id), do: id
  defp normalize_batch_uuid(_id), do: nil

  @doc """
  Batch-loads multiple releases with the same preload set as
  `get_for_edit/1`. Used by the bulk revision writer to snapshot many
  entities in a single round-trip per preload instead of one per entity.
  """
  def batch_load_for_hist(ids) when is_list(ids) do
    from(r in Release, where: r.id in ^ids)
    |> Repo.all()
    |> Repo.preload(:extlinks)
  end

  @edit_scalar_fields ~w(title display_title latin_title original_language release_date
                         release_type patch freeware official has_ero uncensored voiced
                         minage engine platforms languages mtl_languages producers notes reso_x reso_y media)a

  def create_from_edit(attrs) do
    with {:ok, release} <- %Release{} |> Release.changeset(attrs) |> Repo.insert(),
         :ok <- sync_extlinks(release, attrs),
         :ok <- maybe_recompute_vn_producers(release.visual_novel_id, attrs) do
      {:ok, release}
    end
  end

  def apply_edit(release, changes) do
    attrs = Map.take(changes, @edit_scalar_fields)

    with {:ok, release} <- update_release_fields(release, attrs),
         :ok <- sync_extlinks(release, changes),
         :ok <- maybe_recompute_vn_producers(release.visual_novel_id, changes) do
      {:ok, release}
    end
  end

  defp update_release_fields(release, attrs) when attrs == %{}, do: {:ok, release}

  defp update_release_fields(release, attrs) do
    release |> Release.changeset(attrs) |> Repo.update()
  end

  defp sync_extlinks(release, changes) do
    case Map.get(changes, :extlinks) do
      nil ->
        :ok

      extlinks when is_list(extlinks) ->
        from(e in ReleaseExtlink, where: e.vn_release_id == ^release.id) |> Repo.delete_all()
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        rows =
          Enum.map(extlinks, fn e ->
            %{
              id: UUIDv7.generate(),
              vn_release_id: release.id,
              site: e.site,
              label: Map.get(e, :label),
              url: e.url,
              inserted_at: now,
              updated_at: now
            }
          end)

        if rows != [], do: Repo.insert_all(ReleaseExtlink, rows)
        :ok
    end
  end

  # Only recompute vn_producers when producers field was actually changed
  defp maybe_recompute_vn_producers(vn_id, changes) do
    if Map.has_key?(changes, :producers) or Map.has_key?(changes, "producers") do
      recompute_vn_producers(vn_id)
    else
      :ok
    end
  end

  # Recomputes vn_producers for a VN from all its releases' producers JSONB.
  # Handles both sync-imported format (vndb_id + name) and user format (producer_id).
  # For sync-imported producers, resolves vndb_id → internal UUID via producers table.
  defp recompute_vn_producers(nil), do: :ok

  defp recompute_vn_producers(vn_id) do
    # Serialize concurrent edits on the same VN so two release edits don't
    # both delete_all + insert_all on vn_producers and leave a half-state.
    # Reentrant within the caller's transaction; same lock-key family as
    # Revisions.create_change/7 so visual_novel edits and release edits
    # exclude each other on the same VN.
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtext($1))",
      ["visual_novel:#{vn_id}"]
    )

    releases =
      from(r in Release,
        where: r.visual_novel_id == ^vn_id,
        select: {r.producers, r.release_date}
      )
      |> Repo.all()

    # Batch-resolve all vndb_ids to internal UUIDs in one query
    vndb_id_map = build_vndb_id_map(releases)

    producer_map =
      Enum.reduce(releases, %{}, fn {producers, release_date}, acc ->
        Enum.reduce(producers || [], acc, fn producer, inner_acc ->
          pid = resolve_producer_id(producer, vndb_id_map)
          is_dev = get_flag(producer, :developer, "developer")
          is_pub = get_flag(producer, :publisher, "publisher")

          if pid do
            existing =
              Map.get(inner_acc, pid, %{developer: false, publisher: false, earliest_date: nil})

            Map.put(inner_acc, pid, %{
              developer: existing.developer || is_dev,
              publisher: existing.publisher || is_pub,
              earliest_date: earliest(existing.earliest_date, release_date)
            })
          else
            inner_acc
          end
        end)
      end)

    from(vp in VNProducer, where: vp.visual_novel_id == ^vn_id) |> Repo.delete_all()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(producer_map, fn {producer_id, info} ->
        role =
          case {info.developer, info.publisher} do
            {true, true} -> "both"
            {true, false} -> "developer"
            {false, true} -> "publisher"
            _ -> "developer"
          end

        %{
          visual_novel_id: vn_id,
          producer_id: producer_id,
          role: role,
          earliest_release_date: info.earliest_date,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(VNProducer, rows)

    # Search index lives on the VN, so producer changes need a reindex —
    # otherwise browse / search filtering by producer keeps showing the
    # pre-change set until the next dump-sync or VN edit. Best-effort and
    # async to S3-backed Meilisearch — never block the txn on it.
    reindex_vn_search(vn_id)

    :ok
  end

  defp reindex_vn_search(vn_id) do
    vn =
      Kaguya.VisualNovels.VisualNovel
      |> Repo.get(vn_id)
      |> Repo.preload([:primary_image, :vn_titles, vn_producers: :producer])

    cond do
      is_nil(vn) -> :ok
      vn.hidden_at != nil -> Kaguya.SearchIndex.remove_visual_novel(vn_id)
      true -> Kaguya.SearchIndex.index_visual_novels(vn)
    end
  rescue
    e ->
      require Logger

      Logger.warning(
        "[Releases] Meilisearch reindex failed for VN #{vn_id} after vn_producers recompute: #{Exception.message(e)}"
      )
  end

  # Resolves producer IDs from all releases in one batch query.
  # User-created releases store producer_id (our UUID).
  # Sync-imported releases store vndb_id (e.g. "p146") — resolved via producers table.
  defp resolve_producer_id(producer, vndb_id_map) do
    Map.get(producer, :producer_id) ||
      Map.get(producer, "producer_id") ||
      Map.get(vndb_id_map, Map.get(producer, "vndb_id"))
  end

  defp build_vndb_id_map(releases) do
    vndb_ids =
      releases
      |> Enum.flat_map(fn {producers, _} ->
        Enum.map(producers || [], &Map.get(&1, "vndb_id"))
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if vndb_ids == [] do
      %{}
    else
      from(p in Kaguya.Producers.Producer,
        where: p.vndb_id in ^vndb_ids,
        select: {p.vndb_id, p.id}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  defp get_flag(map, atom_key, string_key) do
    Map.get(map, atom_key) || Map.get(map, string_key) || false
  end

  defp earliest(nil, date), do: date
  defp earliest(date, nil), do: date
  defp earliest(d1, d2), do: if(Date.compare(d1, d2) == :lt, do: d1, else: d2)

  defp pick_available_on_links(rows) do
    rows
    |> Enum.group_by(&VndbStorefrontMapper.available_on_family(&1.site))
    |> Enum.flat_map(fn
      {nil, _family_rows} ->
        []

      {family, family_rows} ->
        best = Enum.min_by(family_rows, &available_on_candidate_rank(family, &1))

        [
          %{
            site: best.site,
            source_site: family,
            label: VndbStorefrontMapper.available_on_label(family),
            url: VndbStorefrontMapper.canonical_available_on_url(best.site, best.url),
            availability: availability_kind(best),
            official: best.official
          }
        ]
    end)
    |> prefer_primary_available_on_links()
    |> Enum.sort_by(&VndbStorefrontMapper.available_on_sort_key(&1.source_site))
  end

  defp prefer_primary_available_on_links(links) do
    official_links = Enum.filter(links, & &1.official)

    official_primary_links =
      Enum.filter(
        official_links,
        &VndbStorefrontMapper.primary_available_on_family?(&1.source_site)
      )

    primary_links =
      Enum.filter(links, &VndbStorefrontMapper.primary_available_on_family?(&1.source_site))

    cond do
      official_primary_links != [] -> official_primary_links
      official_links != [] -> official_links
      primary_links != [] -> primary_links
      true -> links
    end
  end

  defp available_on_candidate_rank(family, row) do
    {
      official_rank(row.official),
      trial_rank(row.release_type),
      freeware_rank(row.freeware),
      english_rank(row.languages, row.mtl_languages),
      site_variant_rank(family, row.site),
      release_date_rank(row.release_date),
      row.url
    }
  end

  defp official_rank(false), do: 1
  defp official_rank(_), do: 0

  defp trial_rank("trial"), do: 1
  defp trial_rank(_), do: 0

  defp freeware_rank(true), do: 1
  defp freeware_rank(_), do: 0

  defp english_rank(languages, mtl_languages)
       when is_list(languages) and is_list(mtl_languages) do
    cond do
      "en" in languages -> 0
      "en" in mtl_languages -> 1
      true -> 2
    end
  end

  defp english_rank(_languages, _mtl_languages), do: 2

  defp site_variant_rank("dlsite", "dlsiteen"), do: 0
  defp site_variant_rank("dlsite", "dlsite"), do: 1
  defp site_variant_rank("nintendo", "nintendo"), do: 0
  defp site_variant_rank("nintendo", "nintendo_jp"), do: 1
  defp site_variant_rank("nintendo", "nintendo_hk"), do: 2
  defp site_variant_rank("playstation", "playstation_na"), do: 0
  defp site_variant_rank("playstation", "playstation_eu"), do: 1
  defp site_variant_rank("playstation", "playstation_jp"), do: 2
  defp site_variant_rank("playstation", "playstation_hk"), do: 3
  defp site_variant_rank("getchu", "getchudl"), do: 0
  defp site_variant_rank("getchu", "getchu"), do: 1
  defp site_variant_rank("melonbooks", "melonjp"), do: 0
  defp site_variant_rank("melonbooks", "melon"), do: 1
  defp site_variant_rank("patreon", "patreonp"), do: 0
  defp site_variant_rank("patreon", "patreon"), do: 1
  defp site_variant_rank(_family, _site), do: 0

  defp release_date_rank(%Date{} = date), do: -Date.to_gregorian_days(date)
  defp release_date_rank(_), do: 0

  defp availability_kind(%{release_type: "trial"}), do: :demo
  defp availability_kind(%{freeware: true}), do: :free
  defp availability_kind(_row), do: nil

  # ============================================================================
  # Revision _hist Support
  # ============================================================================

  alias Kaguya.Revisions.Hist.{ReleaseHist, ReleaseExtlinkHist}

  # Every column on `releases_hist`. Includes the user-editable fields plus
  # moderation state (hidden_at, is_locked) so revert restores everything.
  #
  # Intentionally excluded — sync-managed external identifier: vndb_id
  # Intentionally excluded — FK to parent VN (visual_novel_id, immutable post-creation)
  @hist_fields @edit_scalar_fields ++ [:hidden_at, :is_locked]

  @field_groups %{
    "title" => [:title, :display_title, :latin_title],
    "general" => [
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
      :notes,
      :reso_x,
      :reso_y,
      :producers
    ],
    "platforms" => [:platforms, :languages, :mtl_languages],
    "links" => [:extlinks],
    "moderation" => [:hidden_at, :is_locked]
  }

  def write_hist(change_id, release) do
    Repo.insert_all(ReleaseHist, [
      Map.take(release, @hist_fields) |> Map.put(:change_id, change_id)
    ])

    extlink_rows =
      Enum.map(release.extlinks, fn e ->
        %{change_id: change_id, site: e.site, label: e.label, url: e.url}
      end)

    if extlink_rows != [], do: Repo.insert_all(ReleaseExtlinkHist, extlink_rows)
  end

  @doc """
  Bulk version of `write_hist/2` for seeding/backfill paths. Pairs must be
  `[{change_id, release_with_preloads}, ...]` (preloaded with `:extlinks`).
  """
  def bulk_write_hist([]), do: :ok

  def bulk_write_hist(pairs) when is_list(pairs) do
    main_rows =
      Enum.map(pairs, fn {change_id, release} ->
        Map.take(release, @hist_fields) |> Map.put(:change_id, change_id)
      end)

    chunked_insert_all(ReleaseHist, main_rows)

    extlink_rows =
      Enum.flat_map(pairs, fn {change_id, release} ->
        Enum.map(release.extlinks, fn e ->
          %{change_id: change_id, site: e.site, label: e.label, url: e.url}
        end)
      end)

    chunked_insert_all(ReleaseExtlinkHist, extlink_rows)

    :ok
  end

  defp chunked_insert_all(_module, []), do: :ok

  defp chunked_insert_all(module, rows) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(module, &1))

    :ok
  end

  def load_hist(change_id) do
    hist = Repo.one(from h in ReleaseHist, where: h.change_id == ^change_id)
    extlinks = Repo.all(from e in ReleaseExtlinkHist, where: e.change_id == ^change_id)
    %{hist: hist, extlinks: extlinks}
  end

  @doc """
  Batched version of `load_hist/1`. 2 queries for any number of change_ids.
  """
  def bulk_load_hist([]), do: %{}

  def bulk_load_hist(change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    hists =
      Repo.all(from h in ReleaseHist, where: h.change_id in ^ids) |> Map.new(&{&1.change_id, &1})

    extlinks =
      Repo.all(from e in ReleaseExtlinkHist, where: e.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    Map.new(ids, fn change_id ->
      {change_id, %{hist: Map.get(hists, change_id), extlinks: Map.get(extlinks, change_id, [])}}
    end)
  end

  def apply_hist(release, hist_data) do
    # Bypass Release.changeset: hist data includes hidden_at + is_locked which
    # the user-edit changeset doesn't accept. Ecto.Changeset.change/2 restores
    # every snapshotted field verbatim.
    attrs = Map.take(hist_data.hist, @hist_fields)

    with {:ok, release} <- release |> Ecto.Changeset.change(attrs) |> Repo.update() do
      from(e in ReleaseExtlink, where: e.vn_release_id == ^release.id) |> Repo.delete_all()

      rows =
        Enum.map(hist_data.extlinks, fn e ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          %{
            id: UUIDv7.generate(),
            vn_release_id: release.id,
            site: e.site,
            label: e.label,
            url: e.url,
            inserted_at: now,
            updated_at: now
          }
        end)

      if rows != [], do: Repo.insert_all(ReleaseExtlink, rows)

      maybe_recompute_vn_producers(release.visual_novel_id, %{producers: true})
      {:ok, release}
    end
  end

  def changed_field_groups(release, changes) do
    @field_groups
    |> Enum.filter(fn {_group, fields} ->
      Enum.any?(fields, fn
        :extlinks ->
          Map.has_key?(changes, :extlinks)

        field ->
          Map.has_key?(changes, field) && Map.get(changes, field) != Map.get(release, field)
      end)
    end)
    |> Enum.map(fn {group, _} -> group end)
    |> Enum.sort()
  end
end

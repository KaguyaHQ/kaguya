defmodule Kaguya.Revisions.Hist.VisualNovel do
  @moduledoc """
  Snapshot / restore operations against the VN `_hist` tables.

  Owns the `write_hist`, `load_hist`, `apply_hist`, and `changed_field_groups`
  contract that `Kaguya.Revisions` dispatches to for `:visual_novel`. The
  public surface stays exposed via `defdelegate` on `Kaguya.VisualNovels` so
  the existing `@entity_config` dispatch keeps working unchanged.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels

  alias Kaguya.Revisions.Hist.{
    VnHist,
    VnTitleHist,
    VnRelationHist,
    VnScreenshotHist,
    VnCoverHist,
    VnCharacterHist,
    VnExternalLinkHist
  }

  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Series, as: VnSeries
  alias Kaguya.VisualNovels.{Image, VNTitle, VnExternalLink}

  # Every column on `vn_hist`, in the order of @vn_hist_fields, must be
  # snapshotted on write_hist and restored on apply_hist.
  #
  # Intentionally excluded — denormalized counter / cache (matches VNDB pattern):
  #   average_rating, ratings_count, ratings_dist, reviews_count
  #   vndb_rating, vndb_vote_count
  # Intentionally excluded — sync-managed external identifier: vndb_id
  # Intentionally excluded — transient upload-staging field: temp_image_url
  @vn_hist_fields ~w(title slug description aliases development_status length_category
                     length_minutes original_language release_date min_age has_ero is_avn
                     title_category primary_image_id is_image_nsfw is_image_suggestive
                     primary_vn_series_id primary_series_position featured_screenshot_id
                     is_cover_pinned hidden_at is_locked)a

  # Slug is auto-derived from the title at creation time and never
  # regenerates (see Utils.put_unique_slug). It's kept in @vn_hist_fields
  # for revert correctness but does not have a field group — it should never
  # show up in changed_fields or in the diff display.
  @field_groups %{
    "title" => [:title],
    "description" => [:description],
    "general" => [
      :aliases,
      :development_status,
      :length_category,
      :length_minutes,
      :original_language,
      :release_date,
      :min_age,
      :has_ero,
      :is_avn,
      :title_category
    ],
    "cover" => [:primary_image_id, :is_image_nsfw, :is_image_suggestive, :is_cover_pinned],
    "featured_screenshot" => [:featured_screenshot_id],
    "moderation" => [:hidden_at, :is_locked],
    "titles" => [:vn_titles],
    "relations" => [:vn_relations],
    "characters" => [:vn_characters],
    "screenshots" => [:vn_screenshots],
    "covers_metadata" => [:covers],
    "external_links" => [:external_links],
    "removed_screenshots" => [:removed_screenshot_ids],
    "removed_covers" => [:removed_cover_ids]
  }

  def write_hist(change_id, vn) do
    main_row =
      vn
      |> Map.take(@vn_hist_fields)
      |> Map.put(:change_id, change_id)
      |> Map.update(:title_category, "vn", &to_string_or_nil/1)

    Repo.insert_all(VnHist, [main_row])

    title_rows =
      Enum.map(vn.vn_titles, fn t ->
        %{
          change_id: change_id,
          lang: t.lang,
          title: t.title,
          latin: t.latin,
          official: t.official
        }
      end)

    if title_rows != [], do: Repo.insert_all(VnTitleHist, title_rows)

    relation_rows =
      Enum.map(vn.vn_relations, fn r ->
        %{
          change_id: change_id,
          related_vn_id: r.related_vn_id,
          relation_type: r.relation_type,
          is_official: r.is_official
        }
      end)

    if relation_rows != [], do: Repo.insert_all(VnRelationHist, relation_rows)

    screenshot_rows =
      Enum.map(vn.vn_screenshots, fn s ->
        %{
          change_id: change_id,
          screenshot_id: s.id,
          is_nsfw: s.is_nsfw,
          is_brutal: s.is_brutal,
          release_id: s.release_id
        }
      end)

    if screenshot_rows != [], do: Repo.insert_all(VnScreenshotHist, screenshot_rows)

    cover_rows =
      Enum.map(vn.vn_images, fn c ->
        %{
          change_id: change_id,
          cover_id: c.id,
          is_image_nsfw: c.is_image_nsfw,
          is_image_suggestive: c.is_image_suggestive,
          language: c.language,
          release_date: c.release_date
        }
      end)

    if cover_rows != [], do: Repo.insert_all(VnCoverHist, cover_rows)

    extlink_rows =
      Enum.map(vn.external_links, fn l ->
        %{change_id: change_id, site: l.site, value: l.value}
      end)

    if extlink_rows != [], do: Repo.insert_all(VnExternalLinkHist, extlink_rows)

    # Cast (vn_characters) is preloaded separately because the VisualNovel
    # schema doesn't have a direct has_many — fetch it explicitly so VN
    # revisions snapshot the cast even when the edit didn't touch it.
    cast_rows =
      from(vc in VNCharacter, where: vc.visual_novel_id == ^vn.id)
      |> Repo.all()
      |> Enum.map(fn vc ->
        %{
          change_id: change_id,
          visual_novel_id: vc.visual_novel_id,
          character_id: vc.character_id,
          role: to_string(vc.role),
          spoiler_level: vc.spoiler_level
        }
      end)

    if cast_rows != [], do: Repo.insert_all(VnCharacterHist, cast_rows)
  end

  @doc """
  Bulk version of `write_hist/2` for seeding/backfill paths. Takes a list of
  `{change_id, vn}` pairs (vn must be preloaded with the same associations
  as `get_for_edit/1`) and emits one `insert_all` per `_hist` table for the
  whole batch — instead of 6+ inserts per entity.

  At seed time this is the difference between ~minutes and ~hours.
  """
  def bulk_write_hist([]), do: :ok

  def bulk_write_hist(pairs) when is_list(pairs) do
    main_rows =
      Enum.map(pairs, fn {change_id, vn} ->
        vn
        |> Map.take(@vn_hist_fields)
        |> Map.put(:change_id, change_id)
        |> Map.update(:title_category, "vn", &to_string_or_nil/1)
      end)

    chunked_insert_all(VnHist, main_rows)

    title_rows =
      Enum.flat_map(pairs, fn {change_id, vn} ->
        Enum.map(vn.vn_titles, fn t ->
          %{
            change_id: change_id,
            lang: t.lang,
            title: t.title,
            latin: t.latin,
            official: t.official
          }
        end)
      end)

    chunked_insert_all(VnTitleHist, title_rows)

    relation_rows =
      Enum.flat_map(pairs, fn {change_id, vn} ->
        Enum.map(vn.vn_relations, fn r ->
          %{
            change_id: change_id,
            related_vn_id: r.related_vn_id,
            relation_type: r.relation_type,
            is_official: r.is_official
          }
        end)
      end)

    chunked_insert_all(VnRelationHist, relation_rows)

    screenshot_rows =
      Enum.flat_map(pairs, fn {change_id, vn} ->
        Enum.map(vn.vn_screenshots, fn s ->
          %{
            change_id: change_id,
            screenshot_id: s.id,
            is_nsfw: s.is_nsfw,
            is_brutal: s.is_brutal,
            release_id: s.release_id
          }
        end)
      end)

    chunked_insert_all(VnScreenshotHist, screenshot_rows)

    cover_rows =
      Enum.flat_map(pairs, fn {change_id, vn} ->
        Enum.map(vn.vn_images, fn c ->
          %{
            change_id: change_id,
            cover_id: c.id,
            is_image_nsfw: c.is_image_nsfw,
            is_image_suggestive: c.is_image_suggestive,
            language: c.language,
            release_date: c.release_date
          }
        end)
      end)

    chunked_insert_all(VnCoverHist, cover_rows)

    extlink_rows =
      Enum.flat_map(pairs, fn {change_id, vn} ->
        Enum.map(vn.external_links, fn l ->
          %{change_id: change_id, site: l.site, value: l.value}
        end)
      end)

    chunked_insert_all(VnExternalLinkHist, extlink_rows)

    # vn_characters: batch-fetch all rows for all VN ids in one query, then
    # group by visual_novel_id to assign each row to its corresponding change.
    vn_ids = Enum.map(pairs, fn {_, vn} -> vn.id end)
    change_id_by_vn = Map.new(pairs, fn {change_id, vn} -> {vn.id, change_id} end)

    cast_rows =
      from(vc in VNCharacter, where: vc.visual_novel_id in ^vn_ids)
      |> Repo.all()
      |> Enum.map(fn vc ->
        %{
          change_id: Map.fetch!(change_id_by_vn, vc.visual_novel_id),
          visual_novel_id: vc.visual_novel_id,
          character_id: vc.character_id,
          role: to_string(vc.role),
          spoiler_level: vc.spoiler_level
        }
      end)

    chunked_insert_all(VnCharacterHist, cast_rows)

    :ok
  end

  # Chunks insert_all to stay under PostgreSQL's 65535 parameter limit.
  # 1000 rows × up to ~50 fields = 50k params, safe headroom.
  defp chunked_insert_all(_module, []), do: :ok

  defp chunked_insert_all(module, rows) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(module, &1))

    :ok
  end

  def load_hist(change_id) do
    hist = Repo.one(from h in VnHist, where: h.change_id == ^change_id)
    titles = Repo.all(from t in VnTitleHist, where: t.change_id == ^change_id)
    relations = Repo.all(from r in VnRelationHist, where: r.change_id == ^change_id)
    screenshots = Repo.all(from s in VnScreenshotHist, where: s.change_id == ^change_id)
    covers = Repo.all(from c in VnCoverHist, where: c.change_id == ^change_id)
    external_links = Repo.all(from l in VnExternalLinkHist, where: l.change_id == ^change_id)
    characters = Repo.all(from vc in VnCharacterHist, where: vc.change_id == ^change_id)

    %{
      hist: hist,
      titles: titles,
      relations: relations,
      screenshots: screenshots,
      covers: covers,
      external_links: external_links,
      characters: characters
    }
  end

  @doc """
  Batched version of `load_hist/1`. Fetches hist for many change_ids in 7
  queries total (one per `_hist` table) instead of N×7. Used by the activity
  log feed where every visible revision needs its diff inline.

  Returns `%{change_id => %{hist, titles, relations, screenshots, covers,
  external_links, characters}}`. Change_ids with no hist row are omitted.
  """
  def bulk_load_hist([]), do: %{}

  def bulk_load_hist(change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    hists = Repo.all(from h in VnHist, where: h.change_id in ^ids) |> Map.new(&{&1.change_id, &1})

    titles =
      Repo.all(from t in VnTitleHist, where: t.change_id in ^ids) |> Enum.group_by(& &1.change_id)

    relations =
      Repo.all(from r in VnRelationHist, where: r.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    screenshots =
      Repo.all(from s in VnScreenshotHist, where: s.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    covers =
      Repo.all(from c in VnCoverHist, where: c.change_id in ^ids) |> Enum.group_by(& &1.change_id)

    extlinks =
      Repo.all(from l in VnExternalLinkHist, where: l.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    chars =
      Repo.all(from vc in VnCharacterHist, where: vc.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    Map.new(ids, fn change_id ->
      {change_id,
       %{
         hist: Map.get(hists, change_id),
         titles: Map.get(titles, change_id, []),
         relations: Map.get(relations, change_id, []),
         screenshots: Map.get(screenshots, change_id, []),
         covers: Map.get(covers, change_id, []),
         external_links: Map.get(extlinks, change_id, []),
         characters: Map.get(chars, change_id, [])
       }}
    end)
  end

  def apply_hist(vn, hist_data) do
    # Bypass VisualNovel.changeset on purpose: hist data is known-good and
    # contains fields (slug, hidden_at, is_locked, is_cover_pinned, ...) that
    # the user-edit changeset doesn't accept. Ecto.Changeset.change/2 lets us
    # restore everything verbatim.
    attrs =
      hist_data.hist
      |> Map.take(@vn_hist_fields)
      |> Map.drop([:primary_vn_series_id, :primary_series_position])
      |> normalize_hist_attrs()

    with {:ok, vn} <- vn |> Ecto.Changeset.change(attrs) |> Repo.update() do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Replace titles
      from(t in VNTitle, where: t.visual_novel_id == ^vn.id) |> Repo.delete_all()

      title_rows =
        Enum.map(hist_data.titles, fn t ->
          %{
            id: UUIDv7.generate(),
            visual_novel_id: vn.id,
            lang: t.lang,
            title: t.title,
            latin: t.latin,
            official: t.official
          }
        end)

      if title_rows != [], do: Repo.insert_all(VNTitle, title_rows)

      # Replace relations — same symmetric semantics as sync_relations:
      # restoring forward also re-asserts the reverse on the other side.
      hist_relations =
        Enum.map(hist_data.relations, fn r ->
          %{
            related_vn_id: r.related_vn_id,
            relation_type: r.relation_type,
            is_official: r.is_official
          }
        end)

      VisualNovels.replace_vn_relations(vn.id, hist_relations)

      # Series membership is owned by vn_series_items. Recompute the derived
      # primary pointer from current memberships instead of restoring stale
      # pointer values from an old VN snapshot.
      VnSeries.reconcile_primary_series([vn.id])

      # Replace external links
      from(l in VnExternalLink, where: l.vn_id == ^vn.id) |> Repo.delete_all()

      extlink_rows =
        Enum.map(hist_data.external_links, fn l ->
          %{vn_id: vn.id, site: l.site, value: l.value, inserted_at: now, updated_at: now}
        end)

      if extlink_rows != [], do: Repo.insert_all(VnExternalLink, extlink_rows)

      # Replace cast (vn_characters). Skip rows whose character was deleted in
      # the meantime — restoring would violate the FK and isn't recoverable.
      restore_cast(vn.id, hist_data.characters, now)

      # Restore screenshot metadata (NSFW flag, release link) from hist snapshot.
      # Only updates metadata on screenshots that still exist — does not re-create deleted images.
      restore_screenshot_metadata(vn.id, hist_data.screenshots)

      # Restore cover metadata from hist snapshot.
      # Only updates metadata on covers that still exist.
      restore_cover_metadata(vn.id, hist_data.covers)

      VisualNovels.reindex_search(vn.id)
      {:ok, vn}
    end
  end

  defp normalize_hist_attrs(attrs) do
    case Map.get(attrs, :title_category) do
      nil -> attrs
      val when is_atom(val) -> attrs
      val when is_binary(val) -> Map.put(attrs, :title_category, String.to_existing_atom(val))
    end
  end

  defp restore_cast(vn_id, hist_characters, now) do
    from(vc in VNCharacter, where: vc.visual_novel_id == ^vn_id) |> Repo.delete_all()

    if hist_characters != [] do
      char_ids =
        Enum.map(hist_characters, & &1.character_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      existing =
        from(c in Character, where: c.id in ^char_ids, select: c.id)
        |> Repo.all()
        |> MapSet.new()

      rows =
        hist_characters
        |> Enum.filter(fn vc -> vc.character_id && MapSet.member?(existing, vc.character_id) end)
        |> Enum.map(fn vc ->
          %{
            visual_novel_id: vn_id,
            character_id: vc.character_id,
            role: String.to_existing_atom(vc.role),
            spoiler_level: vc.spoiler_level,
            inserted_at: now,
            updated_at: now
          }
        end)

      if rows != [], do: Repo.insert_all(VNCharacter, rows)
    end

    :ok
  end

  defp restore_screenshot_metadata(_vn_id, []), do: :ok

  defp restore_screenshot_metadata(vn_id, hist_screenshots) do
    hist_map = Map.new(hist_screenshots, &{&1.screenshot_id, &1})

    current_ids =
      from(s in Screenshot, where: s.visual_novel_id == ^vn_id, select: s.id)
      |> Repo.all()
      |> MapSet.new()

    for {sid, meta} <- hist_map, MapSet.member?(current_ids, sid) do
      from(s in Screenshot, where: s.id == ^sid)
      |> Repo.update_all(
        set: [
          is_nsfw: meta.is_nsfw,
          is_brutal: meta.is_brutal,
          release_id: meta.release_id
        ]
      )
    end

    :ok
  end

  defp restore_cover_metadata(_vn_id, []), do: :ok

  defp restore_cover_metadata(vn_id, hist_covers) do
    hist_map = Map.new(hist_covers, &{&1.cover_id, &1})

    current_ids =
      from(i in Image, where: i.visual_novel_id == ^vn_id, select: i.id)
      |> Repo.all()
      |> MapSet.new()

    for {cid, meta} <- hist_map, MapSet.member?(current_ids, cid) do
      from(i in Image, where: i.id == ^cid)
      |> Repo.update_all(
        set: [
          is_image_nsfw: meta.is_image_nsfw,
          is_image_suggestive: meta.is_image_suggestive,
          language: meta.language,
          release_date: meta.release_date
        ]
      )
    end

    :ok
  end

  def changed_field_groups(vn, changes) do
    @field_groups
    |> Enum.filter(fn {_group, fields} ->
      Enum.any?(fields, fn
        :vn_titles ->
          collection_actually_changed?(changes, :titles, vn.vn_titles, &title_fingerprint/1)

        :vn_relations ->
          collection_actually_changed?(
            changes,
            :relations,
            vn.vn_relations,
            &relation_fingerprint/1
          )

        :vn_screenshots ->
          collection_actually_changed?(
            changes,
            :screenshots,
            vn.vn_screenshots,
            &screenshot_fingerprint/1
          )

        :vn_characters ->
          Map.has_key?(changes, :characters)

        :external_links ->
          collection_actually_changed?(
            changes,
            :external_links,
            vn.external_links,
            &extlink_fingerprint/1
          )

        :covers ->
          has_non_empty_list?(changes, :covers)

        :primary_image_id ->
          Map.has_key?(changes, :primary_cover_id) &&
            Map.get(changes, :primary_cover_id) != vn.primary_image_id

        :removed_screenshot_ids ->
          has_non_empty_list?(changes, :removed_screenshot_ids)

        :removed_cover_ids ->
          has_non_empty_list?(changes, :removed_cover_ids)

        field ->
          Map.has_key?(changes, field) && Map.get(changes, field) != Map.get(vn, field)
      end)
    end)
    |> Enum.map(fn {group, _} -> group end)
    |> Enum.sort()
  end

  defp has_non_empty_list?(changes, key) do
    case Map.get(changes, key) do
      list when is_list(list) and list != [] -> true
      _ -> false
    end
  end

  # Returns true only when the submitted collection actually differs from the
  # entity's current state. The edit form sends full collections every time,
  # so plain Map.has_key? produces false-positive "changed" labels.
  #
  # Comparison is order-insensitive: rows are reduced to a fingerprint tuple
  # of their identifying + content fields, then compared as a sorted list.
  defp collection_actually_changed?(changes, key, current_rows, fingerprint_fn) do
    case Map.get(changes, key) do
      nil ->
        false

      submitted when is_list(submitted) ->
        current_set =
          current_rows
          |> Enum.map(fingerprint_fn)
          |> Enum.sort()

        submitted_set =
          submitted
          |> Enum.map(fingerprint_fn)
          |> Enum.sort()

        current_set != submitted_set
    end
  end

  defp title_fingerprint(t) do
    {get(t, :lang), get(t, :title), get(t, :latin), get(t, :official, true)}
  end

  defp relation_fingerprint(r) do
    {get(r, :related_vn_id), get(r, :relation_type), get(r, :is_official, true)}
  end

  defp screenshot_fingerprint(s) do
    # Screenshots are matched by id; only the editable metadata matters here.
    {get(s, :screenshot_id) || get(s, :id), get(s, :is_nsfw, false), get(s, :release_id)}
  end

  defp extlink_fingerprint(l) do
    {get(l, :site), get(l, :value)}
  end

  defp get(item, key, default \\ nil)
  defp get(item, key, default) when is_map(item), do: Map.get(item, key, default)

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)
end

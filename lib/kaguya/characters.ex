defmodule Kaguya.Characters do
  @moduledoc """
  Context for character edit/revision support.
  """

  @behaviour Kaguya.Revisions.EntityContext

  import Ecto.Query
  alias Kaguya.Repo

  alias Kaguya.Characters.{
    Character,
    CharacterFavorite,
    VNCharacter,
    CharacterImage
  }

  alias Kaguya.CursorPagination
  alias Kaguya.Pagination
  alias Kaguya.Revisions.Hist.{CharacterHist, VnCharacterHist, CharacterImageHist}
  alias Kaguya.SearchIndex
  alias Kaguya.VisualNovels

  # Enum fields stored as :string in characters_hist — must be normalized to
  # atoms when restoring via Ecto.Changeset.change/2 (which doesn't run the
  # Ecto.Enum cast the user-edit changeset would).
  @enum_fields [:sex, :spoiler_sex, :gender, :spoiler_gender, :blood_type]

  # ============================================================================
  # Detail Page
  # ============================================================================

  @doc """
  Loads the public character detail page data by slug.

  LiveView calls contexts directly, so this returns the full character page
  shape in one context call.
  """
  def get_character_page_by_slug(slug, viewer \\ nil) do
    with {:ok, character} <- get_character_by_slug(slug, viewer) do
      include_hidden? = can_view_hidden?(viewer)

      {:ok,
       %{
         character: character,
         visual_novels: list_visual_novels_for_character(character.id, include_hidden?),
         quotes:
           Kaguya.Characters.Quotes.list_quotes_for_character(character.id,
             user_id: viewer && viewer.id
           )
       }}
    end
  end

  def get_character_by_slug(slug, viewer \\ nil) do
    include_hidden? = can_view_hidden?(viewer)

    Character
    |> maybe_filter_hidden(include_hidden?)
    |> where([c], c.slug == ^slug)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      character -> {:ok, attach_viewer_state(character, viewer)}
    end
  end

  defp list_visual_novels_for_character(character_id, include_hidden?) do
    VNCharacter
    |> where([vc], vc.character_id == ^character_id)
    |> join(:inner, [vc], vn in assoc(vc, :visual_novel))
    |> maybe_filter_hidden_vns(include_hidden?)
    |> order_by([vc, vn],
      asc:
        fragment(
          "CASE ? WHEN 'main' THEN 0 WHEN 'primary' THEN 1 WHEN 'side' THEN 2 ELSE 3 END",
          vc.role
        ),
      desc: vn.ratings_count,
      asc: vn.title
    )
    |> select([vc, vn], %{role: vc.role, spoiler_level: vc.spoiler_level, visual_novel: vn})
    |> Repo.all()
  end

  defp attach_viewer_state(character, nil), do: Map.put(character, :favorited_by_me, false)

  defp attach_viewer_state(character, %{id: user_id}) do
    favorited? =
      Repo.exists?(
        from cf in CharacterFavorite,
          where: cf.character_id == ^character.id and cf.user_id == ^user_id
      )

    Map.put(character, :favorited_by_me, favorited?)
  end

  defp can_view_hidden?(%{mod_db: true}), do: true
  defp can_view_hidden?(%{role: role}) when role in [:moderator, :admin], do: true
  defp can_view_hidden?(_), do: false

  defp maybe_filter_hidden(query, true), do: query
  defp maybe_filter_hidden(query, false), do: where(query, [c], is_nil(c.hidden_at))

  defp maybe_filter_hidden_vns(query, true), do: query
  defp maybe_filter_hidden_vns(query, false), do: where(query, [_vc, vn], is_nil(vn.hidden_at))

  # ============================================================================
  # Browse / List
  # ============================================================================

  @valid_sorts ~w(most_popular name_asc name_desc recently_added)a

  @doc """
  Lists characters for the browse page. Accepts `:sort`, `:page`, `:page_size`.
  """
  # Frontend caps pagination at 10 pages — an unbounded count(*) would be a
  # full seq scan over the whole `characters` heap.
  @browse_max_pages 10

  def list_characters(opts \\ []) do
    sort = Keyword.get(opts, :sort, :most_popular)
    sort = if sort in @valid_sorts, do: sort, else: :most_popular
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20) |> min(100) |> max(1)
    max_count = @browse_max_pages * page_size + 1

    filtered =
      Character
      |> where([c], is_nil(c.hidden_at))

    items =
      filtered
      |> apply_sort(sort)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    total =
      from(sub in subquery(filtered |> select([c], c.id) |> limit(^max_count)),
        select: count()
      )
      |> Repo.one()

    %{
      items: items,
      pagination: %{
        page: page,
        page_size: page_size,
        total_count: total,
        total_pages: min(@browse_max_pages, max(1, div(total + page_size - 1, page_size)))
      }
    }
  end

  @doc """
  Returns visible characters for sitemap indexing.
  """
  def list_characters_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      from(c in Character,
        where: is_nil(c.hidden_at) and not is_nil(c.slug),
        order_by: [desc: c.updated_at, desc: c.id],
        select: %{
          id: c.id,
          slug: c.slug,
          updated_at: c.updated_at,
          primary_image_id: c.primary_image_id,
          vndb_image_id: c.vndb_image_id
        }
      )

    {items, pagination} = Pagination.paginate(query, page, page_size)

    items =
      Enum.map(items, fn item ->
        images = VisualNovels.build_character_image_urls(item)
        Map.put(item, :image_url, images[:large])
      end)

    {items, pagination}
  end

  # :most_popular sorts by `favorites_count` — the count of users who have
  # this character in their profile's favorite_characters list.
  defp apply_sort(query, :most_popular),
    do: order_by(query, [c], desc: c.favorites_count, asc: c.id)

  defp apply_sort(query, :name_asc),
    do: order_by(query, [c], asc: fragment("LOWER(?)", c.name), asc: c.id)

  defp apply_sort(query, :name_desc),
    do: order_by(query, [c], desc: fragment("LOWER(?)", c.name), asc: c.id)

  defp apply_sort(query, :recently_added),
    do: order_by(query, [c], desc: c.inserted_at, asc: c.id)

  # ============================================================================
  # Profile Favorites (character_favorites join table)
  # ============================================================================

  @doc """
  Lists users who have this character in their profile's `favorite_characters`
  list, newest favorited first. Cursor-paginated on `(inserted_at, user_id)` so
  ties on `inserted_at` don't drop rows and pages stay stable.

  Returns `{:ok, %{items, next_cursor, has_next}}` where each item is
  `%{user: %User{}, favorited_at: DateTime.t(), id: user_id}`. The synthetic
  `id` field is the user_id — the join table has a composite PK so there's no
  natural scalar id; using user_id here gives Apollo a cache-friendly key for
  the row object.
  """
  def list_favoriters_of(character_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 20)

    # CursorPagination.extract_cursor_value/2 reads the cursor columns
    # off the select map by their column atoms (:inserted_at, :user_id),
    # not by presentation aliases. Include both the row's real
    # column names AND the aliased fields — without this the extracted
    # cursor is {nil, nil} on every page and pagination loops forever.
    query =
      from cf in CharacterFavorite,
        join: u in assoc(cf, :user),
        where: cf.character_id == ^character_id,
        select: %{
          user: u,
          favorited_at: cf.inserted_at,
          id: u.id,
          inserted_at: cf.inserted_at,
          user_id: cf.user_id
        }

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        query,
        [:inserted_at, :user_id],
        [:datetime, :string],
        cursor,
        limit,
        :desc
      )

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  # ============================================================================
  # Edit / Revision Support
  # ============================================================================

  def get_for_edit(id) do
    case Repo.get(Character, id) do
      nil -> nil
      character -> Repo.preload(character, [:vn_characters, :character_images])
    end
  end

  @doc """
  Batch-loads multiple characters with the same preload set as
  `get_for_edit/1`. Used by the bulk revision writer to snapshot many
  entities in a single round-trip per preload instead of one per entity.
  """
  def batch_load_for_hist(ids) when is_list(ids) do
    from(c in Character, where: c.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:vn_characters, :character_images])
  end

  def create_from_edit(attrs) do
    with {:ok, character} <- %Character{} |> Character.changeset(attrs) |> Repo.insert(),
         :ok <- sync_appearances(character, attrs) do
      reindex_search(character)
      {:ok, character}
    end
  end

  @edit_scalar_fields ~w(name description sex spoiler_sex gender spoiler_gender
                         blood_type height weight age birthday bust waist hip cup_size
                         primary_image_id is_image_nsfw is_image_suggestive)a

  def apply_edit(character, changes) do
    attrs = Map.take(changes, @edit_scalar_fields)

    with {:ok, character} <- update_character_fields(character, attrs),
         :ok <- sync_appearances(character, changes),
         :ok <- remove_character_images(character, changes),
         :ok <- sync_character_images(character, changes) do
      reindex_search(character)
      {:ok, character}
    end
  end

  # Atomic image removal inside the edit transaction. Mirrors how
  # remove_covers / remove_screenshots work in `Kaguya.VisualNovels` so
  # the "replace image" flow (attach new + remove old + set primary) is
  # one round-trip and one revision instead of three async mutations.
  # Only deletes rows belonging to this character; foreign ids are
  # silently skipped. Caller is expected to set `primary_image_id` in
  # the same edit if the removed image was primary, otherwise the
  # character is left with a dangling primary_image_id.
  defp remove_character_images(character, %{removed_image_ids: ids})
       when is_list(ids) and ids != [] do
    from(i in CharacterImage,
      where: i.id in ^ids and i.character_id == ^character.id
    )
    |> Repo.delete_all()

    :ok
  end

  defp remove_character_images(_character, _changes), do: :ok

  # Updates per-image NSFW/suggestive flags only — does not add/remove rows
  # (image upload goes through a dedicated mutation; removal is handled by
  # remove_character_images above). Only updates rows belonging to this
  # character; foreign image_ids are silently skipped.
  defp sync_character_images(character, changes) do
    case Map.get(changes, :images) do
      nil ->
        :ok

      images when is_list(images) ->
        current_ids =
          from(i in CharacterImage, where: i.character_id == ^character.id, select: i.id)
          |> Repo.all()
          |> MapSet.new()

        for entry <- images, MapSet.member?(current_ids, entry.image_id) do
          updates =
            entry
            |> Map.take([:is_image_nsfw, :is_image_suggestive])
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)

          if updates != [] do
            from(i in CharacterImage, where: i.id == ^entry.image_id)
            |> Repo.update_all(set: updates)
          end
        end

        :ok
    end
  end

  # ============================================================================
  # Revision _hist Support
  # ============================================================================

  # Every column on `characters_hist`. Used by both write_hist (snapshot) and
  # apply_hist (restore). Includes everything that's either editable or
  # represents moderation state.
  #
  # Intentionally excluded — denormalized counter / cache (matches VNDB pattern):
  #   favorites_count — maintained by favorite actions, not user edits
  # Intentionally excluded — sync-managed external identifiers:
  #   vndb_id, vndb_image_id, temp_image_url
  @hist_fields ~w(name slug description sex spoiler_sex gender spoiler_gender
                  blood_type height weight age birthday bust waist hip cup_size
                  primary_image_id is_image_nsfw is_image_suggestive
                  hidden_at is_locked)a

  # Slug is auto-derived and stable; kept in @hist_fields for revert but
  # excluded from field groups so it never surfaces in the diff.
  @field_groups %{
    "name" => [:name],
    "description" => [:description],
    "image" => [:primary_image_id, :is_image_nsfw, :is_image_suggestive],
    "traits" => [
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
      :cup_size
    ],
    "appearances" => [:vn_characters],
    "images" => [:character_images],
    "removed_images" => [:removed_image_ids],
    "moderation" => [:hidden_at, :is_locked]
  }

  def write_hist(change_id, character) do
    hist_row =
      character
      |> Map.take(@hist_fields)
      |> Map.new(fn {k, v} -> {k, to_string_or_nil_enum(v)} end)
      |> Map.put(:change_id, change_id)

    Repo.insert_all(CharacterHist, [hist_row])

    appearance_rows =
      Enum.map(character.vn_characters, fn vc ->
        %{
          change_id: change_id,
          visual_novel_id: vc.visual_novel_id,
          character_id: character.id,
          role: to_string(vc.role),
          spoiler_level: vc.spoiler_level
        }
      end)

    if appearance_rows != [], do: Repo.insert_all(VnCharacterHist, appearance_rows)

    image_rows =
      Enum.map(character.character_images, fn img ->
        %{
          change_id: change_id,
          image_id: img.id,
          is_image_nsfw: img.is_image_nsfw,
          is_image_suggestive: img.is_image_suggestive
        }
      end)

    if image_rows != [], do: Repo.insert_all(CharacterImageHist, image_rows)
  end

  @doc """
  Bulk version of `write_hist/2` for seeding/backfill paths. Pairs must be
  `[{change_id, character_with_preloads}, ...]` (preloaded with `:vn_characters`
  and `:character_images`). One `insert_all` per `_hist` table for the batch.
  """
  def bulk_write_hist([]), do: :ok

  def bulk_write_hist(pairs) when is_list(pairs) do
    main_rows =
      Enum.map(pairs, fn {change_id, character} ->
        character
        |> Map.take(@hist_fields)
        |> Map.new(fn {k, v} -> {k, to_string_or_nil_enum(v)} end)
        |> Map.put(:change_id, change_id)
      end)

    chunked_insert_all(CharacterHist, main_rows)

    appearance_rows =
      Enum.flat_map(pairs, fn {change_id, character} ->
        Enum.map(character.vn_characters, fn vc ->
          %{
            change_id: change_id,
            visual_novel_id: vc.visual_novel_id,
            character_id: character.id,
            role: to_string(vc.role),
            spoiler_level: vc.spoiler_level
          }
        end)
      end)

    chunked_insert_all(VnCharacterHist, appearance_rows)

    image_rows =
      Enum.flat_map(pairs, fn {change_id, character} ->
        Enum.map(character.character_images, fn img ->
          %{
            change_id: change_id,
            image_id: img.id,
            is_image_nsfw: img.is_image_nsfw,
            is_image_suggestive: img.is_image_suggestive
          }
        end)
      end)

    chunked_insert_all(CharacterImageHist, image_rows)

    :ok
  end

  # Chunked to stay under PostgreSQL's 65535-parameter cap on insert_all.
  defp chunked_insert_all(_module, []), do: :ok

  defp chunked_insert_all(module, rows) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(module, &1))

    :ok
  end

  def load_hist(change_id) do
    hist = Repo.one(from h in CharacterHist, where: h.change_id == ^change_id)
    appearances = Repo.all(from vc in VnCharacterHist, where: vc.change_id == ^change_id)
    images = Repo.all(from i in CharacterImageHist, where: i.change_id == ^change_id)

    %{hist: hist, appearances: appearances, images: images}
  end

  @doc """
  Batched version of `load_hist/1`. 3 queries for any number of change_ids.
  """
  def bulk_load_hist([]), do: %{}

  def bulk_load_hist(change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    hists =
      Repo.all(from h in CharacterHist, where: h.change_id in ^ids)
      |> Map.new(&{&1.change_id, &1})

    apps =
      Repo.all(from vc in VnCharacterHist, where: vc.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    images =
      Repo.all(from i in CharacterImageHist, where: i.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    Map.new(ids, fn change_id ->
      {change_id,
       %{
         hist: Map.get(hists, change_id),
         appearances: Map.get(apps, change_id, []),
         images: Map.get(images, change_id, [])
       }}
    end)
  end

  def apply_hist(character, hist_data) do
    # Bypass Character.changeset on purpose: hist data is known-good and
    # contains slug + hidden_at + is_locked which the user-edit changeset
    # doesn't accept. Ecto.Changeset.change/2 restores everything verbatim.
    attrs =
      hist_data.hist
      |> Map.take(@hist_fields)
      |> normalize_hist_attrs()

    with {:ok, character} <- character |> Ecto.Changeset.change(attrs) |> Repo.update() do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Replace appearances. Skip rows whose VN was deleted in the meantime.
      from(vc in VNCharacter, where: vc.character_id == ^character.id) |> Repo.delete_all()
      restore_appearances(character.id, hist_data.appearances, now)

      # Restore character_images metadata: only updates rows that still exist
      # (don't re-create deleted images — same approach as VN screenshots).
      restore_character_image_metadata(character.id, hist_data.images)

      reindex_search(character)
      {:ok, character}
    end
  end

  defp restore_appearances(character_id, appearances, now) do
    if appearances != [] do
      vn_ids = Enum.map(appearances, & &1.visual_novel_id) |> Enum.uniq()

      existing =
        from(v in Kaguya.VisualNovels.VisualNovel, where: v.id in ^vn_ids, select: v.id)
        |> Repo.all()
        |> MapSet.new()

      rows =
        appearances
        |> Enum.filter(&MapSet.member?(existing, &1.visual_novel_id))
        |> Enum.map(fn a ->
          %{
            character_id: character_id,
            visual_novel_id: a.visual_novel_id,
            role: String.to_existing_atom(a.role),
            spoiler_level: a.spoiler_level,
            inserted_at: now,
            updated_at: now
          }
        end)

      if rows != [], do: Repo.insert_all(VNCharacter, rows)
    end

    :ok
  end

  defp restore_character_image_metadata(_character_id, []), do: :ok

  defp restore_character_image_metadata(character_id, hist_images) do
    hist_map = Map.new(hist_images, &{&1.image_id, &1})

    current_ids =
      from(i in CharacterImage, where: i.character_id == ^character_id, select: i.id)
      |> Repo.all()
      |> MapSet.new()

    for {iid, meta} <- hist_map, MapSet.member?(current_ids, iid) do
      from(i in CharacterImage, where: i.id == ^iid)
      |> Repo.update_all(
        set: [
          is_image_nsfw: meta.is_image_nsfw,
          is_image_suggestive: meta.is_image_suggestive
        ]
      )
    end

    :ok
  end

  # Convert hist string values back to atoms for Ecto.Enum fields when
  # restoring with Ecto.Changeset.change/2.
  defp normalize_hist_attrs(attrs) do
    Enum.reduce(@enum_fields, attrs, fn field, acc ->
      case Map.get(acc, field) do
        nil -> acc
        val when is_atom(val) -> acc
        val when is_binary(val) -> Map.put(acc, field, String.to_existing_atom(val))
      end
    end)
  end

  def changed_field_groups(character, changes) do
    @field_groups
    |> Enum.filter(fn {_group, fields} ->
      Enum.any?(fields, fn
        :vn_characters ->
          Map.has_key?(changes, :appearances)

        :character_images ->
          Map.has_key?(changes, :images)

        :removed_image_ids ->
          case Map.get(changes, :removed_image_ids) do
            ids when is_list(ids) -> ids != []
            _ -> false
          end

        field ->
          Map.has_key?(changes, field) && Map.get(changes, field) != Map.get(character, field)
      end)
    end)
    |> Enum.map(fn {group, _} -> group end)
    |> Enum.sort()
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp update_character_fields(character, attrs) when attrs == %{}, do: {:ok, character}

  defp update_character_fields(character, attrs) do
    character |> Character.changeset(attrs) |> Repo.update()
  end

  defp sync_appearances(character, changes) do
    case Map.get(changes, :appearances) do
      nil ->
        :ok

      appearances when is_list(appearances) ->
        vn_ids = Enum.map(appearances, & &1.visual_novel_id) |> Enum.uniq()

        existing =
          from(v in Kaguya.VisualNovels.VisualNovel, where: v.id in ^vn_ids, select: v.id)
          |> Repo.all()
          |> MapSet.new()

        missing = Enum.reject(vn_ids, &MapSet.member?(existing, &1))

        if missing != [] do
          {:error, "Visual novel(s) not found: #{Enum.join(missing, ", ")}"}
        else
          from(vc in VNCharacter, where: vc.character_id == ^character.id) |> Repo.delete_all()
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          rows =
            Enum.map(appearances, fn a ->
              %{
                character_id: character.id,
                visual_novel_id: a.visual_novel_id,
                role: to_atom(a.role),
                spoiler_level: Map.get(a, :spoiler_level, 0),
                inserted_at: now,
                updated_at: now
              }
            end)

          if rows != [], do: Repo.insert_all(VNCharacter, rows)
          :ok
        end
    end
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp to_string_or_nil_enum(value) when is_boolean(value), do: value

  defp to_string_or_nil_enum(value) when is_atom(value) and not is_nil(value),
    do: to_string(value)

  defp to_string_or_nil_enum(value), do: value

  defp reindex_search(%Character{} = char) do
    if is_nil(char.hidden_at) do
      SearchIndex.index_characters(char)
    else
      SearchIndex.remove_character(char.id)
    end
  rescue
    e ->
      require Logger

      Logger.warning(
        "[Characters] Meilisearch reindex failed for #{char.id}: #{Exception.message(e)}"
      )
  end
end

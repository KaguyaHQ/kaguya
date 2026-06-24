defmodule Kaguya.Shelves do
  @moduledoc """
  Context for Visual Novel reading status (library) operations.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Shelves.{ReadingStatus, Shelf, ShelfItem}
  alias Kaguya.Reviews.{Review, Rating}
  alias Kaguya.Reviews.RatingUpdater
  alias Kaguya.Reviews.UserStatsUpdater
  alias Kaguya.Activities
  alias Kaguya.Users

  # ============================================================================
  # Status Operations
  # ============================================================================

  @doc """
  Gets the reading status for a VN belonging to the current user.
  """
  def get_reading_status(user_id, visual_novel_id) do
    case Repo.get_by(ReadingStatus, user_id: user_id, visual_novel_id: visual_novel_id) do
      nil -> {:ok, nil}
      status -> {:ok, status}
    end
  end

  @doc """
  Sets reading status for one or more VNs.
  """
  def set_reading_status(user_id, visual_novel_ids, attrs) when is_list(visual_novel_ids) do
    status = Map.get(attrs, :status)

    # date_finished is only set when explicitly provided by the caller

    # Fetch existing statuses so we only record activity when status actually changes
    existing_statuses =
      from(s in ReadingStatus,
        where: s.user_id == ^user_id and s.visual_novel_id in ^visual_novel_ids,
        select: {s.visual_novel_id, s.status}
      )
      |> Repo.all()
      |> Map.new()

    with {:ok, result} <- upsert_statuses(user_id, visual_novel_ids, attrs) do
      changed_vn_ids =
        Enum.filter(visual_novel_ids, &(Map.get(existing_statuses, &1) != status))

      if status == :not_interested and changed_vn_ids != [] do
        clear_ratings_for_vns(user_id, changed_vn_ids)
      end

      maybe_autofill_date_started(user_id, visual_novel_ids, status, attrs)

      if changed_vn_ids != [] do
        record_status_activities(user_id, changed_vn_ids, status)
      end

      {:ok, result}
    end
  end

  def set_reading_status(user_id, visual_novel_id, attrs) do
    set_reading_status(user_id, [visual_novel_id], attrs)
  end

  defp clear_ratings_for_vns(user_id, visual_novel_ids) do
    ratings =
      from(r in Rating,
        where: r.user_id == ^user_id and r.visual_novel_id in ^visual_novel_ids
      )
      |> Repo.all()

    suppressed? = Users.ratings_suppressed?(user_id)

    for rating <- ratings do
      Repo.delete!(rating)

      unless suppressed?,
        do: RatingUpdater.adjust_vn_rating(rating.visual_novel_id, rating.rating, nil)

      UserStatsUpdater.adjust_user_vn_rating(user_id, rating.rating, nil)
      Activities.delete_activity(user_id, :rated, "rating", rating.id)
    end
  end

  @doc """
  Null out specific columns on a user's reading_status row.

  `set_reading_status/3` (via `upsert_statuses/3`) intentionally treats `nil`
  as "leave alone" so callers can do partial updates. That makes it impossible
  to clear a `date_started`/`date_finished` once it has been set. This helper
  fills that gap — call it after a set when the caller knows a field should be
  cleared (e.g. range → single-date transitions in the picker).
  """
  def clear_reading_status_fields(_user_id, _vn_id, []), do: :ok

  def clear_reading_status_fields(user_id, vn_id, fields) when is_list(fields) do
    set =
      fields
      |> Enum.map(&{&1, nil})
      |> Keyword.put(:updated_at, DateTime.utc_now() |> DateTime.truncate(:second))

    from(rs in ReadingStatus,
      where: rs.user_id == ^user_id and rs.visual_novel_id == ^vn_id
    )
    |> Repo.update_all(set: set)

    :ok
  end

  @doc """
  Deletes reading status for a VN, including its rating and review.
  """
  def delete_reading_status(user_id, visual_novel_id) do
    review =
      Repo.get_by(Review, user_id: user_id, visual_novel_id: visual_novel_id)

    rating =
      Repo.get_by(Rating, user_id: user_id, visual_novel_id: visual_novel_id)

    result =
      Repo.transact(fn ->
        # Delete review if exists
        if review do
          Repo.delete!(review)
          RatingUpdater.adjust_vn_review_count(visual_novel_id, -1)
          UserStatsUpdater.adjust_user_vn_review_count(user_id, -1)
        end

        # Delete rating if exists
        if rating do
          Repo.delete!(rating)

          unless Users.ratings_suppressed?(user_id),
            do: RatingUpdater.adjust_vn_rating(visual_novel_id, rating.rating, nil)

          UserStatsUpdater.adjust_user_vn_rating(user_id, rating.rating, nil)
        end

        # Delete reading status
        query =
          from(s in ReadingStatus,
            where: s.user_id == ^user_id and s.visual_novel_id == ^visual_novel_id
          )

        case Repo.delete_all(query) do
          {1, _} -> {:ok, true}
          {0, _} -> {:error, :not_found}
        end
      end)

    with {:ok, true} <- result do
      # Clean up all activities related to this user+VN
      if review, do: Activities.delete_activities_for_entity("review", review.id)
      if rating, do: Activities.delete_activity(user_id, :rated, "rating", rating.id)
      delete_status_activities(user_id, visual_novel_id)
      {:ok, true}
    end
  end

  # ============================================================================
  # Stats Helpers
  # ============================================================================

  @doc """
  Counts VNs in user's library by status.
  """
  def count_library_vns(user_id, status \\ nil) do
    query =
      ReadingStatus
      |> where([s], s.user_id == ^user_id)

    query =
      if status do
        where(query, [s], s.status == ^status)
      else
        query
      end

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Counts VNs in user's library excluding not_interested and want_to_read statuses.
  """
  def count_active_library_vns(user_id, allowed_categories \\ nil) do
    query =
      ReadingStatus
      |> where([s], s.user_id == ^user_id)
      |> where([s], s.status not in [:not_interested, :want_to_read])

    query =
      if allowed_categories do
        from rs in query,
          join: vn in Kaguya.VisualNovels.VisualNovel,
          on: vn.id == rs.visual_novel_id,
          where: vn.title_category in ^allowed_categories
      else
        query
      end

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Lists VNs read by a user in a specific year.
  """
  def list_vns_read_in_year(user_id, year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year, 12, 31)

    VisualNovel
    |> join(:inner, [vn], rs in assoc(vn, :reading_statuses),
      on: rs.user_id == ^user_id and rs.status == :read
    )
    |> where([_, rs], rs.date_finished >= ^start_date and rs.date_finished <= ^end_date)
    |> order_by([_, rs], desc: rs.date_finished)
    |> Repo.all()
  end

  # ============================================================================
  # Internal: Status upsert
  # ============================================================================

  defp upsert_statuses(user_id, visual_novel_ids, args) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    date_started = Map.get(args, :date_started)
    note = Map.get(args, :note)
    note_provided? = Map.has_key?(args, :note)

    if note_provided? && note != nil && String.length(note) > 280 do
      {:error, "Note must be 280 characters or less"}
    else
      {status, date_finished} =
        case {Map.get(args, :status), Map.get(args, :date_finished)} do
          {_s, df} when not is_nil(df) -> {:read, df}
          {s, df} -> {s, df}
        end

      set_fields =
        [status: status, updated_at: now]
        |> maybe_add(:date_started, date_started)
        |> maybe_add(:date_finished, date_finished)
        |> maybe_put_note(note_provided?, note)

      entries =
        for vn_id <- visual_novel_ids do
          %{
            id: UUIDv7.generate(),
            user_id: user_id,
            visual_novel_id: vn_id,
            status: status,
            date_started: date_started,
            date_finished: date_finished,
            note: note,
            library_added_at: now,
            inserted_at: now,
            updated_at: now
          }
        end

      {num_inserted, _} =
        Repo.insert_all(ReadingStatus, entries,
          on_conflict: [set: set_fields],
          conflict_target: [:user_id, :visual_novel_id]
        )

      {:ok, %{total_works_processed: length(visual_novel_ids), successful_works: num_inserted}}
    end
  end

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: Keyword.put(list, key, value)

  defp maybe_put_note(list, false, _note), do: list
  defp maybe_put_note(list, true, note), do: Keyword.put(list, :note, note)

  # `Map.has_key?` (not nil-check) is what exempts importers — they pass the
  # key explicitly, often as nil, and that intent must be honored.
  defp maybe_autofill_date_started(user_id, visual_novel_ids, :currently_reading, attrs) do
    if Map.has_key?(attrs, :date_started) do
      :ok
    else
      today = Date.utc_today()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(rs in ReadingStatus,
        where:
          rs.user_id == ^user_id and
            rs.visual_novel_id in ^visual_novel_ids and
            rs.status == :currently_reading and
            is_nil(rs.date_started)
      )
      |> Repo.update_all(set: [date_started: today, updated_at: now])

      :ok
    end
  end

  defp maybe_autofill_date_started(_user_id, _vn_ids, _status, _attrs), do: :ok

  # ----------------------------------------------------------------------------
  # Activity helpers
  # ----------------------------------------------------------------------------

  defp record_status_activities(user_id, visual_novel_ids, status) do
    vns_by_id =
      from(vn in VisualNovel, where: vn.id in ^visual_novel_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    for vn_id <- visual_novel_ids do
      vn = Map.get(vns_by_id, vn_id)

      # Delete previous status_changed activity for this user+VN
      delete_status_activities(user_id, vn_id)

      Activities.record_activity(%{
        user_id: user_id,
        action: :status_changed,
        entity_type: "reading_status",
        # entity_id is vn_id (not reading_status_id) since statuses use composite key
        entity_id: vn_id,
        metadata: vn_metadata(vn, status)
      })
    end
  end

  defp delete_status_activities(user_id, visual_novel_id) do
    Activities.delete_activity(user_id, :status_changed, "reading_status", visual_novel_id)
  end

  defp vn_metadata(nil, status) do
    %{status: to_string(status)}
  end

  defp vn_metadata(vn, status) do
    %{
      status: to_string(status),
      vn_id: vn.id,
      vn_title: vn.title,
      vn_slug: vn.slug,
      vn_image_url: VisualNovels.build_image_urls(vn)[:small],
      vn_release_year: release_year(vn.release_date)
    }
  end

  defp release_year(%Date{year: y}), do: y
  defp release_year(_), do: nil

  # ============================================================================
  # Custom Shelf CRUD
  # ============================================================================

  @doc """
  Lists all shelves for a user.
  """
  def list_shelves_for_user(user_id) do
    shelves =
      Shelf
      |> where([s], s.user_id == ^user_id)
      |> order_by([s], asc: s.name)
      |> Repo.all()

    {:ok, shelves}
  end

  @doc """
  List all shelves for a user, each with its 3 most-recent visual novels.
  """
  def list_shelves_with_vns_for_user(user_id) do
    vns_sub =
      from si in ShelfItem,
        where: si.shelf_id == parent_as(:shelf).id,
        order_by: [desc: si.inserted_at],
        limit: 3,
        join: v in assoc(si, :visual_novel),
        select: v

    query =
      from s in Shelf,
        as: :shelf,
        where: s.user_id == ^user_id,
        order_by: [asc: s.name],
        left_lateral_join: v in subquery(vns_sub),
        on: true,
        as: :vns,
        preload: [visual_novels: v]

    payload =
      Repo.all(query)
      |> Enum.map(&%{shelf: &1, visual_novels: &1.visual_novels})

    {:ok, payload}
  end

  @doc """
  Gets shelves for a VN belonging to the current user.
  """
  def list_user_shelves_for_vn(user_id, visual_novel_id) do
    shelves =
      Shelf
      |> join(:inner, [s], j in ShelfItem, on: j.shelf_id == s.id)
      |> where([s, j], s.user_id == ^user_id and j.visual_novel_id == ^visual_novel_id)
      |> select([s, _j], s)
      |> Repo.all()

    {:ok, shelves}
  end

  @doc """
  Gets a shelf by slug for a user.
  """
  def get_shelf_by_slug_for_user(user_id, slug) do
    case Repo.get_by(Shelf, user_id: user_id, slug: slug) do
      nil -> {:error, :not_found}
      shelf -> {:ok, shelf}
    end
  end

  @doc """
  Gets a single shelf.
  """
  def get_shelf(id) do
    case Repo.get(Shelf, id) do
      nil -> {:error, :not_found}
      shelf -> {:ok, shelf}
    end
  end

  @doc """
  Creates a shelf.
  """
  def create_shelf(attrs \\ %{}) do
    %Shelf{}
    |> Shelf.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Renames a shelf.
  """
  def rename_shelf(user_id, id, new_name) do
    with {:ok, shelf} <- get_shelf(id),
         true <- shelf.user_id == user_id || {:error, :unauthorized} do
      shelf
      |> Shelf.changeset(%{name: new_name})
      |> Repo.update()
    end
  end

  @doc """
  Deletes a shelf.
  """
  def delete_shelf(user_id, id) do
    with {:ok, shelf} <- get_shelf(id),
         true <- shelf.user_id == user_id || {:error, :unauthorized},
         {:ok, _deleted} <- Repo.delete(shelf) do
      {:ok, true}
    end
  end

  # ============================================================================
  # VN <-> Shelf Operations
  # ============================================================================

  @doc """
  Adds VNs to shelves.
  """
  def add_vns_to_shelves(user_id, shelf_ids, vn_ids) do
    handle_shelf_operation(user_id, shelf_ids, vn_ids, :insert)
  end

  @doc """
  Removes VNs from shelves.
  """
  def remove_vns_from_shelves(user_id, shelf_ids, vn_ids) do
    handle_shelf_operation(user_id, shelf_ids, vn_ids, :delete)
  end

  # ============================================================================
  # Internal: Shelf helpers
  # ============================================================================

  defp handle_shelf_operation(user_id, shelf_ids, vn_ids, action) do
    case fetch_valid_shelves_and_vns(user_id, shelf_ids, vn_ids) do
      {:error, errors} ->
        {:ok, %{success: false, shelves_affected: 0, vns_affected: 0, errors: errors}}

      {:ok, %{shelves: shelves, vn_ids: valid_vn_ids}} ->
        {shelves_affected, vns_affected, errors} =
          Enum.reduce(shelves, {0, 0, []}, fn shelf, {s_acc, v_acc, e_acc} ->
            case modify_vns_on_shelf(shelf, valid_vn_ids, action) do
              {:ok, count} -> {s_acc + 1, v_acc + count, e_acc}
              {:error, message} -> {s_acc, v_acc, [message | e_acc]}
            end
          end)

        {:ok,
         %{
           success: vns_affected > 0,
           shelves_affected: shelves_affected,
           vns_affected: vns_affected,
           errors: Enum.reverse(errors)
         }}
    end
  end

  defp modify_vns_on_shelf(shelf, vn_ids, :insert) do
    Repo.transaction(fn ->
      current_time = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(vn_ids, fn vn_id ->
          %{
            shelf_id: shelf.id,
            visual_novel_id: vn_id,
            inserted_at: current_time,
            updated_at: current_time
          }
        end)

      {num_inserted, _} = Repo.insert_all(ShelfItem, entries, on_conflict: :nothing)

      if num_inserted > 0 do
        Repo.update_all(
          from(s in Shelf, where: s.id == ^shelf.id),
          inc: [vns_count: num_inserted]
        )

        num_inserted
      else
        Repo.rollback("No new VNs were added to shelf #{shelf.id}.")
      end
    end)
  end

  defp modify_vns_on_shelf(shelf, vn_ids, :delete) do
    Repo.transaction(fn ->
      {num_deleted, _} =
        from(j in ShelfItem,
          where: j.shelf_id == ^shelf.id and j.visual_novel_id in ^vn_ids
        )
        |> Repo.delete_all()

      if num_deleted > 0 do
        Repo.update_all(
          from(s in Shelf, where: s.id == ^shelf.id),
          inc: [vns_count: -num_deleted]
        )

        num_deleted
      else
        Repo.rollback("No VNs were removed from shelf #{shelf.id}.")
      end
    end)
  end

  defp fetch_valid_shelves_and_vns(user_id, shelf_ids, vn_ids) do
    shelves =
      from(s in Shelf, where: s.id in ^shelf_ids and s.user_id == ^user_id, select: s)
      |> Repo.all()

    valid_vn_ids =
      from(vn in VisualNovel, where: vn.id in ^vn_ids, select: vn.id)
      |> Repo.all()

    cond do
      shelves == [] ->
        {:error, ["No valid shelves found for user."]}

      valid_vn_ids == [] ->
        {:error, ["No valid VNs found."]}

      true ->
        {:ok, %{shelves: shelves, vn_ids: valid_vn_ids}}
    end
  end

  # ============================================================================
  # Vote Date Fallback (for VNDB imports)
  # ============================================================================

  alias Kaguya.Users.VndbImport

  @doc """
  Fills NULL date_finished with vote_date for items from a specific import.
  Uses the import JSON to identify which items had NULL date_finished originally.
  Returns count of updated records.
  """
  def apply_vote_date_fallback(user_id, import_id) do
    with {:ok, import_record} <- get_import(user_id, import_id),
         {:ok, updates} <- build_vote_date_updates(import_record) do
      if updates == [] do
        {:ok, 0}
      else
        slugs = Enum.map(updates, & &1.slug)
        slug_to_date = Map.new(updates, fn %{slug: s, vote_date: d} -> {s, d} end)

        # Resolve slugs to canonical VN ids — falls through
        # `slug_redirects` so a user re-importing with a now-merged or
        # renamed slug still updates the canonical's reading status.
        slug_to_vn_id = Kaguya.VisualNovels.resolve_vn_ids_by_slugs(slugs)

        if map_size(slug_to_vn_id) == 0 do
          {:ok, 0}
        else
          # Group by date to minimize queries (most will share same vote_date pattern)
          by_date =
            slug_to_vn_id
            |> Enum.map(fn {slug, vn_id} -> {vn_id, Map.get(slug_to_date, slug)} end)
            |> Enum.reject(fn {_, date} -> is_nil(date) end)
            |> Enum.group_by(fn {_, date} -> date end, fn {vn_id, _} -> vn_id end)

          # One query per unique date (typically much fewer than N)
          count =
            Enum.reduce(by_date, 0, fn {date, vn_id_list}, acc ->
              {n, _} =
                from(rs in ReadingStatus,
                  where:
                    rs.user_id == ^user_id and
                      rs.visual_novel_id in ^vn_id_list and
                      is_nil(rs.date_finished)
                )
                |> Repo.update_all(set: [date_finished: date])

              acc + n
            end)

          {:ok, count}
        end
      end
    end
  end

  @doc """
  Reverts vote date fallback - only clears date_finished if it still equals the vote_date.
  This preserves any manual edits the user made after applying the fallback.
  """
  def revert_vote_date_fallback(user_id, import_id) do
    with {:ok, import_record} <- get_import(user_id, import_id),
         {:ok, updates} <- build_vote_date_updates(import_record) do
      if updates == [] do
        {:ok, 0}
      else
        slugs = Enum.map(updates, & &1.slug)

        slug_to_vn_id = Kaguya.VisualNovels.resolve_vn_ids_by_slugs(slugs)

        # Group by vote_date so we can batch updates
        by_date =
          updates
          |> Enum.map(fn %{slug: slug, vote_date: date} ->
            {Map.get(slug_to_vn_id, slug), date}
          end)
          |> Enum.reject(fn {vn_id, _} -> is_nil(vn_id) end)
          |> Enum.group_by(fn {_, date} -> date end, fn {vn_id, _} -> vn_id end)

        # Only clear date_finished if it equals the vote_date (preserves manual edits)
        count =
          Enum.reduce(by_date, 0, fn {vote_date, vn_id_list}, acc ->
            {updated, _} =
              from(rs in ReadingStatus,
                where:
                  rs.user_id == ^user_id and
                    rs.visual_novel_id in ^vn_id_list and
                    rs.date_finished == ^vote_date
              )
              |> Repo.update_all(set: [date_finished: nil])

            acc + updated
          end)

        {:ok, count}
      end
    end
  end

  @doc """
  Returns stats for vote date fallback eligibility from a specific import.
  - eligible_count: Items where import JSON shows date_finished=null but vote_date exists
  - applied_count: Of those, how many currently have date_finished set in DB
  """
  def vote_date_fallback_stats(user_id, import_id) do
    with {:ok, import_record} <- get_import(user_id, import_id),
         {:ok, updates} <- build_vote_date_updates(import_record) do
      eligible_count = length(updates)

      if eligible_count == 0 do
        {:ok, %{eligible_count: 0, applied_count: 0}}
      else
        slugs = Enum.map(updates, & &1.slug)
        slug_to_vn_id = Kaguya.VisualNovels.resolve_vn_ids_by_slugs(slugs)

        # Count only rows whose `date_finished` exactly matches the vote_date
        # we'd backfill from. Anything else (manual edits, dates the user set
        # before the import) doesn't count as "fallback applied", so the
        # toggle can swing all the way back to OFF when the user reverts.
        by_date =
          updates
          |> Enum.map(fn %{slug: slug, vote_date: date} ->
            {Map.get(slug_to_vn_id, slug), date}
          end)
          |> Enum.reject(fn {vn_id, _} -> is_nil(vn_id) end)
          |> Enum.group_by(fn {_, date} -> date end, fn {vn_id, _} -> vn_id end)

        applied_count =
          Enum.reduce(by_date, 0, fn {vote_date, vn_id_list}, acc ->
            count =
              Repo.one(
                from rs in ReadingStatus,
                  where:
                    rs.user_id == ^user_id and rs.visual_novel_id in ^vn_id_list and
                      rs.date_finished == ^vote_date,
                  select: count()
              ) || 0

            acc + count
          end)

        {:ok, %{eligible_count: eligible_count, applied_count: applied_count}}
      end
    end
  end

  defp get_import(user_id, import_id) do
    case Repo.get_by(VndbImport, id: import_id, user_id: user_id) do
      nil -> {:error, :not_found}
      import_record -> {:ok, import_record}
    end
  end

  defp build_vote_date_updates(import_record) do
    items = get_in(import_record.result, ["imported_items"]) || []

    updates =
      items
      |> Enum.filter(fn item ->
        item["status"] == "read" &&
          is_nil(item["date_finished"]) &&
          item["vote_date"] != nil
      end)
      |> Enum.map(fn item ->
        %{slug: item["slug"], vote_date: Date.from_iso8601!(item["vote_date"])}
      end)

    {:ok, updates}
  end
end

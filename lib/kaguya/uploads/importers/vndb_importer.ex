defmodule Kaguya.Uploads.VndbImporter do
  @moduledoc """
  Imports visual novels from a VNDB XML export file.

  Label mapping:
  - 1 (Playing) → :currently_reading
  - 2 (Finished) → :read
  - 3 (Stalled) → :on_hold
  - 4 (Dropped) → :did_not_finish
  - 5 (Wishlist) → :want_to_read
  - 6 (Blacklist) → :not_interested
  - 7 (Voted) → Informational only (has vote)
  - ≥10 → Custom shelves
  """

  require Logger

  alias Kaguya.Repo
  alias Kaguya.Shelves.{ReadingStatus, ShelfItem}
  alias Kaguya.Reviews.{Rating, Review}

  alias Kaguya.VisualNovels

  alias Kaguya.Uploads.Helpers.{
    VndbXmlParser,
    VndbPrefetcher,
    VnImportInserter,
    VnImportStats
  }

  # Label ID to status mapping
  @status_labels %{
    1 => :currently_reading,
    2 => :read,
    3 => :on_hold,
    4 => :did_not_finish,
    5 => :want_to_read,
    6 => :not_interested
  }

  @doc """
  Parses the XML content and inserts all VN data.
  Returns {:ok, summary} or {:error, reason}.
  """
  def parse_and_insert_vns(xml_content, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. Parse XML
    with {:ok, parsed} <- VndbXmlParser.parse(xml_content) do
      do_import(parsed, user_id, now)
    end
  end

  defp do_import(parsed, user_id, now) do
    # 2. Build initial accumulator
    initial_acc = %{
      ratings: [],
      reviews: [],
      reading_statuses: [],
      shelf_names: MapSet.new(),
      shelf_items: [],
      imported_items: [],
      missing_vns: [],
      banned_vns: [],
      processed_vn_ids: MapSet.new(),
      # Track VNs that have reading statuses (for O(1) lookup in review processing)
      vns_with_status: MapSet.new()
    }

    # 3. Prefetch vndb_id → visual_novel_id and vn_link_map in single query
    acc = VndbPrefetcher.prefetch(initial_acc, parsed.vns, parsed.reviews)

    # 4. Build label name lookup from parsed labels
    label_names =
      parsed.labels
      |> Enum.map(fn label -> {label.id, label.name} end)
      |> Map.new()

    acc = Map.put(acc, :label_names, label_names)

    # 5. Process each VN entry
    acc =
      Enum.reduce(parsed.vns, acc, fn vn, acc ->
        process_vn_entry(vn, user_id, now, acc)
      end)

    # 6. Process reviews separately (they're in a different section)
    vn_link_map = acc.vn_link_map

    acc =
      Enum.reduce(parsed.reviews, acc, fn review, acc ->
        process_review_entry(review, user_id, now, vn_link_map, acc)
      end)

    # 7. Commit to database
    result = commit_import(acc, user_id, now)

    # 8. Log missing VNs
    log_missing_vns(acc.missing_vns, user_id)

    result
  end

  # ---------------------------------------------------------------------------
  # VN Entry Processing
  # ---------------------------------------------------------------------------

  defp process_vn_entry(vn, user_id, now, acc) do
    vndb_id = vn.vndb_id
    vn_map = acc.vn_map

    case Map.get(vn_map, vndb_id) do
      nil ->
        if Map.has_key?(acc.banned_map, vndb_id) do
          # VN is banned by us, add to banned list
          banned_entry = %{vndb_url: "https://vndb.org/#{vndb_id}", title: vn.title}
          update_in(acc, [:banned_vns], &[banned_entry | &1])
        else
          # VN not in database, add to missing list
          missing_entry = %{vndb_url: "https://vndb.org/#{vndb_id}", title: vn.title}
          update_in(acc, [:missing_vns], &[missing_entry | &1])
        end

      visual_novel_id ->
        # VN exists, process it
        acc
        |> collect_rating(user_id, visual_novel_id, vn, now)
        |> collect_reading_status(user_id, visual_novel_id, vn, now)
        |> collect_shelves(user_id, visual_novel_id, vn, now)
        |> collect_imported_item(visual_novel_id, vn)
        |> update_in([:processed_vn_ids], &MapSet.put(&1, visual_novel_id))
    end
  end

  defp collect_rating(acc, user_id, visual_novel_id, vn, now) do
    case convert_vndb_vote(vn.vote) do
      nil ->
        acc

      rating_value ->
        rating_data = %{
          id: UUIDv7.generate(),
          user_id: user_id,
          visual_novel_id: visual_novel_id,
          rating: rating_value,
          source: "vndb",
          inserted_at: parse_timestamp(vn.vote_timestamp) || now,
          updated_at: now
        }

        update_in(acc, [:ratings], &[rating_data | &1])
    end
  end

  defp collect_reading_status(acc, user_id, visual_novel_id, vn, now) do
    # Find status from labels (1-5) only - skip entries without explicit VNDB labels
    status = find_status_from_labels(vn.labels)

    if status do
      status_data = %{
        id: UUIDv7.generate(),
        user_id: user_id,
        visual_novel_id: visual_novel_id,
        status: status,
        date_started: parse_date(vn.started),
        date_finished: parse_date(vn.finished) || vote_date_fallback(status, vn),
        library_added_at: parse_timestamp(vn.added) || now,
        note: truncate_note(vn.notes),
        source: "vndb",
        inserted_at: now,
        updated_at: now
      }

      acc
      |> update_in([:reading_statuses], &[status_data | &1])
      |> update_in([:vns_with_status], &MapSet.put(&1, visual_novel_id))
    else
      acc
    end
  end

  defp collect_shelves(acc, _user_id, visual_novel_id, vn, now) do
    label_names = acc.label_names

    # Get custom shelf labels (≥10 only)
    shelf_labels =
      vn.labels
      |> Enum.filter(fn label ->
        label.id >= 10
      end)

    Enum.reduce(shelf_labels, acc, fn label, acc ->
      shelf_name = label.name || Map.get(label_names, label.id, "Unknown")

      acc
      |> update_in([:shelf_names], &MapSet.put(&1, shelf_name))
      |> update_in([:shelf_items], fn items ->
        [
          %{
            shelf_name: shelf_name,
            visual_novel_id: visual_novel_id,
            inserted_at: now,
            updated_at: now
          }
          | items
        ]
      end)
    end)
  end

  defp collect_imported_item(acc, visual_novel_id, vn) do
    detail = Map.get(acc.vn_detail_map, visual_novel_id, %{})
    vote_timestamp = parse_timestamp(vn.vote_timestamp)

    item = %{
      id: visual_novel_id,
      title: detail[:title] || vn.title,
      slug: detail[:slug],
      images: VisualNovels.build_image_urls(detail),
      has_ero: VisualNovels.cover_nsfw?(detail),
      rating: convert_vndb_vote(vn.vote),
      status: find_status_from_labels(vn.labels),
      release_date: detail[:release_date],
      date_added: parse_timestamp(vn.added),
      date_started: parse_date(vn.started),
      date_finished: parse_date(vn.finished),
      vote_date: vote_timestamp && DateTime.to_date(vote_timestamp),
      last_updated: parse_timestamp(vn.modified) || parse_timestamp(vn.added)
    }

    update_in(acc, [:imported_items], &[item | &1])
  end

  # ---------------------------------------------------------------------------
  # Review Processing
  # ---------------------------------------------------------------------------

  defp process_review_entry(review, user_id, now, vn_link_map, acc) do
    vndb_id = review.vndb_id
    vn_map = acc.vn_map

    case Map.get(vn_map, vndb_id) do
      nil ->
        # VN not in database or banned, skip review
        acc

      visual_novel_id ->
        if review.text && review.text != "" do
          markdown_content = VndbToMarkdown.convert(review.text, vn_link_map)

          review_data = %{
            id: UUIDv7.generate(),
            user_id: user_id,
            visual_novel_id: visual_novel_id,
            content: markdown_content,
            is_spoiler: review.spoiler || false,
            source: "vndb",
            inserted_at: parse_timestamp(review.added) || now,
            updated_at: now
          }

          acc = update_in(acc, [:reviews], &[review_data | &1])

          # If user has a review but no status was set, mark as read
          # (they must have read it to review it)
          acc = maybe_add_read_status(acc, user_id, visual_novel_id, review, now)

          acc
        else
          acc
        end
    end
  end

  # Add :read status if no status exists yet for this VN (O(1) lookup using Set)
  # Uses review's added date as date_finished since they must have read it to review it
  defp maybe_add_read_status(acc, user_id, visual_novel_id, review, now) do
    if MapSet.member?(acc.vns_with_status, visual_novel_id) do
      acc
    else
      status_data = %{
        id: UUIDv7.generate(),
        user_id: user_id,
        visual_novel_id: visual_novel_id,
        status: :read,
        date_started: nil,
        date_finished: nil,
        library_added_at: parse_timestamp(review.added) || now,
        note: nil,
        source: "vndb",
        inserted_at: now,
        updated_at: now
      }

      acc
      |> update_in([:reading_statuses], &[status_data | &1])
      |> update_in([:vns_with_status], &MapSet.put(&1, visual_novel_id))
    end
  end

  # ---------------------------------------------------------------------------
  # Database Commit
  # ---------------------------------------------------------------------------

  defp commit_import(acc, user_id, now) do
    Repo.transaction(fn ->
      # 1. Create missing shelves
      VnImportInserter.insert_vn_shelves(user_id, acc.shelf_names, now)
      shelves_count = MapSet.size(acc.shelf_names)
      shelves_map = VnImportInserter.get_vn_shelves_map(user_id)
      shelf_items = VnImportInserter.update_vn_shelf_items(acc.shelf_items, shelves_map, now)

      # 2. Deduplicate (same VN might appear multiple times)
      unique_ratings = Enum.uniq_by(acc.ratings, &{&1.user_id, &1.visual_novel_id})
      unique_statuses = Enum.uniq_by(acc.reading_statuses, &{&1.user_id, &1.visual_novel_id})
      unique_reviews = Enum.uniq_by(acc.reviews, &{&1.user_id, &1.visual_novel_id})

      # 3. Insert ratings (skip VNs user already rated on Kaguya)
      {ratings_count, inserted_ratings} =
        Repo.insert_all(Rating, unique_ratings,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing,
          returning: [:visual_novel_id, :rating]
        )

      # 4. Insert reading statuses (skip VNs user already has in library)
      {statuses_count, _} =
        Repo.insert_all(
          ReadingStatus,
          unique_statuses,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing
        )

      # 5. Insert reviews (skip VNs user already reviewed on Kaguya)
      {reviews_count, inserted_reviews} =
        Repo.insert_all(Review, unique_reviews,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing,
          returning: [:visual_novel_id]
        )

      # 6. Insert shelf items
      Repo.insert_all(ShelfItem, shelf_items, on_conflict: :nothing)

      # 7. Update stats (skip VN rating aggregates for suppressed users)
      suppressed? =
        case Repo.get(Kaguya.Users.User, user_id) do
          %{ratings_suppressed: true} -> true
          _ -> false
        end

      unless suppressed?, do: VnImportStats.update_vn_ratings_count(inserted_ratings)
      VnImportStats.update_vn_reviews_count(inserted_reviews)
      VnImportInserter.update_vn_shelf_counts(user_id)
      VnImportStats.update_user_vn_stats_for_user(user_id)

      # 8. Return summary
      %{
        vns_imported: statuses_count,
        ratings: ratings_count,
        reviews: reviews_count,
        shelves: shelves_count,
        imported_items: sort_imported_items(acc.imported_items),
        missing_vns: acc.missing_vns,
        banned_vns: acc.banned_vns
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_status_from_labels(labels) do
    # Find first status label (1-5)
    labels
    |> Enum.find_value(fn label ->
      Map.get(@status_labels, label.id)
    end)
  end

  defp convert_vndb_vote(nil), do: nil
  defp convert_vndb_vote(""), do: nil

  defp convert_vndb_vote(vote) when is_binary(vote) do
    case Integer.parse(vote) do
      {v, _} when v in 1..10 -> v / 2
      _ -> nil
    end
  end

  # Use vote date as fallback for date_finished when status is :read and no explicit finish date
  defp vote_date_fallback(:read, vn) do
    case parse_timestamp(vn.vote_timestamp) do
      %DateTime{} = dt -> DateTime.to_date(dt)
      _ -> nil
    end
  end

  defp vote_date_fallback(_, _), do: nil

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(""), do: nil

  defp parse_timestamp(ts_str) when is_binary(ts_str) do
    case DateTime.from_iso8601(ts_str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  @max_note_length 280

  defp truncate_note(nil), do: nil
  defp truncate_note(""), do: nil

  defp truncate_note(note) when is_binary(note) do
    if String.length(note) > @max_note_length do
      # Try to break at last sentence end (.!?) if it's in the last ~80 chars
      # Reserve 3 chars for "..." in the search window
      search_window = String.slice(note, 0, @max_note_length - 3)

      sentence_pos =
        Regex.scan(~r/[.!?]\s/u, search_window, return: :index)
        |> List.last()
        |> case do
          [{pos, len}] when pos + len >= @max_note_length - 80 -> pos + len
          _ -> nil
        end

      if sentence_pos do
        trimmed = String.slice(search_window, 0, sentence_pos) |> String.trim_trailing()
        String.trim_trailing(trimmed, ".") <> "..."
      else
        # Fall back to last space to avoid cutting mid-word
        case :binary.match(String.reverse(search_window), " ") do
          {pos, _} -> String.slice(note, 0, @max_note_length - 3 - pos) <> "..."
          :nomatch -> search_window <> "..."
        end
      end
    else
      note
    end
  end

  # Sort imported items: explicit finish dates first (desc), then vote dates (desc), then rest by last_updated
  defp sort_imported_items(items) do
    Enum.sort_by(items, fn item ->
      {priority, date} =
        cond do
          item.date_finished -> {0, item.date_finished}
          item.vote_date -> {1, item.vote_date}
          true -> {2, nil}
        end

      # Negate days for descending date order; nil dates sort last within their priority
      date_sort = if date, do: -Date.to_gregorian_days(date), else: 0
      last_updated_sort = if item.last_updated, do: -DateTime.to_unix(item.last_updated), else: 0

      {priority, date_sort, last_updated_sort}
    end)
  end

  defp log_missing_vns([], _user_id), do: :ok

  defp log_missing_vns(missing_vns, user_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[^\d]/, "")
    dir = "priv/vndb_missing_imports"
    filename = "#{dir}/#{user_id}_#{timestamp}.txt"

    content =
      Enum.map_join(missing_vns, "\n", fn vn -> "#{vn.vndb_url}\t#{vn.title}" end)

    File.mkdir_p!(dir)
    File.write!(filename, content)

    Logger.info("Logged #{length(missing_vns)} missing VNs to #{filename}")
  end
end

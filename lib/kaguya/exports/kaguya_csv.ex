defmodule Kaguya.Exports.KaguyaCsv do
  @moduledoc """
  Kaguya-native CSV export/import for a user's VN library.

  The format is intentionally one row per library VN, similar to Goodreads and
  Hardcover exports, but `VN ID` is Kaguya's `visual_novels.id` and is the
  primary import key.
  """

  import Ecto.Query
  require Logger

  alias Kaguya.Exports.Storage
  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Lists.{ListItem, ListTier}
  alias Kaguya.Lists.List, as: VnList
  alias Kaguya.Shelves.{ReadingStatus, Shelf, ShelfItem}
  alias Kaguya.Uploads.Helpers.{VnImportInserter, VnImportStats}
  alias Kaguya.Users
  alias Kaguya.Users.{User, UserLibraryExport}
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel

  @headers [
    "VN ID",
    "Title",
    "Slug",
    "Status",
    "Date Started",
    "Date Finished",
    "Date Added",
    "Notes",
    "My Rating",
    "Rated At",
    "Shelves",
    "Shelves Added At",
    "My Review",
    "Spoiler",
    "Review Date",
    "Review Edited At"
  ]

  @required_headers @headers
  @shelf_only_vn_id "__kaguya_empty_shelf__"
  @batch_size 1000
  @presign_seconds 60 * 60
  @max_csv_bytes 10_000_000
  @statuses ~w(read did_not_finish on_hold want_to_read currently_reading not_interested)

  @profile_headers [
    "Date Joined",
    "Username",
    "Display Name",
    "Email Address",
    "Bio",
    "Website",
    "Favorite Visual Novels"
  ]

  @ratings_headers ["Date", "Title", "Year", "Kaguya URL", "VN ID", "Rating"]

  @reviews_headers [
    "Date",
    "Title",
    "Year",
    "Kaguya URL",
    "VN ID",
    "Rating",
    "Review",
    "Spoiler"
  ]

  @list_metadata_headers ["Date", "Name", "URL", "Description", "Visibility", "Display Mode"]
  @list_item_headers ["Position", "Title", "Year", "Kaguya URL", "VN ID", "Description"]
  @tier_list_item_headers [
    "Tier",
    "Tier Position",
    "Position",
    "Title",
    "Year",
    "Kaguya URL",
    "VN ID",
    "Description"
  ]

  def headers, do: @headers
  def max_csv_bytes, do: @max_csv_bytes

  def enqueue(user_id) do
    if in_progress?(user_id) do
      {:error, :export_in_progress}
    else
      case Repo.transaction(fn -> create_export_and_job(user_id) end) do
        {:error, %Ecto.Changeset{} = changeset} ->
          if active_export_constraint?(changeset) do
            {:error, :export_in_progress}
          else
            {:error, changeset}
          end

        result ->
          result
      end
    end
  end

  defp create_export_and_job(user_id) do
    with {:ok, %UserLibraryExport{} = export} <-
           Users.create_user_library_export(%{
             user_id: user_id,
             status: :queued
           }),
         {:ok, _job} <- enqueue_job(export) do
      export
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp active_export_constraint?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      to_string(opts[:constraint_name]) == "user_library_exports_one_active_per_user"
    end)
  end

  def presign_download(%UserLibraryExport{object_key: nil}), do: {:error, :not_ready}

  def presign_download(%UserLibraryExport{object_key: key}, filename \\ nil) do
    Storage.presign_get(key, @presign_seconds, filename)
  end

  def download_filename(user, %UserLibraryExport{} = export) do
    "#{download_filename_base(user)}.#{download_extension(export)}"
  end

  def export_to_path(user_id, path) do
    {rows_stream, count} = rows_for_user(user_id)
    write_stream(path, rows_stream)
    {:ok, %{path: path, row_count: count, byte_size: File.stat!(path).size}}
  end

  def export_archive_to_path(user_id, path) do
    tmp_dir = tmp_dir(user_id)

    try do
      File.mkdir_p!(Path.join(tmp_dir, "lists"))

      {library_rows_stream, library_count} = rows_for_user(user_id)
      write_stream(Path.join(tmp_dir, "library.csv"), library_rows_stream)
      profile_count = write_profile_csv(Path.join(tmp_dir, "profile.csv"), user_id)
      ratings_count = write_ratings_csv(Path.join(tmp_dir, "ratings.csv"), user_id)
      reviews_count = write_reviews_csv(Path.join(tmp_dir, "reviews.csv"), user_id)

      file_names = ["profile.csv", "library.csv", "ratings.csv", "reviews.csv"]
      {list_file_names, list_count} = write_list_csv_files(user_id, tmp_dir)
      row_count = library_count + profile_count + ratings_count + reviews_count + list_count

      case create_zip(path, file_names ++ list_file_names, tmp_dir) do
        {:ok, _} ->
          {:ok, %{path: path, row_count: row_count, byte_size: File.stat!(path).size}}

        {:error, reason} ->
          {:error, reason}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  def perform!(%UserLibraryExport{} = export) do
    tmp = tmp_path(export.id)

    try do
      with {:ok, %{row_count: row_count, byte_size: byte_size}} <-
             export_archive_to_path(export.user_id, tmp),
           {:ok, _} <- Storage.upload_export(tmp, export.user_id, export.id),
           {:ok, updated} <-
             Users.update_user_library_export(export, %{
               status: :completed,
               object_key: Storage.export_key(export.user_id, export.id),
               row_count: row_count,
               byte_size: byte_size
             }) do
        {:ok, updated}
      else
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(tmp)
    end
  end

  def import_csv(csv_content, user_id) when is_binary(csv_content) do
    with :ok <- check_size(csv_content),
         {:ok, rows} <- parse_rows(csv_content) do
      do_import(rows, user_id)
    end
  end

  def rows_for_user(user_id) do
    vn_ids = export_vn_ids(user_id)
    empty_shelf_rows = empty_shelf_rows_for_user(user_id)

    vn_stream =
      vn_ids
      |> Stream.chunk_every(@batch_size)
      |> Stream.flat_map(&process_batch(&1, user_id))

    {Stream.concat(vn_stream, empty_shelf_rows), length(vn_ids) + length(empty_shelf_rows)}
  end

  def map_row(row) do
    [
      row.vn_id,
      row.title,
      row.slug,
      row.status,
      row.date_started,
      row.date_finished,
      row.date_added,
      row.notes,
      row.my_rating,
      row.rated_at,
      row.shelves,
      row.shelves_added_at,
      row.review,
      row.spoiler,
      row.review_date,
      row.review_edited_at
    ]
  end

  defp enqueue_job(%UserLibraryExport{id: export_id}) do
    Kaguya.Exports.Workers.KaguyaCsvExportWorker.new(%{export_id: export_id})
    |> Oban.insert()
  end

  defp download_filename_base(%{username: username})
       when is_binary(username) and username != "" do
    "kaguya-#{safe_download_filename_part(username)}-#{download_timestamp()}"
  end

  defp download_filename_base(%{id: id}) when is_binary(id) do
    "kaguya-#{safe_download_filename_part(id)}-#{download_timestamp()}"
  end

  defp download_filename_base(_user), do: "kaguya-library-#{download_timestamp()}"

  defp download_extension(%UserLibraryExport{object_key: object_key}) do
    case Path.extname(object_key || "") do
      ".csv" -> "csv"
      _ -> "zip"
    end
  end

  defp safe_download_filename_part(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "library"
      safe -> safe
    end
  end

  defp download_timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y-%m-%d-%H%M%S")
  end

  defp in_progress?(user_id) do
    Repo.exists?(
      from e in UserLibraryExport,
        where: e.user_id == ^user_id and e.status in [:queued, :processing]
    )
  end

  defp write_stream(path, rows_stream) do
    File.open!(path, [:write, :binary], fn file ->
      IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([@headers]))

      rows_stream
      |> Stream.each(fn row ->
        IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([map_row(row)]))
      end)
      |> Stream.run()
    end)
  end

  defp write_profile_csv(path, user_id) do
    user = Repo.get!(User, user_id)

    favorite_urls =
      user.favorite_visual_novels
      |> List.wrap()
      |> ordered_vns()
      |> Enum.map_join(", ", &vn_url/1)

    write_csv_file(path, @profile_headers, [
      profile_row(user, favorite_urls)
    ])
  end

  defp profile_row(user, favorite_urls) do
    [
      format_date_only(user.inserted_at),
      user.username || "",
      user.display_name || "",
      user.email || "",
      user.bio || "",
      social_website(user.social_links),
      favorite_urls
    ]
  end

  defp write_ratings_csv(path, user_id) do
    query =
      from r in Rating,
        join: vn in assoc(r, :visual_novel),
        where: r.user_id == ^user_id,
        order_by: [asc: r.updated_at, asc: vn.title],
        select: %{
          date: r.updated_at,
          title: vn.title,
          release_date: vn.release_date,
          slug: vn.slug,
          vn_id: vn.id,
          rating: r.rating
        }

    {:ok, count} = stream_query_to_csv(path, @ratings_headers, query, &rating_export_row/1)
    count
  end

  defp rating_export_row(row) do
    [
      format_date_only(row.date),
      row.title || "",
      release_year(row.release_date),
      vn_url(row),
      row.vn_id,
      format_rating(row.rating)
    ]
  end

  defp write_reviews_csv(path, user_id) do
    query =
      from r in Review,
        join: vn in assoc(r, :visual_novel),
        left_join: rating in Rating,
        on: rating.user_id == r.user_id and rating.visual_novel_id == r.visual_novel_id,
        where: r.user_id == ^user_id and is_nil(r.hidden_at) and r.is_locked == false,
        order_by: [asc: r.inserted_at, asc: vn.title],
        select: %{
          date: r.inserted_at,
          title: vn.title,
          release_date: vn.release_date,
          slug: vn.slug,
          vn_id: vn.id,
          rating: rating.rating,
          review: r.content,
          spoiler: r.is_spoiler
        }

    {:ok, count} = stream_query_to_csv(path, @reviews_headers, query, &review_export_row/1)
    count
  end

  defp review_export_row(row) do
    [
      format_date_only(row.date),
      row.title || "",
      release_year(row.release_date),
      vn_url(row),
      row.vn_id,
      format_rating(row.rating),
      row.review || "",
      bool_value(row.spoiler)
    ]
  end

  defp write_list_csv_files(user_id, tmp_dir) do
    lists =
      Repo.all(
        from l in VnList,
          where: l.user_id == ^user_id and is_nil(l.hidden_at),
          order_by: [asc: l.inserted_at, asc: l.name]
      )

    lists
    |> Enum.reduce({[], 0, %{}}, fn list, {filenames, count, filename_counts} ->
      {basename, filename_counts} = unique_list_filename(list, filename_counts)
      filename = "lists/#{basename}.csv"
      list_count = write_list_csv(Path.join(tmp_dir, filename), list)
      {[filename | filenames], count + list_count, filename_counts}
    end)
    |> then(fn {filenames, count, _filename_counts} -> {Enum.reverse(filenames), count} end)
  end

  defp create_zip(path, file_names, cwd) do
    :zip.create(
      String.to_charlist(path),
      Enum.map(file_names, &String.to_charlist/1),
      cwd: String.to_charlist(cwd)
    )
  end

  defp write_list_csv(path, %VnList{} = list) do
    tiers = load_list_tiers(list.id)
    tier_by_id = Map.new(tiers, &{&1.id, &1})

    {banner, item_headers, row_mapper} =
      if list.display_mode == "tier" do
        {
          "Kaguya tier list export v1\n",
          @tier_list_item_headers,
          &tier_list_item_row(&1, tier_by_id)
        }
      else
        {
          "Kaguya list export v1\n",
          @list_item_headers,
          &list_item_row/1
        }
      end

    File.open!(path, [:write, :binary], fn file ->
      IO.binwrite(file, banner)
      write_csv_rows(file, @list_metadata_headers, [list_metadata_row(list)])
      IO.binwrite(file, "\n")

      {:ok, item_count} =
        Repo.transaction(
          fn ->
            list_items_stream(list.id)
            |> write_csv_stream(file, item_headers, row_mapper)
          end,
          timeout: :infinity
        )

      1 + item_count
    end)
  end

  defp load_list_tiers(list_id) do
    Repo.all(from t in ListTier, where: t.list_id == ^list_id, order_by: [asc: t.position])
  end

  defp list_items_stream(list_id) do
    query =
      from item in ListItem,
        join: vn in assoc(item, :visual_novel),
        where: item.list_id == ^list_id,
        order_by: [asc: item.position, asc: item.tier_position],
        select: %{
          position: item.position,
          tier_id: item.tier_id,
          tier_position: item.tier_position,
          title: vn.title,
          release_date: vn.release_date,
          slug: vn.slug,
          vn_id: vn.id
        }

    Repo.stream(query)
  end

  defp list_metadata_row(list) do
    [
      format_date_only(list.inserted_at),
      list.name || "",
      list_url(list),
      list.description || "",
      if(list.is_public, do: "Public", else: "Private"),
      display_mode(list.display_mode)
    ]
  end

  defp list_item_row(item) do
    [
      item.position,
      item.title || "",
      release_year(item.release_date),
      vn_url(item),
      item.vn_id,
      ""
    ]
  end

  defp tier_list_item_row(item, tier_by_id) do
    tier = Map.get(tier_by_id, item.tier_id)

    [
      (tier && tier.label) || "",
      item.tier_position || "",
      item.position,
      item.title || "",
      release_year(item.release_date),
      vn_url(item),
      item.vn_id,
      ""
    ]
  end

  defp write_csv_file(path, headers, rows) do
    File.open!(path, [:write, :binary], fn file ->
      write_csv_rows(file, headers, rows)
    end)
  end

  defp stream_query_to_csv(path, headers, query, row_mapper) do
    Repo.transaction(
      fn ->
        File.open!(path, [:write, :binary], fn file ->
          query
          |> Repo.stream()
          |> write_csv_stream(file, headers, row_mapper)
        end)
      end,
      timeout: :infinity
    )
  end

  defp write_csv_stream(stream, file, headers, row_mapper) do
    IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([headers]))

    Enum.reduce(stream, 0, fn row, count ->
      IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([row_mapper.(row)]))
      count + 1
    end)
  end

  defp write_csv_rows(file, headers, rows) do
    IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([headers]))

    Enum.each(rows, fn row ->
      IO.binwrite(file, NimbleCSV.RFC4180.dump_to_iodata([row]))
    end)

    length(rows)
  end

  defp export_vn_ids(user_id) do
    status_ids =
      Repo.all(
        from rs in ReadingStatus, where: rs.user_id == ^user_id, select: rs.visual_novel_id
      )

    rating_ids =
      Repo.all(from r in Rating, where: r.user_id == ^user_id, select: r.visual_novel_id)

    review_ids =
      Repo.all(
        from r in Review,
          where: r.user_id == ^user_id and is_nil(r.hidden_at) and r.is_locked == false,
          select: r.visual_novel_id
      )

    shelf_item_ids =
      Repo.all(
        from s in Shelf,
          join: si in ShelfItem,
          on: si.shelf_id == s.id,
          where: s.user_id == ^user_id,
          select: si.visual_novel_id
      )

    [status_ids, rating_ids, review_ids, shelf_item_ids]
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp process_batch(vn_ids, user_id) do
    vns = load_vns(vn_ids)
    statuses = load_statuses(user_id, vn_ids)
    ratings = load_ratings(user_id, vn_ids)
    reviews = load_reviews(user_id, vn_ids)
    shelves = load_shelves(user_id, vn_ids)

    vn_ids
    |> Enum.map(fn vn_id ->
      vn = Map.get(vns, vn_id)
      if vn, do: build_row(Map.get(statuses, vn_id), vn, ratings, reviews, shelves)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_row(status, vn, ratings, reviews, shelves) do
    shelf_entries = Map.get(shelves, vn.id, [])
    rating = Map.get(ratings, vn.id)
    review = Map.get(reviews, vn.id)

    %{
      vn_id: vn.id,
      title: vn.title || "",
      slug: vn.slug || "",
      status: status_value(status),
      date_started: format_date(status && status.date_started),
      date_finished: format_date(status && status.date_finished),
      date_added: format_datetime(status && status.library_added_at),
      notes: (status && status.note) || "",
      my_rating: format_rating(rating && rating.rating),
      rated_at: format_datetime(rating && rating.updated_at),
      shelves: encode_list(Enum.map(shelf_entries, & &1.name)),
      shelves_added_at: encode_list(Enum.map(shelf_entries, &format_datetime(&1.added_at))),
      review: (review && review.content) || "",
      spoiler: if(review && review.is_spoiler, do: "true", else: "false"),
      review_date: format_datetime(review && review.inserted_at),
      review_edited_at: review_edited_at(review)
    }
  end

  defp load_vns(vn_ids) do
    Repo.all(
      from vn in VisualNovel,
        where: vn.id in ^vn_ids,
        select: %{id: vn.id, title: vn.title, slug: vn.slug}
    )
    |> Map.new(&{&1.id, &1})
  end

  defp load_statuses(user_id, vn_ids) do
    Repo.all(
      from rs in ReadingStatus, where: rs.user_id == ^user_id and rs.visual_novel_id in ^vn_ids
    )
    |> Map.new(&{&1.visual_novel_id, &1})
  end

  defp load_ratings(user_id, vn_ids) do
    Repo.all(from r in Rating, where: r.user_id == ^user_id and r.visual_novel_id in ^vn_ids)
    |> Map.new(&{&1.visual_novel_id, &1})
  end

  defp load_reviews(user_id, vn_ids) do
    Repo.all(
      from r in Review,
        where:
          r.user_id == ^user_id and r.visual_novel_id in ^vn_ids and is_nil(r.hidden_at) and
            r.is_locked == false
    )
    |> Map.new(&{&1.visual_novel_id, &1})
  end

  defp load_shelves(user_id, vn_ids) do
    Repo.all(
      from s in Shelf,
        join: si in ShelfItem,
        on: si.shelf_id == s.id,
        where: s.user_id == ^user_id and si.visual_novel_id in ^vn_ids,
        order_by: [asc: s.name],
        select: {si.visual_novel_id, %{name: s.name, added_at: si.inserted_at}}
    )
    |> Enum.group_by(fn {vn_id, _} -> vn_id end, fn {_, shelf} -> shelf end)
  end

  defp empty_shelf_rows_for_user(user_id) do
    Repo.all(
      from s in Shelf,
        left_join: si in ShelfItem,
        on: si.shelf_id == s.id,
        where: s.user_id == ^user_id and is_nil(si.visual_novel_id),
        order_by: [asc: s.name],
        select: %{name: s.name, inserted_at: s.inserted_at}
    )
    |> Enum.map(fn shelf ->
      %{
        vn_id: @shelf_only_vn_id,
        title: "Kaguya Shelf",
        slug: "",
        status: "",
        date_started: "",
        date_finished: "",
        date_added: "",
        notes: "",
        my_rating: "",
        rated_at: "",
        shelves: encode_list([shelf.name]),
        shelves_added_at: encode_list([format_datetime(shelf.inserted_at)]),
        review: "",
        spoiler: "false",
        review_date: "",
        review_edited_at: ""
      }
    end)
  end

  defp check_size(csv_content) do
    if byte_size(csv_content) > @max_csv_bytes do
      {:error, "CSV file exceeds the 10 MB limit"}
    else
      :ok
    end
  end

  defp parse_rows(csv_content) do
    case NimbleCSV.RFC4180.parse_string(csv_content, skip_headers: false) do
      [] ->
        {:error, "CSV is empty"}

      [headers | data_rows] ->
        headers = Enum.map(headers, &String.trim/1)

        with :ok <- validate_headers(headers),
             {:ok, rows} <- validate_and_map_rows(headers, data_rows),
             :ok <- validate_unique_vn_ids(rows) do
          {:ok, rows}
        end
    end
  rescue
    e -> {:error, "Failed to parse CSV: #{Exception.message(e)}"}
  end

  defp validate_headers(headers) do
    missing = Enum.reject(@required_headers, &(&1 in headers))

    cond do
      missing != [] ->
        {:error, "CSV is missing required columns: #{Enum.join(missing, ", ")}"}

      duplicate_headers(headers) != [] ->
        {:error, "CSV contains duplicate columns: #{Enum.join(duplicate_headers(headers), ", ")}"}

      true ->
        :ok
    end
  end

  defp validate_and_map_rows(headers, data_rows) do
    case Enum.find(Enum.with_index(data_rows, 2), fn {row, _line} ->
           length(row) != length(headers)
         end) do
      nil ->
        {:ok,
         data_rows
         |> Enum.with_index(2)
         |> Enum.map(fn {row, line} -> row_to_map(headers, row, line) end)}

      {row, line} ->
        {:error, "CSV row #{line} has #{length(row)} columns; expected #{length(headers)}"}
    end
  end

  defp validate_unique_vn_ids(rows) do
    duplicate_ids =
      rows
      |> Enum.map(&(Map.get(&1, "VN ID", "") |> String.trim()))
      |> Enum.reject(&(&1 in ["", @shelf_only_vn_id]))
      |> duplicate_values()

    if duplicate_ids == [] do
      :ok
    else
      {:error, "CSV contains duplicate VN IDs: #{Enum.join(duplicate_ids, ", ")}"}
    end
  end

  defp duplicate_headers(headers), do: duplicate_values(headers)

  defp duplicate_values(values) do
    values
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn value, {seen, duplicates} ->
      if MapSet.member?(seen, value) do
        {seen, MapSet.put(duplicates, value)}
      else
        {MapSet.put(seen, value), duplicates}
      end
    end)
    |> elem(1)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp row_to_map(headers, row, line) do
    headers
    |> Enum.zip(row)
    |> Map.new(fn {k, v} -> {k, v || ""} end)
    |> Map.put(:__line__, line)
  end

  defp do_import(rows, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    vn_map = load_import_vns(rows)

    parsed_rows = Enum.map(rows, &parse_import_row(&1, vn_map, now))

    invalid =
      Enum.filter(parsed_rows, &match?({:invalid, _line, _errors}, &1))
      |> Enum.map(fn {:invalid, line, errors} -> {line, errors} end)

    if invalid != [] do
      {:error, format_import_errors(invalid)}
    else
      import_valid_rows(rows, parsed_rows, user_id, now)
    end
  end

  defp import_valid_rows(rows, parsed_rows, user_id, now) do
    missing =
      Enum.filter(parsed_rows, &match?({:missing, _}, &1))
      |> Enum.map(fn {:missing, row} -> row end)

    valid =
      Enum.flat_map(parsed_rows, fn
        {:ok, row} -> [row]
        _ -> []
      end)

    Repo.transaction(fn ->
      shelf_names = valid |> Enum.flat_map(& &1.shelves) |> MapSet.new()
      shelves_created = VnImportInserter.insert_vn_shelves(user_id, shelf_names, now)
      shelves_map = VnImportInserter.get_vn_shelves_map(user_id)

      statuses = Enum.flat_map(valid, &status_row(&1, user_id, now))
      ratings = valid |> Enum.flat_map(&rating_row(&1, user_id, now))
      reviews = valid |> Enum.flat_map(&review_row(&1, user_id, now))
      shelf_items = Enum.flat_map(valid, &shelf_item_rows(&1, shelves_map, now))

      {status_count, _} =
        Repo.insert_all(ReadingStatus, statuses,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing
        )

      {rating_count, inserted_ratings} =
        Repo.insert_all(Rating, ratings,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing,
          returning: [:visual_novel_id, :rating]
        )

      {review_count, inserted_reviews} =
        Repo.insert_all(Review, reviews,
          conflict_target: [:user_id, :visual_novel_id],
          on_conflict: :nothing,
          returning: [:visual_novel_id]
        )

      {shelf_item_count, _} = Repo.insert_all(ShelfItem, shelf_items, on_conflict: :nothing)

      unless Kaguya.Users.ratings_suppressed?(user_id),
        do: VnImportStats.update_vn_ratings_count(inserted_ratings)

      VnImportStats.update_vn_reviews_count(inserted_reviews)
      VnImportInserter.update_vn_shelf_counts(user_id)
      VnImportStats.update_user_vn_stats_for_user(user_id)

      %{
        rows: length(rows),
        vns_imported: status_count,
        ratings: rating_count,
        reviews: review_count,
        shelves: shelves_created,
        shelf_items: shelf_item_count,
        imported_items: imported_items(valid),
        missing_vns: missing
      }
    end)
  end

  defp format_import_errors(errors) do
    detail =
      errors
      |> Enum.take(5)
      |> Enum.map_join("; ", fn {line, row_errors} ->
        "row #{line}: #{Enum.join(row_errors, ", ")}"
      end)

    suffix = if length(errors) > 5, do: "; and #{length(errors) - 5} more", else: ""

    "CSV contains invalid values: #{detail}#{suffix}"
  end

  defp imported_items(rows) do
    rows = Enum.reject(rows, &(&1.shelf_only? or is_nil(&1.status)))
    vn_ids = rows |> Enum.map(& &1.vn_id) |> Enum.uniq()
    details = load_import_item_details(vn_ids)

    rows
    |> Enum.uniq_by(& &1.vn_id)
    |> Enum.map(fn row ->
      detail = Map.get(details, row.vn_id, %{})

      cover_needs_blur = VisualNovels.cover_nsfw?(detail)

      %{
        id: row.vn_id,
        title: detail[:title] || row.title,
        slug: detail[:slug],
        images: VisualNovels.build_image_urls(detail),
        cover_needs_blur: cover_needs_blur,
        has_ero: cover_needs_blur,
        rating: row.rating,
        status: row.status,
        release_date: detail[:release_date],
        date_added: row.date_added,
        date_started: row.date_started,
        date_finished: row.date_finished,
        vote_date: row.rated_at && DateTime.to_date(row.rated_at),
        last_updated: row.review_edited_at || row.review_date || row.rated_at || row.date_added
      }
    end)
    |> sort_imported_items()
  end

  defp load_import_item_details([]), do: %{}

  defp load_import_item_details(vn_ids) do
    Repo.all(
      from v in VisualNovel,
        where: v.id in ^vn_ids,
        select:
          {v.id,
           %{
             slug: v.slug,
             title: v.title,
             primary_image_id: v.primary_image_id,
             temp_image_url: v.temp_image_url,
             release_date: v.release_date,
             is_image_nsfw: v.is_image_nsfw,
             is_image_suggestive: v.is_image_suggestive
           }}
    )
    |> Map.new()
  end

  defp sort_imported_items(items) do
    Enum.sort_by(items, fn item ->
      {priority, date} =
        cond do
          item.date_finished -> {0, item.date_finished}
          item.vote_date -> {1, item.vote_date}
          true -> {2, nil}
        end

      date_sort = if date, do: -Date.to_gregorian_days(date), else: 0
      last_updated_sort = if item.last_updated, do: -DateTime.to_unix(item.last_updated), else: 0

      {priority, date_sort, last_updated_sort}
    end)
  end

  defp load_import_vns(rows) do
    ids =
      rows
      |> Enum.map(&(Map.get(&1, "VN ID", "") |> String.trim()))
      |> Enum.reject(&(&1 in ["", @shelf_only_vn_id]))
      |> Enum.uniq()

    Repo.all(from vn in VisualNovel, where: vn.id in ^ids, select: {vn.id, vn})
    |> Map.new()
  end

  defp parse_import_row(row, vn_map, now) do
    vn_id = row |> Map.get("VN ID", "") |> String.trim()

    cond do
      vn_id == @shelf_only_vn_id ->
        parse_shelf_only_row(row, now)

      vn_id == "" ->
        {:invalid, Map.get(row, :__line__), ["VN ID is required"]}

      true ->
        parse_vn_row(row, vn_map, vn_id, now)
    end
  end

  defp parse_vn_row(row, vn_map, vn_id, now) do
    case Map.get(vn_map, vn_id) do
      nil ->
        {:missing,
         %{vn_id: vn_id, title: Map.get(row, "Title", ""), slug: Map.get(row, "Slug", "")}}

      %VisualNovel{} = vn ->
        with {:ok, parsed} <- parse_row_fields(row, now) do
          {:ok, Map.merge(parsed, %{vn_id: vn.id, title: vn.title, shelf_only?: false})}
        end
    end
  end

  defp parse_shelf_only_row(row, now) do
    case parse_row_fields(row, now) do
      {:ok, %{shelves: []}} ->
        {:invalid, Map.get(row, :__line__), ["Shelves is required for shelf-only rows"]}

      {:ok, parsed} ->
        if shelf_only_row_empty?(parsed) do
          {:ok, Map.merge(parsed, %{vn_id: nil, title: nil, shelf_only?: true})}
        else
          {:invalid, Map.get(row, :__line__), ["shelf-only rows cannot contain VN data"]}
        end

      {:invalid, _line, _errors} = invalid ->
        invalid
    end
  end

  defp parse_row_fields(row, now) do
    parsed = %{
      status: parse_status(Map.get(row, "Status")),
      date_started: parse_date(Map.get(row, "Date Started")),
      date_finished: parse_date(Map.get(row, "Date Finished")),
      date_added: parse_datetime(Map.get(row, "Date Added")),
      notes: blank_to_nil(Map.get(row, "Notes")),
      rating: parse_rating(Map.get(row, "My Rating")),
      rated_at: parse_datetime(Map.get(row, "Rated At")),
      shelves: parse_list(Map.get(row, "Shelves")),
      shelves_added_at: parse_datetime_list(Map.get(row, "Shelves Added At")),
      review: blank_to_nil(Map.get(row, "My Review")),
      spoiler: parse_bool(Map.get(row, "Spoiler")),
      review_date: parse_datetime(Map.get(row, "Review Date")),
      review_edited_at: parse_datetime(Map.get(row, "Review Edited At"))
    }

    errors = validation_errors(parsed)

    if errors == [] do
      {:ok,
       parsed
       |> Map.update!(:date_added, &(&1 || now))
       |> Map.update!(:rated_at, &(&1 || now))
       |> Map.update!(:review_date, &(&1 || now))
       |> unwrap_parsed_values()}
    else
      {:invalid, Map.get(row, :__line__), errors}
    end
  end

  defp validation_errors(parsed) do
    field_errors =
      parsed
      |> Enum.flat_map(fn
        {_field, {:invalid, message}} -> [message]
        {_field, _value} -> []
      end)

    shelf_errors =
      with %{shelves: shelves, shelves_added_at: {:ok, shelf_dates}} <- parsed,
           true <- shelves != [] or shelf_dates != [],
           false <- shelf_dates == [] or length(shelves) == length(shelf_dates) do
        ["Shelves Added At must be blank or have one value per shelf"]
      else
        _ -> []
      end

    field_errors ++ shelf_errors
  end

  defp unwrap_parsed_values(parsed) do
    Map.new(parsed, fn
      {key, {:ok, value}} -> {key, value}
      {key, value} -> {key, value}
    end)
  end

  defp shelf_only_row_empty?(row) do
    is_nil(row.status) and is_nil(row.date_started) and is_nil(row.date_finished) and
      is_nil(row.notes) and is_nil(row.rating) and is_nil(row.review) and row.spoiler == false
  end

  defp status_row(%{status: nil}, _user_id, _now), do: []

  defp status_row(row, user_id, now) do
    [
      %{
        id: UUIDv7.generate(),
        user_id: user_id,
        visual_novel_id: row.vn_id,
        status: row.status,
        date_started: row.date_started,
        date_finished: row.date_finished,
        library_added_at: row.date_added,
        note: row.notes,
        source: "kaguya_csv",
        inserted_at: now,
        updated_at: now
      }
    ]
  end

  defp rating_row(%{rating: nil}, _user_id, _now), do: []

  defp rating_row(row, user_id, _now) do
    [
      %{
        id: UUIDv7.generate(),
        user_id: user_id,
        visual_novel_id: row.vn_id,
        rating: row.rating,
        source: "kaguya_csv",
        inserted_at: row.rated_at,
        updated_at: row.rated_at
      }
    ]
  end

  defp review_row(%{review: nil}, _user_id, _now), do: []

  defp review_row(row, user_id, _now) do
    edited_at = row.review_edited_at || row.review_date

    [
      %{
        id: UUIDv7.generate(),
        user_id: user_id,
        visual_novel_id: row.vn_id,
        content: row.review,
        is_spoiler: row.spoiler,
        is_edited: not is_nil(row.review_edited_at),
        source: "kaguya_csv",
        likes_count: 0,
        trending_score: 0.0,
        comments_count: 0,
        inserted_at: row.review_date,
        updated_at: edited_at
      }
    ]
  end

  defp shelf_item_rows(%{shelf_only?: true}, _shelves_map, _now), do: []

  defp shelf_item_rows(row, shelves_map, now) do
    row.shelves
    |> Enum.with_index()
    |> Enum.map(fn {shelf_name, index} ->
      added_at = Enum.at(row.shelves_added_at, index) || now

      %{
        shelf_id: Map.fetch!(shelves_map, shelf_name),
        visual_novel_id: row.vn_id,
        inserted_at: added_at,
        updated_at: added_at
      }
    end)
  end

  defp parse_status(nil), do: nil
  defp parse_status(""), do: nil

  defp parse_status(status) do
    status = String.trim(status)

    if status in @statuses do
      String.to_existing_atom(status)
    else
      {:invalid, "Status must be one of: #{Enum.join(@statuses, ", ")}"}
    end
  end

  defp status_value(nil), do: ""
  defp status_value(status), do: to_string(status.status)

  defp parse_rating(nil), do: nil
  defp parse_rating(""), do: nil

  defp parse_rating(value) do
    case Float.parse(String.trim(value)) do
      {rating, ""} when rating in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0] ->
        rating

      _ ->
        {:invalid, "My Rating must be blank or a half-star value from 0.5 to 5.0"}
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      _ -> {:invalid, "dates must use YYYY-MM-DD"}
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> {:invalid, "datetimes must be ISO 8601 values"}
    end
  end

  defp parse_datetime_list(value) do
    values = parse_list(value)

    parsed = Enum.map(values, &parse_datetime/1)

    case Enum.find(parsed, &match?({:invalid, _}, &1)) do
      nil -> {:ok, parsed}
      {:invalid, _} -> {:invalid, "Shelves Added At contains an invalid datetime"}
    end
  end

  defp parse_bool(nil), do: false
  defp parse_bool(""), do: false

  defp parse_bool(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      value when value in ["true", "1", "yes"] -> true
      value when value in ["false", "0", "no"] -> false
      _ -> {:invalid, "Spoiler must be true or false"}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp review_edited_at(nil), do: ""

  defp review_edited_at(%{is_edited: true, updated_at: updated_at}),
    do: format_datetime(updated_at)

  defp review_edited_at(_), do: ""

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(DateTime.truncate(dt, :second))

  defp format_datetime(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> format_datetime()

  defp format_date_only(nil), do: ""
  defp format_date_only(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date_only(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp format_date_only(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> format_date_only()

  defp release_year(nil), do: ""
  defp release_year(%Date{year: year}), do: year
  defp release_year(value) when is_binary(value), do: String.slice(value, 0, 4)

  defp vn_url(%{slug: nil}), do: ""
  defp vn_url(%{slug: ""}), do: ""
  defp vn_url(%{slug: slug}), do: frontend_url() <> "/vn/" <> slug

  defp list_url(%{slug: nil}), do: ""
  defp list_url(%{slug: ""}), do: ""
  defp list_url(%{slug: slug}), do: frontend_url() <> "/lists/" <> slug

  defp frontend_url do
    :kaguya
    |> Application.get_env(:frontend_url, "https://kaguya.io")
    |> String.trim_trailing("/")
  end

  defp display_mode("tier"), do: "Tier"
  defp display_mode("grid"), do: "Grid"
  defp display_mode(value), do: value || ""

  defp bool_value(true), do: "true"
  defp bool_value(_), do: "false"

  defp unique_list_filename(list, filename_counts) do
    basename = list_filename(list)
    count = Map.get(filename_counts, basename, 0)

    filename = if count == 0, do: basename, else: "#{basename}-#{count + 1}"
    {filename, Map.put(filename_counts, basename, count + 1)}
  end

  defp list_filename(list) do
    base =
      (list.name || list.slug || "list")
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/, "-")
      |> String.trim("-")

    if base == "", do: "list", else: base
  end

  defp social_website(nil), do: ""
  defp social_website(%{website: website}), do: website || ""
  defp social_website(%{"website" => website}), do: website || ""
  defp social_website(_), do: ""

  defp ordered_vns([]), do: []

  defp ordered_vns(vn_ids) do
    vn_map = load_vns(vn_ids)

    vn_ids
    |> Enum.map(&Map.get(vn_map, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp format_rating(nil), do: ""

  defp format_rating(rating) when is_float(rating),
    do: :erlang.float_to_binary(rating, [:compact, decimals: 1])

  defp format_rating(rating), do: to_string(rating)

  defp encode_list(values), do: Enum.map_join(values, "|", &escape_list_value/1)
  defp parse_list(nil), do: []
  defp parse_list(""), do: []
  defp parse_list(value), do: split_escaped(value)

  defp escape_list_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\|")
  end

  defp split_escaped(value) do
    {parts, current, escaped?} =
      value
      |> String.graphemes()
      |> Enum.reduce({[], "", false}, fn
        char, {parts, current, true} -> {parts, current <> char, false}
        "\\", {parts, current, false} -> {parts, current, true}
        "|", {parts, current, false} -> {[current | parts], "", false}
        char, {parts, current, false} -> {parts, current <> char, false}
      end)

    final = if escaped?, do: current <> "\\", else: current

    [final | parts]
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp tmp_path(export_id),
    do: Path.join(System.tmp_dir!(), "kaguya_library_export_#{export_id}.zip")

  defp tmp_dir(user_id),
    do: Path.join(System.tmp_dir!(), "kaguya_library_export_#{user_id}_#{UUIDv7.generate()}")
end

defmodule Kaguya.Exports.KaguyaCsvTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Exports.KaguyaCsv
  alias Kaguya.Lists.{ListItem, ListTier}
  alias Kaguya.Lists.List, as: VnList
  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Shelves.{ReadingStatus, Shelf, ShelfItem}
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "exports and imports the user library without losing modeled library data" do
    user = insert_user!()
    vn = insert_vn!("Round Trip VN")

    added_at = ~U[2025-01-02 03:04:05Z]
    rated_at = ~U[2025-01-03 03:04:05Z]
    review_at = ~U[2025-01-04 03:04:05Z]
    review_edited_at = ~U[2025-01-05 03:04:05Z]
    shelf_added_at = ~U[2025-01-06 03:04:05Z]

    insert_status!(user, vn, added_at)
    insert_rating!(user, vn, 4.5, rated_at)
    insert_review!(user, vn, review_at, review_edited_at)
    insert_shelf!(user, vn, "Favorites|Odd", shelf_added_at)

    path = Path.join(System.tmp_dir!(), "kaguya_csv_test_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    refute csv =~ "Export Version"
    assert csv =~ "VN ID"
    assert csv =~ "Favorites\\|Odd"
    assert csv =~ "This review has ||inline spoiler|| text"

    assert {:ok, true} = Users.reset_library(user.id)

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.vns_imported == 1
    assert result.ratings == 1
    assert result.reviews == 1
    assert result.shelves == 1
    assert result.shelf_items == 1
    assert length(result.imported_items) == 1
    assert hd(result.imported_items).title == vn.title

    status = Repo.get_by!(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)
    assert status.status == :read
    assert status.date_started == ~D[2024-12-31]
    assert status.date_finished == ~D[2025-01-01]
    assert status.library_added_at == added_at
    assert status.note == "play after fandisc"

    rating = Repo.get_by!(Rating, user_id: user.id, visual_novel_id: vn.id)
    assert rating.rating == 4.5
    assert rating.updated_at == rated_at

    review = Repo.get_by!(Review, user_id: user.id, visual_novel_id: vn.id)
    assert review.content == "This review has ||inline spoiler|| text and enough content."
    assert review.is_spoiler == true
    assert review.is_edited == true
    assert review.inserted_at == review_at
    assert review.updated_at == review_edited_at

    shelf = Repo.get_by!(Shelf, user_id: user.id, name: "Favorites|Odd")
    shelf_item = Repo.get_by!(ShelfItem, shelf_id: shelf.id, visual_novel_id: vn.id)
    assert shelf_item.inserted_at == shelf_added_at

    File.rm(path)
  end

  test "exports a Letterboxd-style ZIP of CSV files" do
    user = insert_user!()
    vn = insert_vn!("Archive VN")
    tier_vn = insert_vn!("Tier Archive VN")

    now = ~U[2025-02-01 03:04:05Z]
    insert_status!(user, vn, now)
    insert_rating!(user, vn, 4.0, now)
    insert_review!(user, vn, now, now)
    insert_list!(user, "Normal Picks", "grid", [vn], now)
    insert_tier_list!(user, "Tier Picks", [{"S", tier_vn}], now)

    user
    |> Ecto.Changeset.change(favorite_visual_novels: [tier_vn.id, vn.id])
    |> Repo.update!()

    path = Path.join(System.tmp_dir!(), "kaguya_archive_test_#{UUIDv7.generate()}.zip")
    assert {:ok, %{row_count: 8}} = KaguyaCsv.export_archive_to_path(user.id, path)

    {:ok, files} = :zip.extract(String.to_charlist(path), [:memory])
    archive = Map.new(files, fn {name, content} -> {to_string(name), content} end)

    assert Map.has_key?(archive, "profile.csv")
    assert Map.has_key?(archive, "library.csv")
    assert Map.has_key?(archive, "ratings.csv")
    assert Map.has_key?(archive, "reviews.csv")

    list_files = archive |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "lists/"))
    assert length(list_files) == 2
    assert "lists/normal-picks.csv" in list_files
    assert "lists/tier-picks.csv" in list_files

    assert archive["profile.csv"] =~ "Favorite Visual Novels"
    assert archive["profile.csv"] =~ "/vn/#{vn.slug}"

    assert String.contains?(
             archive["profile.csv"],
             "http://localhost:3000/vn/#{tier_vn.slug}, http://localhost:3000/vn/#{vn.slug}"
           )

    assert archive["library.csv"] =~ "VN ID"
    assert archive["ratings.csv"] =~ "Date,Title,Year,Kaguya URL,VN ID,Rating"
    assert archive["reviews.csv"] =~ "Date,Title,Year,Kaguya URL,VN ID,Rating,Review,Spoiler"

    assert Enum.any?(list_files, fn file ->
             archive[file] =~ "Kaguya list export v1" and
               archive[file] =~ "Position,Title,Year,Kaguya URL,VN ID,Description"
           end)

    assert Enum.any?(list_files, fn file ->
             archive[file] =~ "Kaguya tier list export v1" and
               archive[file] =~
                 "Tier,Tier Position,Position,Title,Year,Kaguya URL,VN ID,Description"
           end)

    File.rm(path)
  end

  test "reports rows whose VN ID no longer exists" do
    user = insert_user!()

    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        KaguyaCsv.headers(),
        [
          UUIDv7.generate(),
          "Missing",
          "missing",
          "read",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "false",
          "",
          ""
        ]
      ])
      |> IO.iodata_to_binary()

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.vns_imported == 0
    assert [%{title: "Missing", slug: "missing"}] = result.missing_vns
  end

  test "exports ratings and reviews even when a reading status is absent" do
    user = insert_user!()
    vn = insert_vn!("Reviewed Only VN")

    rated_at = ~U[2025-02-03 03:04:05Z]
    review_at = ~U[2025-02-04 03:04:05Z]

    insert_rating!(user, vn, 3.5, rated_at)
    insert_review!(user, vn, review_at, review_at)

    path = Path.join(System.tmp_dir!(), "kaguya_csv_review_only_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    assert {:ok, true} = Users.reset_library(user.id)

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.vns_imported == 0
    assert result.ratings == 1
    assert result.reviews == 1
    assert result.imported_items == []

    refute Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)
    assert Repo.get_by!(Rating, user_id: user.id, visual_novel_id: vn.id).rating == 3.5

    assert Repo.get_by!(Review, user_id: user.id, visual_novel_id: vn.id).content =~
             "inline spoiler"

    File.rm(path)
  end

  test "exports and imports empty shelves removed by reset_library" do
    user = insert_user!()
    inserted_at = ~U[2025-03-04 05:06:07Z]
    insert_empty_shelf!(user, "Empty Backlog", inserted_at)

    path = Path.join(System.tmp_dir!(), "kaguya_csv_empty_shelf_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    assert csv =~ "Empty Backlog"

    assert {:ok, true} = Users.reset_library(user.id)
    refute Repo.get_by(Shelf, user_id: user.id, name: "Empty Backlog")

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.vns_imported == 0
    assert result.shelves == 1
    assert result.shelf_items == 0

    shelf = Repo.get_by!(Shelf, user_id: user.id, name: "Empty Backlog")
    assert shelf.vns_count == 0

    File.rm(path)
  end

  test "imports hidden VNs that were present in a Kaguya export" do
    user = insert_user!()
    vn = insert_vn!("Hidden Restore VN")
    hidden_at = ~U[2025-04-01 00:00:00Z]

    insert_status!(user, vn, ~U[2025-04-02 00:00:00Z])

    path = Path.join(System.tmp_dir!(), "kaguya_csv_hidden_vn_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)
    csv = File.read!(path)

    vn
    |> Ecto.Changeset.change(hidden_at: hidden_at)
    |> Repo.update!()

    assert {:ok, true} = Users.reset_library(user.id)

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.vns_imported == 1
    assert result.missing_vns == []
    assert Repo.get_by!(ReadingStatus, user_id: user.id, visual_novel_id: vn.id).status == :read

    File.rm(path)
  end

  test "does not export hidden review text as importable user data" do
    user = insert_user!()
    vn = insert_vn!("Hidden Review VN")

    insert_status!(user, vn, ~U[2025-04-03 00:00:00Z])

    insert_review!(user, vn, ~U[2025-04-04 00:00:00Z], ~U[2025-04-04 00:00:00Z], %{
      hidden_at: ~U[2025-04-05 00:00:00Z]
    })

    path = Path.join(System.tmp_dir!(), "kaguya_csv_hidden_review_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    refute csv =~ "This review has ||inline spoiler|| text"

    [headers, row] = NimbleCSV.RFC4180.parse_string(csv, skip_headers: false)
    row_map = Map.new(Enum.zip(headers, row))
    assert row_map["Status"] == "read"
    assert row_map["My Review"] == ""
    assert row_map["Review Date"] == ""
    assert row_map["Review Edited At"] == ""

    File.rm(path)
  end

  test "does not export locked review text as importable user data" do
    user = insert_user!()
    vn = insert_vn!("Locked Review VN")

    insert_rating!(user, vn, 4.0, ~U[2025-04-06 00:00:00Z])

    insert_review!(user, vn, ~U[2025-04-07 00:00:00Z], ~U[2025-04-07 00:00:00Z], %{
      is_locked: true
    })

    path = Path.join(System.tmp_dir!(), "kaguya_csv_locked_review_#{UUIDv7.generate()}.csv")
    assert {:ok, %{row_count: 1}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    refute csv =~ "This review has ||inline spoiler|| text"

    [headers, row] = NimbleCSV.RFC4180.parse_string(csv, skip_headers: false)
    row_map = Map.new(Enum.zip(headers, row))
    assert row_map["My Rating"] == "4.0"
    assert row_map["My Review"] == ""

    File.rm(path)
  end

  test "does not export review-only VNs when the review is hidden or locked" do
    user = insert_user!()
    hidden_vn = insert_vn!("Hidden Review Only VN")
    locked_vn = insert_vn!("Locked Review Only VN")

    insert_review!(user, hidden_vn, ~U[2025-04-08 00:00:00Z], ~U[2025-04-08 00:00:00Z], %{
      hidden_at: ~U[2025-04-09 00:00:00Z]
    })

    insert_review!(user, locked_vn, ~U[2025-04-10 00:00:00Z], ~U[2025-04-10 00:00:00Z], %{
      is_locked: true
    })

    path =
      Path.join(System.tmp_dir!(), "kaguya_csv_moderated_review_only_#{UUIDv7.generate()}.csv")

    assert {:ok, %{row_count: 0}} = KaguyaCsv.export_to_path(user.id, path)

    csv = File.read!(path)
    [headers] = NimbleCSV.RFC4180.parse_string(csv, skip_headers: false)
    assert headers == KaguyaCsv.headers()

    File.rm(path)
  end

  test "import does not replace an existing hidden or locked review with a public one" do
    user = insert_user!()
    vn = insert_vn!("Existing Moderated Review VN")
    hidden_at = ~U[2025-04-11 00:00:00Z]

    existing_review =
      insert_review!(user, vn, ~U[2025-04-12 00:00:00Z], ~U[2025-04-12 00:00:00Z], %{
        hidden_at: hidden_at,
        is_locked: true
      })

    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        KaguyaCsv.headers(),
        csv_row(vn, %{
          "My Review" => "This is a replacement review with enough content.",
          "Spoiler" => "false",
          "Review Date" => "2025-04-13T00:00:00Z"
        })
      ])
      |> IO.iodata_to_binary()

    assert {:ok, result} = KaguyaCsv.import_csv(csv, user.id)
    assert result.reviews == 0

    review = Repo.get!(Review, existing_review.id)
    assert review.hidden_at == hidden_at
    assert review.is_locked == true
    assert review.content == "This review has ||inline spoiler|| text and enough content."
  end

  test "rejects partial headers for Kaguya-native imports" do
    user = insert_user!()
    vn = insert_vn!("Partial Header VN")

    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        ["VN ID", "Title", "Slug"],
        [vn.id, vn.title, vn.slug]
      ])
      |> IO.iodata_to_binary()

    assert {:error, message} = KaguyaCsv.import_csv(csv, user.id)
    assert message =~ "CSV is missing required columns"
    assert message =~ "Status"
  end

  test "rejects duplicate VN rows before importing anything" do
    user = insert_user!()
    vn = insert_vn!("Duplicate Row VN")

    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        KaguyaCsv.headers(),
        csv_row(vn, %{"Status" => "read"}),
        csv_row(vn, %{"Status" => "want_to_read"})
      ])
      |> IO.iodata_to_binary()

    assert {:error, message} = KaguyaCsv.import_csv(csv, user.id)
    assert message =~ "duplicate VN IDs"
    refute Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)
  end

  test "rejects invalid typed fields instead of silently dropping them" do
    user = insert_user!()
    vn = insert_vn!("Invalid Rating VN")

    csv =
      NimbleCSV.RFC4180.dump_to_iodata([
        KaguyaCsv.headers(),
        csv_row(vn, %{"My Rating" => "4.7"})
      ])
      |> IO.iodata_to_binary()

    assert {:error, message} = KaguyaCsv.import_csv(csv, user.id)
    assert message =~ "My Rating"
    refute Repo.get_by(Rating, user_id: user.id, visual_novel_id: vn.id)
  end

  defp insert_user! do
    id = UUIDv7.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%User{
      id: id,
      email: "#{id}@example.com",
      username: "u#{String.slice(id, 0, 8)}",
      display_name: "User #{String.slice(id, 0, 4)}",
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_vn!(title) do
    Repo.insert!(%VisualNovel{
      title: title,
      slug: "#{Slug.slugify(title)}-#{System.unique_integer([:positive])}"
    })
  end

  defp insert_status!(user, vn, added_at) do
    Repo.insert!(%ReadingStatus{
      user_id: user.id,
      visual_novel_id: vn.id,
      status: :read,
      date_started: ~D[2024-12-31],
      date_finished: ~D[2025-01-01],
      library_added_at: added_at,
      note: "play after fandisc",
      inserted_at: added_at,
      updated_at: added_at
    })
  end

  defp insert_rating!(user, vn, rating, rated_at) do
    Repo.insert!(%Rating{
      user_id: user.id,
      visual_novel_id: vn.id,
      rating: rating,
      inserted_at: rated_at,
      updated_at: rated_at
    })
  end

  defp insert_review!(user, vn, inserted_at, updated_at, attrs \\ %{}) do
    %{
      user_id: user.id,
      visual_novel_id: vn.id,
      content: "This review has ||inline spoiler|| text and enough content.",
      is_spoiler: true,
      is_edited: true,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
    |> Map.merge(attrs)
    |> then(&struct(Review, &1))
    |> Repo.insert!()
  end

  defp insert_shelf!(user, vn, name, added_at) do
    shelf =
      Repo.insert!(%Shelf{
        user_id: user.id,
        name: name,
        slug: "favorites-odd-#{System.unique_integer([:positive])}",
        vns_count: 1,
        inserted_at: added_at,
        updated_at: added_at
      })

    Repo.insert!(%ShelfItem{
      shelf_id: shelf.id,
      visual_novel_id: vn.id,
      inserted_at: added_at,
      updated_at: added_at
    })
  end

  defp insert_empty_shelf!(user, name, inserted_at) do
    Repo.insert!(%Shelf{
      user_id: user.id,
      name: name,
      slug: "#{Slug.slugify(name)}-#{System.unique_integer([:positive])}",
      vns_count: 0,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end

  defp insert_list!(user, name, display_mode, vns, inserted_at) do
    list =
      Repo.insert!(%VnList{
        user_id: user.id,
        name: name,
        slug: "#{Slug.slugify(name)}-#{System.unique_integer([:positive])}",
        description: "#{name} description",
        display_mode: display_mode,
        is_public: true,
        vns_count: length(vns),
        inserted_at: inserted_at,
        updated_at: inserted_at
      })

    Enum.with_index(vns, 1)
    |> Enum.each(fn {vn, position} ->
      Repo.insert!(%ListItem{
        list_id: list.id,
        visual_novel_id: vn.id,
        position: position,
        inserted_at: inserted_at,
        updated_at: inserted_at
      })
    end)

    list
  end

  defp insert_tier_list!(user, name, tier_entries, inserted_at) do
    list = insert_list!(user, name, "tier", [], inserted_at)

    tier_entries
    |> Enum.with_index(1)
    |> Enum.each(fn {{label, vn}, position} ->
      tier =
        Repo.insert!(%ListTier{
          list_id: list.id,
          label: label,
          color: "#85D0FF",
          position: position,
          inserted_at: inserted_at,
          updated_at: inserted_at
        })

      Repo.insert!(%ListItem{
        list_id: list.id,
        visual_novel_id: vn.id,
        tier_id: tier.id,
        position: position,
        tier_position: 1,
        inserted_at: inserted_at,
        updated_at: inserted_at
      })
    end)

    list
  end

  defp csv_row(vn, overrides) do
    values =
      Map.merge(
        %{
          "VN ID" => vn.id,
          "Title" => vn.title,
          "Slug" => vn.slug,
          "Status" => "",
          "Date Started" => "",
          "Date Finished" => "",
          "Date Added" => "",
          "Notes" => "",
          "My Rating" => "",
          "Rated At" => "",
          "Shelves" => "",
          "Shelves Added At" => "",
          "My Review" => "",
          "Spoiler" => "false",
          "Review Date" => "",
          "Review Edited At" => ""
        },
        overrides
      )

    Enum.map(KaguyaCsv.headers(), &Map.fetch!(values, &1))
  end
end

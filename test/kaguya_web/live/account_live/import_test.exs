defmodule KaguyaWeb.AccountLive.ImportTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.VndbImport

  test "redirects anonymous visitors to login" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/account/import")
  end

  test "renders import instructions for signed-in users" do
    user = UserFixtures.insert_user!()

    {:ok, view, html} = live(conn_for(user), "/account/import")

    assert html =~ "Import your library"
    assert html =~ "I have my export file"

    render_click(view, "show-upload")

    assert has_element?(view, "#vndb-import-form")
    assert has_element?(view, "#vndb-import-form input[type='file']")
    assert render(view) =~ "Drop your export file here"
  end

  test "shows selected VNDB export before import starts" do
    user = UserFixtures.insert_user!()

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")

    render_hook(view, "select-import-file", %{"name" => "vndb-export.xml", "size" => 128})

    html = render(view)

    assert html =~ "vndb-export.xml"
  end

  test "submitting selected export starts processing state" do
    user = UserFixtures.insert_user!()

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")

    render_hook(view, "select-import-file", %{"name" => "vndb-export.xml", "size" => 128})

    render_hook(view, "start-import", %{
      "upload_id" => UUIDv7.generate(),
      "name" => "vndb-export.xml"
    })

    html = render(view)

    assert html =~ "Importing..."
    assert html =~ "1%"
    refute has_element?(view, "#vndb-import-file-action")
  end

  test "shows a friendly upload error before import starts" do
    user = UserFixtures.insert_user!()

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")

    render_hook(view, "select-import-file", %{"name" => "cover.png", "size" => 7})

    html = render(view)

    assert html =~ "Please upload an XML file exported from VNDB."
    refute html =~ "Upload failed:."
  end

  test "completed import shows importing completion state before summary" do
    user = UserFixtures.insert_user!()
    import = insert_completed_import!(user)

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")
    send(view.pid, {:vndb_import_updated, import})

    html = render(view)

    assert html =~ "Importing..."
    refute html =~ "100%"

    send(view.pid, {:complete_import_progress_tick, import.id, 0, 12, 12})

    assert render(view) =~ "100%"
  end

  test "failed imports show a retry state and can reset to the picker" do
    user = UserFixtures.insert_user!()
    import = insert_failed_import!(user, "VNDB could not parse this export.")

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")
    send(view.pid, {:vndb_import_updated, import})

    html = render(view)

    assert html =~ "VNDB could not parse this export."
    assert html =~ "Try again"

    view
    |> element("button[phx-click='reset-import']")
    |> render_click()

    assert has_element?(view, "#vndb-import-form input[type='file']")
    assert render(view) =~ "Drop your export file here"
  end

  test "completed import updates route to summary" do
    user = UserFixtures.insert_user!()
    import = insert_completed_import!(user)

    {:ok, view, _html} = live(conn_for(user), "/account/import")

    render_click(view, "show-upload")
    send(view.pid, {:vndb_import_updated, import})

    html = render(view)

    assert html =~ "Importing..."
    refute html =~ "100%"

    send(view.pid, {:complete_import_progress_tick, import.id, 0, 12, 12})

    assert render(view) =~ "100%"

    send(view.pid, {:finish_import, import.id})

    assert_patch(view, "/account/import/summary")
    assert render(view) =~ "Your library is ready"
  end

  test "renders completed import summary" do
    user = UserFixtures.insert_user!(username: "reader", display_name: "Reader")
    import = insert_completed_import!(user)

    {:ok, _view, html} = live(conn_for(user), "/account/import/summary?import_id=#{import.id}")

    assert html =~ "Your library is ready"
    assert html =~ "Reader"
    assert html =~ "Visual Novels"
    assert html =~ "Umineko"
    assert html =~ "No longer on VNDB"
    assert html =~ "Not on Kaguya"
    assert html =~ ~s(href="/@reader/library")
  end

  test "summary falls back to latest completed import" do
    user = UserFixtures.insert_user!()
    insert_completed_import!(user)

    {:ok, _view, html} = live(conn_for(user), "/account/import/summary")

    assert html =~ "Your library is ready"
    assert html =~ "Umineko"
  end

  defp insert_completed_import!(user) do
    %VndbImport{}
    |> VndbImport.changeset(%{
      id: UUIDv7.generate(),
      user_id: user.id,
      status: "completed",
      result: %{
        "vns_imported" => 1,
        "ratings" => 1,
        "reviews" => 1,
        "shelves" => 1,
        "imported_items" => [
          %{
            "id" => UUIDv7.generate(),
            "title" => "Umineko",
            "slug" => "umineko",
            "images" => %{"medium" => "https://example.com/cover.webp"},
            "has_ero" => false,
            "rating" => 4.5,
            "status" => "read",
            "release_date" => "2007-08-17",
            "date_added" => "2024-01-01T00:00:00Z",
            "date_started" => "2024-01-01",
            "date_finished" => "2024-01-10",
            "vote_date" => "2024-01-10"
          }
        ],
        "missing_vns" => [%{"title" => "Missing VN", "vndb_url" => "https://vndb.org/v1"}],
        "banned_vns" => [%{"title" => "Excluded VN", "vndb_url" => "https://vndb.org/v2"}]
      }
    })
    |> Repo.insert!()
  end

  defp insert_failed_import!(user, message) do
    %VndbImport{}
    |> VndbImport.changeset(%{
      id: UUIDv7.generate(),
      user_id: user.id,
      status: "failed",
      error_message: message
    })
    |> Repo.insert!()
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end
end

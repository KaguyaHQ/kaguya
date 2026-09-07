defmodule KaguyaWeb.SettingsLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.Users.{User, UserLibraryExport}

  test "redirects anonymous visitors to login" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/settings")
  end

  test "renders settings for signed-in users on legacy and account routes" do
    user = UserFixtures.insert_user!(email: "reader@example.com")

    for path <- ["/settings", "/account/settings", "/settings/integrations"] do
      {:ok, view, html} = live(conn_for(user), path)

      assert html =~ "Settings"
      assert html =~ "Sensitive content"
      assert html =~ "Show NSFW covers"
      refute has_element?(view, "#content-preferences [phx-value-field='show_adjacent']")
      assert html =~ "Import your library"
      assert html =~ "Export your data"
      assert html =~ "reader@example.com"
      refute html =~ "Change password"
    end
  end

  test "toggles content preferences" do
    user =
      UserFixtures.insert_user!(
        show_nsfw_images: false,
        show_nukige: true,
        show_adjacent: true
      )

    {:ok, view, _html} = live(conn_for(user), "/settings")

    assert render_click(view, "toggle_preference", %{"field" => "show_nsfw_images"}) =~
             "NSFW covers are now visible."

    assert Repo.get!(User, user.id).show_nsfw_images

    assert render_click(view, "toggle_preference", %{"field" => "show_nukige"}) =~
             "Nukige titles are now hidden."

    refute Repo.get!(User, user.id).show_nukige
  end

  test "obsolete hybrid preference events do not change stored settings" do
    user =
      UserFixtures.insert_user!()
      |> Ecto.Changeset.change(show_adjacent: false)
      |> Repo.update!()

    {:ok, view, _html} = live(conn_for(user), "/settings")

    render_click(view, "toggle_preference", %{"field" => "show_adjacent"})

    refute Repo.get!(User, user.id).show_adjacent
    assert has_element?(view, "#content-preferences")
  end

  test "downloads the existing completed export without starting a new one" do
    user = UserFixtures.insert_user!(username: "export_reader")

    {:ok, %UserLibraryExport{} = export} =
      Users.create_user_library_export(%{
        user_id: user.id,
        status: :completed,
        object_key: "users/exports/kaguya/#{user.id}/export.zip",
        row_count: 12,
        byte_size: 4096
      })

    {:ok, view, _html} = live(conn_for(user), "/settings")

    assert has_element?(view, "#export-status", "Completed · 12 rows · 4 KB")
    view |> element("#download-export") |> render_click()

    assert_push_event(view, "kaguya:download-file", %{url: url})
    assert is_binary(url)
    assert url =~ export.object_key

    assert [^export] = Users.list_user_library_exports(user.id)
  end

  test "generates a fresh export while preserving the previous download and deduplicates requests" do
    user = UserFixtures.insert_user!()
    export = completed_export!(user)
    {:ok, view, _} = live(conn_for(user), "/settings")

    view |> element("#generate-export") |> render_click()
    assert [queued, ^export] = Users.list_user_library_exports(user.id)
    assert queued.status == :queued
    assert has_element?(view, "#generate-export[disabled]")

    render_click(view, "start_export")
    assert [^queued, ^export] = Users.list_user_library_exports(user.id)

    view |> element("#download-export") |> render_click()
    assert_push_event(view, "kaguya:download-file", %{url: url})
    assert url =~ export.object_key

    {:ok, _} =
      Users.update_user_library_export(queued, %{
        status: :completed,
        object_key: "fresh-backup.zip"
      })

    send(view.pid, :poll_export)
    assert has_element?(view, "#generate-export:not([disabled])")
    assert_push_event(view, "kaguya:download-file", %{url: fresh_url})
    assert fresh_url =~ "fresh-backup.zip"
  end

  test "expired backups cannot be downloaded and can be replaced" do
    user = UserFixtures.insert_user!()
    export = completed_export!(user)
    {:ok, view, _} = live(conn_for(user), "/settings")
    assert has_element?(view, "#download-export")

    export
    |> Ecto.Changeset.change(
      inserted_at: DateTime.utc_now() |> DateTime.add(-4, :day) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    view |> element("#download-export") |> render_click()
    refute has_element?(view, "#download-export")
    assert has_element?(view, "#export-status", "Backup expired")
    view |> element("#generate-export") |> render_click()
    assert [%{status: :queued}, %{status: :completed}] = Users.list_user_library_exports(user.id)
  end

  test "a failed replacement keeps the previous backup available and allows retry" do
    user = UserFixtures.insert_user!()
    export = completed_export!(user)
    {:ok, view, _} = live(conn_for(user), "/settings")
    view |> element("#generate-export") |> render_click()
    [queued, _] = Users.list_user_library_exports(user.id)

    {:ok, _} =
      Users.update_user_library_export(queued, %{status: :failed, error: "Export failed."})

    send(view.pid, :poll_export)

    assert has_element?(view, "#generate-export:not([disabled])")
    view |> element("#download-export") |> render_click()
    assert_push_event(view, "kaguya:download-file", %{url: url})
    assert url =~ export.object_key
    view |> element("#generate-export") |> render_click()

    assert [%{status: :queued}, %{status: :failed}, %{status: :completed}] =
             Users.list_user_library_exports(user.id)
  end

  defp completed_export!(user) do
    {:ok, export} =
      Users.create_user_library_export(%{
        user_id: user.id,
        status: :completed,
        object_key: "users/exports/#{user.id}/backup.zip"
      })

    export
  end

  test "reset library uses the destructive confirmation dialog" do
    user = UserFixtures.insert_user!()

    {:ok, view, _html} = live(conn_for(user), "/settings")

    assert render_click(view, "open_reset_library_dialog") =~ "Start over from zero?"
    assert render_click(view, "reset_library") =~ "Library reset."
  end

  test "delete account uses confirmation dialog and signs out after deletion" do
    user = UserFixtures.insert_user!()

    {:ok, view, _html} = live(conn_for(user), "/settings")

    assert render_click(view, "open_delete_account_dialog") =~ "This deletes everything."
    render_click(view, "delete_account")

    assert_push_event(view, "kaguya:submit-form", %{selector: "#account-deleted-sign-out-form"})
    refute Repo.get(User, user.id)
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end
end

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
      {:ok, _view, html} = live(conn_for(user), path)

      assert html =~ "Settings"
      assert html =~ "Sensitive content"
      assert html =~ "Show NSFW covers"
      assert html =~ "Show VN hybrids"
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

  test "downloads the latest completed export instead of starting a new one" do
    user = UserFixtures.insert_user!(username: "export_reader")

    {:ok, %UserLibraryExport{} = export} =
      Users.create_user_library_export(%{
        user_id: user.id,
        status: :completed,
        object_key: "users/exports/kaguya/#{user.id}/export.zip",
        row_count: 12,
        byte_size: 4096
      })

    {:ok, view, html} = live(conn_for(user), "/settings")

    assert html =~ "Completed · 12 rows · 4 KB"
    render_click(view, "start_export")

    assert_push_event(view, "kaguya:download-file", %{url: url})
    assert is_binary(url)
    assert url =~ export.object_key

    assert [^export] = Users.list_user_library_exports(user.id)
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

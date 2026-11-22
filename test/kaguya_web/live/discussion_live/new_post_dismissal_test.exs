defmodule KaguyaWeb.DiscussionLive.NewPostDismissalTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Test.UserFixtures

  test "untouched composer closes without confirmation", %{conn: conn} do
    author = UserFixtures.insert_user!()
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/discussions")

    render_click(view, "open_new_post")
    assert has_element?(view, "#new-post-dialog")

    render_click(view, "close_new_post")
    refute has_element?(view, "#new-post-discard")
    refute has_element?(view, "#new-post-dialog")
  end

  test "unsaved text warns and keep editing restores the composer", %{conn: conn} do
    author = UserFixtures.insert_user!()
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/discussions")

    render_click(view, "open_new_post")

    view
    |> form("#new-post-form", %{"title" => "Unsaved draft"})
    |> render_change()

    render_click(view, "close_new_post")
    assert has_element?(view, "#new-post-discard")

    render_click(view, "keep_editing_new_post")
    assert_push_event(view, "kaguya:dialog-open", %{id: "new-post-dialog"})
    refute has_element?(view, "#new-post-discard")
    assert has_element?(view, ~s(#new-post-title[value="Unsaved draft"]))
  end

  test "changing the topic warns, but returning to the initial topic is clean", %{conn: conn} do
    author = UserFixtures.insert_user!()
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/discussions")

    render_click(view, "open_new_post")

    render_click(view, "select_category_target", %{
      "category_type" => "site_discussions",
      "entity_id" => "",
      "name" => "Feedback",
      "slug" => "feedback"
    })

    render_click(view, "close_new_post")
    assert has_element?(view, "#new-post-discard")
    render_click(view, "keep_editing_new_post")

    render_click(view, "select_category_target", %{
      "category_type" => "general",
      "entity_id" => "",
      "name" => "General",
      "slug" => "general"
    })

    render_click(view, "close_new_post")
    refute has_element?(view, "#new-post-discard")
    refute has_element?(view, "#new-post-dialog")
  end
end

defmodule KaguyaWeb.VNLive.ScreenshotBackdropTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Screenshots
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.VNLive.PageData

  setup do
    Cachex.clear(:vn_page_cache)
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{title: "Backdrop test", slug: "backdrop-test"})
      |> Repo.insert!()

    %{user: user, vn: vn}
  end

  test "liking and unliking refresh the open backdrop and cached page", %{
    conn: conn,
    user: user,
    vn: vn
  } do
    original = screenshot(vn, 800)
    winner = screenshot(vn, 1600)
    other = UserFixtures.insert_user!()
    assert {:ok, true} = Screenshots.like_screenshot(original.id, other.id)

    {:ok, view, _} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live(~p"/vn/#{vn.slug}/screenshots")

    render_async(view)
    assert_backdrop(view, original)
    assert_cached_backdrop(vn, original)

    view |> element("#desktop-screenshot-like-screenshot-id-#{winner.id}") |> render_click()
    assert Repo.get!(VisualNovel, vn.id).featured_screenshot_id == winner.id
    assert_backdrop(view, winner)
    assert_cached_backdrop(vn, winner)

    view |> element("#desktop-screenshot-like-screenshot-id-#{winner.id}") |> render_click()
    assert Repo.get!(VisualNovel, vn.id).featured_screenshot_id == original.id
    assert_backdrop(view, original)
    assert_cached_backdrop(vn, original)
  end

  test "first screenshot vote adds a backdrop without reloading", %{
    conn: conn,
    user: user,
    vn: vn
  } do
    screenshot = screenshot(vn, 1600)

    {:ok, view, _} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live(~p"/vn/#{vn.slug}/screenshots")

    render_async(view)
    refute has_element?(view, "img[fetchpriority='high'][alt='']")
    view |> element("#desktop-screenshot-like-screenshot-id-#{screenshot.id}") |> render_click()
    assert_backdrop(view, screenshot)
    assert_cached_backdrop(vn, screenshot)
  end

  test "main page previews respect content preferences and open the screenshot lightbox", %{
    conn: conn,
    vn: vn
  } do
    safe = screenshot(vn, 800)
    hidden = screenshot(vn, 1600)
    hidden |> Ecto.Changeset.change(is_nsfw: true) |> Repo.update!()
    {:ok, view, _} = live(conn, ~p"/vn/#{vn.slug}")
    render_async(view)
    assert has_element?(view, "#desktop-screenshot-preview-#{safe.id}")
    refute has_element?(view, "#desktop-screenshot-preview-#{hidden.id}")
    view |> element("#desktop-screenshot-preview-#{safe.id}") |> render_click()
    assert has_element?(view, "#media-lightbox")
    url = VisualNovels.build_screenshot_urls(safe.id).large
    assert has_element?(view, "#media-lightbox img[src='#{url}']")
  end

  defp screenshot(vn, width) do
    %Screenshot{}
    |> Screenshot.changeset(%{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      width: width,
      height: 600
    })
    |> Repo.insert!()
  end

  defp assert_backdrop(view, screenshot) do
    urls = VisualNovels.build_screenshot_urls(screenshot.id)
    assert has_element?(view, "img[fetchpriority='high'][src='#{urls.large}']")
    assert has_element?(view, "img[alt=''][src='#{urls.medium}']")
  end

  defp assert_cached_backdrop(vn, screenshot) do
    {:ok, _, page} = PageData.get_public_page(vn.slug)

    assert page.vn.featured_screenshot.large ==
             VisualNovels.build_screenshot_urls(screenshot.id).large
  end
end

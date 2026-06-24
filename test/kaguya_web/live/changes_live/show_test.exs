defmodule KaguyaWeb.ChangesLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Kaguya.Repo
  alias Kaguya.Releases.Release
  alias Kaguya.Revisions
  alias Kaguya.Revisions.Change
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{Image, VNTitle, VisualNovel}

  test "renders revision header, author, summary, links, and scalar diff", %{conn: conn} do
    user = insert_user!(username: "show_author", display_name: "Show Author")
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
    vn = insert_vn!(title: "Show Diff VN", description: "Old description")
    insert_initial_title!(vn, "en", "Show Diff VN")

    {:ok, change} =
      Revisions.submit_edit(
        :visual_novel,
        vn.id,
        %{description: "New description"},
        "Update description",
        user
      )

    {:ok, view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")

    assert html =~ "Revision r2"
    assert has_element?(view, "#revision-diff-row-description")
    assert html =~ "Copy link"
    assert html =~ "Edit entity"
    assert html =~ "Update description"
    assert html =~ "Show Author"
    assert html =~ "Description"
    assert html =~ "Old description"
    assert html =~ "New description"
    assert html =~ ~s(href="/vn/#{vn.slug}")
    assert html =~ ~s(href="/vn/#{vn.slug}/history")
    assert html =~ ~s(href="/vn/#{vn.slug}/edit")
    assert html =~ "data-share-button"
  end

  test "initial revision renders the no previous state message", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!(title: "Initial VN")
    insert_initial_title!(vn, "en", "Initial VN")

    {:ok, _change} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "First"}, "First edit", user)

    [initial | _] = revisions_for(vn)

    {:ok, view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{initial.id}")

    assert html =~ "Revision r1"
    assert html =~ "No previous state to compare."
    assert has_element?(view, "#revision-initial-empty")
  end

  test "revision detail links to adjacent earlier and later revisions", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!(title: "Adjacent Revision VN", description: "first")
    insert_initial_title!(vn, "en", "Adjacent Revision VN")

    {:ok, _r2} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "second"}, "Second", user)

    {:ok, r3} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "third"}, "Third", user)

    [r1, r2, _r3] = revisions_for(vn)

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{r2.id}")

    assert html =~ "earlier"
    assert html =~ "later"
    assert html =~ ~s(href="/vn/#{vn.slug}/history/#{r1.id}")
    assert html =~ ~s(href="/vn/#{vn.slug}/history/#{r3.id}")
  end

  test "release revision links back to the parent VN history", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!(title: "Release Parent VN")
    release = insert_release!(vn, title: "Release r1", notes: "old notes")

    {:ok, change} =
      Revisions.submit_edit(:release, release.id, %{notes: "new notes"}, "Update release", user)

    {:ok, _view, html} =
      live(conn, ~p"/vn/#{vn.slug}/release/#{release.id}/history/#{change.id}")

    assert html =~ ~s(href="/vn/#{vn.slug}/history")
    assert html =~ ~s(href="/vn/#{vn.slug}")
    refute html =~ ~s(href="/vn/#{vn.slug}/release/#{release.id}")
  end

  test "relation changes render readable rows instead of JSON", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!(title: "Relation VN")
    related = insert_vn!(title: "Xi Jjia Cheng Zhen")
    insert_initial_title!(vn, "en", "Relation VN")
    insert_initial_title!(related, "en", "Xi Jjia Cheng Zhen")

    {:ok, change} =
      Revisions.submit_edit(
        :visual_novel,
        vn.id,
        %{relations: [%{related_vn_id: related.id, relation_type: "sequel"}]},
        "Add relation",
        user
      )

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")

    assert html =~ "Relations"
    assert html =~ "[official] Sequel: Xi Jjia Cheng Zhen"
    refute html =~ ~s("related_vn_id")
  end

  test "cover and screenshot metadata edits render thumbnails and inline metadata", %{conn: conn} do
    user = insert_user!(show_nsfw_screenshots: true)
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
    vn = insert_vn!(title: "Media VN", description: "original")
    insert_initial_title!(vn, "en", "Media VN")
    cover = insert_cover!(vn, is_image_nsfw: false)
    screenshot = insert_screenshot!(vn, is_nsfw: false)

    {:ok, _r2} =
      Revisions.submit_edit(
        :visual_novel,
        vn.id,
        %{description: "snapshot media"},
        "Snapshot media",
        user
      )

    {:ok, change} =
      Revisions.submit_edit(
        :visual_novel,
        vn.id,
        %{
          covers: [%{cover_id: cover.id, is_image_nsfw: true}],
          screenshots: [%{screenshot_id: screenshot.id, is_nsfw: true}]
        },
        "Update media flags",
        user
      )

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")

    assert html =~ "Covers"
    assert html =~ "Screenshots"
    assert html =~ "#{cover.id}-256w.webp"
    assert html =~ "#{screenshot.id}-640w.webp"
    assert html =~ "NSFW: No -&gt; Yes"
    refute html =~ ~s("changed")
    refute html =~ ~s("screenshot_id")
  end

  test "revert button is hidden for anonymous and can_edit false viewers", %{conn: conn} do
    author = insert_user!()
    vn = insert_vn!(title: "Hidden Revert VN", description: "old")
    insert_initial_title!(vn, "en", "Hidden Revert VN")

    {:ok, change} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "new"}, "Change", author)

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")
    refute html =~ "Revert to this"

    restricted = insert_user!(username: "restricted_revert", can_edit: false)
    conn = Plug.Test.init_test_session(build_conn(), %{"current_user_id" => restricted.id})
    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")
    refute html =~ "Revert to this"
  end

  test "too-short revert summary keeps the panel open with validation feedback", %{conn: conn} do
    user = insert_user!()
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
    vn = insert_vn!(title: "Short Revert VN", description: "old")
    insert_initial_title!(vn, "en", "Short Revert VN")

    {:ok, change} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "new"}, "Change", user)

    {:ok, view, _html} = live(conn, ~p"/vn/#{vn.slug}/history/#{change.id}")

    view |> element("#revision-revert-toggle") |> render_click()

    html =
      view
      |> element("#revision-revert-form")
      |> render_submit(%{"revert" => %{"summary" => "x"}})

    assert html =~ "Summary must be at least 2 characters."
    assert has_element?(view, "#revision-revert-panel")
  end

  test "valid revert summary creates a revert and navigates back to history", %{conn: conn} do
    user = insert_user!()
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
    vn = insert_vn!(title: "Revert VN", description: "old")
    insert_initial_title!(vn, "en", "Revert VN")

    {:ok, _change} =
      Revisions.submit_edit(:visual_novel, vn.id, %{description: "new"}, "Change", user)

    [initial | _] = revisions_for(vn)

    {:ok, view, _html} = live(conn, ~p"/vn/#{vn.slug}/history/#{initial.id}")

    view |> element("#revision-revert-toggle") |> render_click()

    view
    |> element("#revision-revert-form")
    |> render_submit(%{"revert" => %{"summary" => "Restore old state"}})

    assert_redirected(view, "/vn/#{vn.slug}/history")
    assert Repo.get!(VisualNovel, vn.id).description == "old"
  end

  defp insert_user!(attrs \\ %{}) do
    suffix = unique_suffix()
    attrs = Enum.into(attrs, %{})

    base = %{
      id: Ecto.UUID.generate(),
      username: "changes_show_#{suffix}",
      display_name: "Changes Show #{suffix}",
      email: "changes_show_#{suffix}@test.local",
      can_edit: true,
      show_nsfw_screenshots: false,
      show_brutal_screenshots: false
    }

    fields = [
      :id,
      :username,
      :display_name,
      :email,
      :role,
      :can_edit,
      :show_nsfw_screenshots,
      :show_brutal_screenshots
    ]

    %User{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), fields)
    |> Repo.insert!()
  end

  defp insert_vn!(attrs) do
    suffix = unique_suffix()
    attrs = Enum.into(attrs, %{})

    Repo.insert!(%VisualNovel{
      title: Map.get(attrs, :title, "Show VN #{suffix}"),
      slug: Map.get(attrs, :slug, "show-vn-#{String.downcase(suffix)}"),
      description: Map.get(attrs, :description),
      aliases: [],
      title_category: :vn,
      original_language: "en",
      is_locked: Map.get(attrs, :is_locked, false)
    })
  end

  defp insert_initial_title!(vn, lang, title) do
    Repo.insert!(%VNTitle{
      visual_novel_id: vn.id,
      lang: lang,
      title: title,
      official: true
    })
  end

  defp insert_release!(vn, attrs) do
    attrs = Enum.into(attrs, %{})

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: Map.get(attrs, :title, "Test release"),
      notes: Map.get(attrs, :notes),
      platforms: Map.get(attrs, :platforms, ["win"]),
      languages: Map.get(attrs, :languages, ["en"])
    })
    |> Repo.insert!()
  end

  defp insert_cover!(vn, attrs) do
    attrs = Enum.into(attrs, %{})

    Repo.insert!(%Image{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      is_image_nsfw: Map.get(attrs, :is_image_nsfw, false),
      is_image_suggestive: Map.get(attrs, :is_image_suggestive, false)
    })
  end

  defp insert_screenshot!(vn, attrs) do
    attrs = Enum.into(attrs, %{})

    Repo.insert!(%Screenshot{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      is_nsfw: Map.get(attrs, :is_nsfw, false),
      is_brutal: Map.get(attrs, :is_brutal, false)
    })
  end

  defp revisions_for(vn) do
    Repo.all(
      from(c in Change,
        where: c.entity_type == :visual_novel and c.entity_id == ^vn.id,
        order_by: [asc: c.revision_number]
      )
    )
  end

  defp unique_suffix do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end
end

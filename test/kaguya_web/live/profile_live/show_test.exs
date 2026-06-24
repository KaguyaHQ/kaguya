defmodule KaguyaWeb.ProfileLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Activities
  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username (overview)" do
    test "renders the header and the overview body" do
      _user = UserFixtures.insert_user!(username: "alice", display_name: "Alice")

      {:ok, _view, html} = live(build_conn(), "/@alice")

      assert html =~ "Alice"
      assert html =~ "@alice"
      # Stats grid links + nav links are derived from the username
      assert html =~ ~s(href="/@alice/library")
      assert html =~ ~s(href="/@alice/followers")
      # Sidebar bio block exists with the "Write something about yourself"
      # CTA (non-owner viewers see no bio + no CTA; owner sees the CTA).
      # For a no-bio profile viewed by signed-out, the sidebar bio block
      # is suppressed so we don't assert it here.
      refute html =~ "coming soon"
    end

    test "renders the not-found screen for an unknown username" do
      {:ok, _view, html} = live(build_conn(), "/@no_such_user")

      assert html =~ "https://images.kaguya.io/ui/404.webp"
      assert html =~ "Return home"
    end

    test "hides reviews/lists tabs at zero count for non-owner viewers" do
      _user = UserFixtures.insert_user!(username: "quiet_user")

      {:ok, _view, html} = live(build_conn(), "/@quiet_user")

      # Profile and Activity always render
      assert html =~ ~s(data-tab="overview")
      assert html =~ ~s(data-tab="activity")
      # Reviews and Lists are filtered out at count=0 for non-owners
      refute html =~ ~s(data-tab="reviews")
      refute html =~ ~s(data-tab="lists")
      # Favorites is always shown (free for everyone)
      assert html =~ ~s(data-tab="favorites")
    end

    test "owner sees the Lists nav entry even at zero count" do
      user = UserFixtures.insert_user!(username: "owner_user")
      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})

      {:ok, _view, html} = live(conn, "/@owner_user")

      assert html =~ ~s(data-tab="lists")
      # Reviews is still hidden because reviewsCount==0 even for owners
      # (matches `ProfileNav.tsx:170` — owner check only applies to lists+edits).
      refute html =~ ~s(data-tab="reviews")
    end

    test "inner-page tab renders no banner and shows the mobile compact row" do
      _user = UserFixtures.insert_user!(username: "khamet", display_name: "Khamet")

      {:ok, _view, html} = live(build_conn(), "/@khamet/activity")

      refute html =~ ~s(alt="profile cover")
      # Compact row links back to root profile
      assert html =~ ~s(href="/@khamet")
      # Activity tab renders its empty state when the user has no activity.
      assert html =~ "No recent activity"
    end

    test "owner sees the favorite-VN empty edit pencils" do
      user = UserFixtures.insert_user!(username: "pencil_owner")
      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: user.id})

      {:ok, _view, html} = live(conn, "/@pencil_owner")

      # Empty slot links point at the favorites editor when the viewer is
      # the profile owner.
      assert html =~ "/account/edit/profile#favorite-visual-novels"
    end

    test "member-since date matches production day format" do
      user = UserFixtures.insert_user!(username: "member_since")
      inserted_at = ~U[2024-01-05 12:00:00Z]

      Kaguya.Repo.update_all(
        from(u in Kaguya.Users.User, where: u.id == ^user.id),
        set: [inserted_at: inserted_at]
      )

      {:ok, _view, html} = live(build_conn(), "/@member_since")

      assert html =~ "January 5, 2024"
      refute html =~ "January 05, 2024"
    end

    test "signed-out viewer sees the favorite-VN block but no edit pencils" do
      _user = UserFixtures.insert_user!(username: "pencil_visitor")

      {:ok, _view, html} = live(build_conn(), "/@pencil_visitor")

      # Non-owners never see the pencil/CTA link to settings.
      refute html =~ "/account/edit/profile#favorite-visual-novels"
    end

    test "favorite VN covers link to their VN pages" do
      user = UserFixtures.insert_user!(username: "favorite_links")
      vn = insert_vn!("Favorite Link VN")
      set_favorite_vns(user, [vn.id])

      {:ok, _view, html} = live(build_conn(), "/@favorite_links")

      assert html =~ ~s(href="/vn/#{vn.slug}")
      assert html =~ "Favorite Link VN"
    end

    test "overview library covers link to their VN pages" do
      user = UserFixtures.insert_user!(username: "overview_cover_links")
      read_vn = insert_vn!("Recently Read Link VN")
      reading_vn = insert_vn!("Currently Reading Link VN")
      wishlist_vn = insert_vn!("Wishlist Link VN")

      insert_status!(user, read_vn, :read)
      insert_status!(user, reading_vn, :currently_reading)
      insert_status!(user, wishlist_vn, :want_to_read)

      {:ok, _view, html} = live(build_conn(), "/@overview_cover_links")

      assert html =~ ~s(href="/vn/#{read_vn.slug}")
      assert html =~ ~s(href="/vn/#{reading_vn.slug}")
      assert html =~ ~s(href="/vn/#{wishlist_vn.slug}")
    end

    test "admin viewer sees the Mod pill with full action set" do
      _target = UserFixtures.insert_user!(username: "target_user")
      admin = UserFixtures.insert_user!(username: "admin_user")

      Kaguya.Repo.update_all(
        from(u in Kaguya.Users.User, where: u.id == ^admin.id),
        set: [role: :admin]
      )

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: admin.id})
      {:ok, _view, html} = live(conn, "/@target_user")

      assert html =~ ~s(aria-label="Moderation actions")
      assert html =~ ~s(&quot;event&quot;:&quot;mod_open_permissions&quot;)
      assert html =~ ~s(&quot;event&quot;:&quot;mod_open_suppress&quot;)
      assert html =~ ~s(&quot;event&quot;:&quot;mod_open_delete&quot;)
    end

    test "non-mod viewer on someone else's profile does not see the Mod pill" do
      _target = UserFixtures.insert_user!(username: "regular_target")
      viewer = UserFixtures.insert_user!(username: "regular_viewer")

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: viewer.id})
      {:ok, _view, html} = live(conn, "/@regular_target")

      refute html =~ ~s(aria-label="Moderation actions")
    end

    test "admin viewer on their own profile does not see the Mod pill" do
      admin = UserFixtures.insert_user!(username: "self_admin")

      Kaguya.Repo.update_all(
        from(u in Kaguya.Users.User, where: u.id == ^admin.id),
        set: [role: :admin]
      )

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: admin.id})
      {:ok, _view, html} = live(conn, "/@self_admin")

      refute html =~ ~s(aria-label="Moderation actions")
    end

    test "logged-out viewer does not see the Mod pill" do
      _target = UserFixtures.insert_user!(username: "anon_target")

      {:ok, _view, html} = live(build_conn(), "/@anon_target")

      refute html =~ ~s(aria-label="Moderation actions")
    end

    test "permissions dialog renders switches and a close button" do
      _target = UserFixtures.insert_user!(username: "perms_target")
      admin = UserFixtures.insert_user!(username: "perms_admin")

      Kaguya.Repo.update_all(
        from(u in Kaguya.Users.User, where: u.id == ^admin.id),
        set: [role: :admin]
      )

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: admin.id})
      {:ok, view, _html} = live(conn, "/@perms_target")

      open_html = render_click(view, "mod_open_permissions", %{})

      assert open_html =~ ~s(role="switch")
      assert open_html =~ ~s(aria-label="Close")
      assert open_html =~ "User permissions"
      assert open_html =~ "Manage what @perms_target can do on Kaguya"
    end

    test "follow toggle bumps the follower count via Events" do
      target = UserFixtures.insert_user!(username: "follow_target")
      viewer = UserFixtures.insert_user!(username: "follow_viewer")

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: viewer.id})
      {:ok, view, _html} = live(conn, "/@follow_target")

      # Click the follow button — the header refreshes via Events.toggle_follow.
      Phoenix.LiveViewTest.render_click(view, "toggle_follow", %{"user-id" => target.id})

      assert {:ok, header} = KaguyaWeb.ProfileLive.Data.load_header("follow_target", viewer)
      assert header.counts.followers == 1
    end

    test "overview review hearts render liked state for the viewer and toggle optimistically" do
      author = UserFixtures.insert_user!(username: "overview_author")
      viewer = UserFixtures.insert_user!(username: "overview_viewer")
      vn = insert_vn!("Overview Review VN")
      {:ok, review} = Reviews.create_review(author.id, vn.id, %{content: long_content("liked")})
      assert {:ok, true} = Reviews.like_review(review.id, viewer.id)

      conn = build_conn() |> Plug.Test.init_test_session(%{current_user_id: viewer.id})
      {:ok, view, html} = live(conn, "/@overview_author")

      assert html =~ ~s(phx-click="toggle_review_like")
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(aria-label="Unlike")

      after_unlike = render_click(view, "toggle_review_like", %{"review-id" => review.id})

      assert after_unlike =~ ~s(aria-pressed="false")
      assert after_unlike =~ ~s(aria-label="Like")
      assert Repo.get!(Kaguya.Reviews.Review, review.id).likes_count == 0

      after_like = render_click(view, "toggle_review_like", %{"review-id" => review.id})

      assert after_like =~ ~s(aria-pressed="true")
      assert after_like =~ ~s(aria-label="Unlike")
      assert Repo.get!(Kaguya.Reviews.Review, review.id).likes_count == 1
    end

    test "activity sidebar renders discussion comments as discussion comments" do
      user =
        UserFixtures.insert_user!(username: "discussion_commenter", display_name: "Mika")

      {:ok, _activity} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :commented,
          entity_type: "post_comment",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "parent_entity_type" => "post",
            "post_title" => "Route planning thread",
            "post_short_id" => "abc12345",
            "post_slug" => "route-planning-thread",
            "text_preview" => "This should stay a discussion comment."
          }
        })

      {:ok, _view, html} = live(build_conn(), "/@discussion_commenter")

      assert html =~ "commented on"
      assert html =~ "Route planning thread"
      assert html =~ "This should stay a discussion comment."
      assert html =~ ~s(href="/discussions/p/abc12345/route-planning-thread")
      refute html =~ "commented on a review of a visual novel"
    end
  end

  defp insert_vn!(title) do
    Repo.insert!(%VisualNovel{
      title: title,
      slug: "#{Slug.slugify(title)}-#{System.unique_integer([:positive])}"
    })
  end

  defp set_favorite_vns(user, ids) do
    Repo.update_all(
      from(u in Kaguya.Users.User, where: u.id == ^user.id),
      set: [favorite_visual_novels: ids]
    )
  end

  defp insert_status!(user, vn, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ReadingStatus{
      user_id: user.id,
      visual_novel_id: vn.id,
      status: status,
      library_added_at: now
    })
  end

  defp long_content(seed),
    do: seed <> String.duplicate(" filler for the 40-char min length", 5)
end

defmodule KaguyaWeb.DiscussionLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Discussions
  alias Kaguya.Discussions.{Comment, Post}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders the unified discussion feed and post metadata", %{conn: conn} do
    author =
      UserFixtures.insert_user!(username: "thread_author", display_name: "Thread Author")

    commenter =
      UserFixtures.insert_user!(username: "reply_author", display_name: "Reply Author")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Favorite common route twists",
        content: "What are your favorite **common route** surprises?",
        category_type: :general
      })

    {:ok, _comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "The best ones reframe the opening."
      })

    {:ok, _view, html} = live(conn, ~p"/discussions")

    assert html =~ "Discussions"
    assert html =~ ~s(href="/discussions")
    assert html =~ "General"
    assert html =~ "Favorite common route twists"
    assert html =~ "Thread Author"
    assert html =~ "Reply Author"
    assert html =~ ~s(href="/discussions/p/#{post.short_id}/#{post.slug}")
    refute html =~ "No discussions yet."
  end

  test "root feed is not capped to five posts from a category", %{conn: conn} do
    for index <- 1..6 do
      create_ordered_post!(index, "Uncapped discussion #{index}")
    end

    {:ok, _view, html} = live(conn, ~p"/discussions")

    for index <- 1..6 do
      assert html =~ "Uncapped discussion #{index}"
    end
  end

  test "root feed loads the next cursor page", %{conn: conn} do
    for index <- 1..21 do
      create_ordered_post!(index, "Paginated discussion #{index}")
    end

    {:ok, view, html} = live(conn, ~p"/discussions")

    assert html =~ "Paginated discussion 20"
    refute html =~ "Paginated discussion 21"
    assert html =~ "Load More"

    html = render_click(view, "load_more_posts")

    assert html =~ "Paginated discussion 21"
    refute html =~ "Load More"
  end

  test "renders the empty discussion state", %{conn: conn} do
    Repo.delete_all(Kaguya.Discussions.Comment)
    Repo.delete_all(Post)

    {:ok, _view, html} = live(conn, ~p"/discussions")

    assert html =~ "No discussions yet."
    assert html =~ "New Post"
  end

  test "renders a category page from the sidebar route", %{conn: conn} do
    author =
      UserFixtures.insert_user!(username: "site_author", display_name: "Site Author")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Small feature requests",
        content: "A thread for smaller ideas.",
        category_type: :site_discussions
      })

    {:ok, _view, html} = live(conn, ~p"/discussions/feedback")

    assert html =~ "Feedback"
    assert html =~ "Small feature requests"
    assert html =~ "Recent Activity"
    assert html =~ "Newest"
    assert html =~ "Most Liked"
    assert html =~ ~s(href="/discussions/p/#{post.short_id}/#{post.slug}")
  end

  test "renders compact calendar labels for discussion activity", %{conn: conn} do
    author =
      UserFixtures.insert_user!(username: "timed_author", display_name: "Timed Author")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Timestamp parity thread",
        content: "Checking the discussion timestamp formatter.",
        category_type: :general
      })

    inserted_at = DateTime.utc_now() |> DateTime.add(-3, :hour) |> DateTime.truncate(:second)

    Repo.update_all(
      from(p in Post, where: p.id == ^post.id),
      set: [inserted_at: inserted_at, updated_at: inserted_at, last_comment_at: nil]
    )

    {:ok, _view, html} = live(conn, ~p"/discussions")

    assert html =~ "Timestamp parity thread"
    assert html =~ "3h"
    refute html =~ "3 hours ago"
  end

  test "renders a VN-scoped discussion detail page", %{conn: conn} do
    author =
      UserFixtures.insert_user!(
        username: "vn_thread_author",
        display_name: "VN Thread Author"
      )

    commenter =
      UserFixtures.insert_user!(
        username: "vn_reply_author",
        display_name: "VN Reply Author"
      )

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Full Metal Daemon Muramasa",
        slug: "full-metal-daemon-muramasa",
        description: "A" <> String.duplicate(" test visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Route order for Muramasa",
        content: "How should I approach the **routes**?\n\n||Bad end spoilers||",
        category_type: :visual_novel,
        entity_id: vn.id
      })

    inserted_at = DateTime.utc_now() |> DateTime.add(-3, :hour) |> DateTime.truncate(:second)

    Repo.update_all(
      from(p in Post, where: p.id == ^post.id),
      set: [inserted_at: inserted_at, updated_at: inserted_at]
    )

    {:ok, _comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "Take your time with the common route."
      })

    {:ok, view, html} =
      live(conn, ~p"/vn/full-metal-daemon-muramasa/discussions/#{post.short_id}")

    assert html =~ "Route order for Muramasa"
    assert html =~ "How should I approach the "
    assert html =~ "<strong>routes</strong>"
    assert html =~ "data-spoiler"
    assert html =~ "Full Metal Daemon Muramasa"
    assert html =~ "VN Thread Author"
    assert html =~ "VN Reply Author"
    assert html =~ "Take your time with the common route."

    post_timestamp = render(element(view, "article time"))
    assert post_timestamp =~ "3h"
  end

  test "focused comment links render the comment as the local root with direct replies", %{
    conn: conn
  } do
    author = UserFixtures.insert_user!(username: "focus_author")
    commenter = UserFixtures.insert_user!(username: "focus_commenter")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Focused comment thread",
        content: "A post with several branches.",
        category_type: :general
      })

    {:ok, focused} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "This is the shared parent."
      })

    {:ok, _child} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: focused.id,
        content: "This direct reply should load."
      })

    {:ok, _sibling} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "This sibling should stay hidden in focus mode."
      })

    {:ok, _view, html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{focused.short_id}")

    assert html =~ "Showing a shared comment and its replies."
    assert html =~ "View full discussion"
    assert html =~ "This is the shared parent."
    assert html =~ "This direct reply should load."
    refute html =~ "This sibling should stay hidden in focus mode."
    refute html =~ ~s(id="comments-top-form")
    assert html =~ ~s(id="comment-#{focused.id}-share")

    frontend_url = frontend_url()

    assert html =~
             ~s(data-share-url="#{frontend_url}/discussions/p/#{post.short_id}/#{post.slug}/c/#{focused.short_id}")
  end

  test "discussion pages keep late replies with their parents and reveal a newly posted reply", %{
    conn: conn
  } do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Whole comment threads",
        content: "Replies should stay with their parents.",
        category_type: :general
      })

    roots =
      for index <- 1..21 do
        {:ok, comment} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            content: "Root #{index}"
          })

        comment
      end

    parent =
      Enum.reduce(1..3, hd(roots), fn depth, parent ->
        {:ok, reply} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            parent_comment_id: parent.id,
            content: "Nested reply #{depth}"
          })

        reply
      end)

    children =
      for index <- 1..3 do
        {:ok, reply} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            parent_comment_id: parent.id,
            content: "Existing child #{index}"
          })

        reply
      end

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})
    path = "/discussions/p/#{post.short_id}/#{post.slug}"
    {:ok, view, _html} = live(conn, path <> "?comment_sort=oldest")

    assert has_element?(view, "#comment-#{parent.id}")
    refute has_element?(view, "#comment-#{Enum.at(roots, -1).id}")
    render_click(element(view, "#comment-thread-#{parent.id}-expand"))

    for child <- children, do: assert(has_element?(view, "#comment-#{child.id}"))

    render_click(element(view, "#comment-#{parent.id}-reply"))

    render_submit(element(view, "#comment-#{parent.id}-reply-form"), %{
      "content" => "Fourth child is visible immediately",
      "parent_comment_id" => parent.id
    })

    newest =
      Repo.get_by!(Kaguya.Discussions.Comment, content: "Fourth child is visible immediately")

    assert has_element?(view, "#comment-#{newest.id}")

    {:ok, refreshed, _html} = live(conn, path <> "?comment_sort=oldest")
    render_click(element(refreshed, "#comment-thread-#{parent.id}-expand"))

    render_click(
      element(
        refreshed,
        "#comment-thread-#{parent.id}-children > div > button",
        "Show 1 more reply"
      )
    )

    assert has_element?(refreshed, "#comment-#{newest.id}")

    {:ok, second_page, _html} = live(conn, path <> "?comment_sort=oldest&page=2")
    assert has_element?(second_page, "#comment-#{Enum.at(roots, -1).id}")
    refute has_element?(second_page, "#comment-#{parent.id}")
  end

  test "comment sorts rank roots, preserve pins and reply order, and survive pagination", %{
    conn: conn
  } do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Sort comment threads",
        content: "Independent answers with chronological replies.",
        category_type: :general
      })

    roots =
      for index <- 1..22 do
        insert_sort_comment!(post, author, "Answer #{index}", %{
          inserted_at: DateTime.add(~U[2026-01-01 00:00:00Z], index, :second),
          likes_count: if(index == 21, do: 10, else: 0)
        })
      end

    pinned = Enum.at(roots, 21)
    {:ok, _} = Discussions.admin_moderate_comment(pinned.id, %{is_pinned: true})
    winner = Enum.at(roots, 20)

    early_reply =
      insert_sort_comment!(post, author, "Earlier reply", %{
        parent_comment_id: winner.id,
        inserted_at: ~U[2026-01-02 00:00:00Z]
      })

    later_reply =
      insert_sort_comment!(post, author, "Later popular reply", %{
        parent_comment_id: winner.id,
        inserted_at: ~U[2026-01-03 00:00:00Z],
        likes_count: 100
      })

    path = "/discussions/p/#{post.short_id}/#{post.slug}"
    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "#discussion-comments-sort-top[aria-current=true]")
    assert comment_root_ids(view) |> Enum.take(3) == [pinned.id, winner.id, Enum.at(roots, 19).id]

    children = "#comment-thread-#{winner.id}-children"
    assert has_element?(view, "#{children} > div:first-child #comment-#{early_reply.id}")
    assert has_element?(view, "#{children} > div:last-child #comment-#{later_reply.id}")

    # A vote changes the count without moving the answer while someone is reading.
    conn_with_user = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})
    {:ok, signed_in, _html} = live(conn_with_user, path)
    before_vote = comment_root_ids(signed_in)
    render_click(element(signed_in, "#comment-#{Enum.at(roots, 1).id}-like"))
    assert comment_root_ids(signed_in) == before_vote

    render_click(element(view, "#comment-thread-#{winner.id}-toggle"))
    refute has_element?(view, "#comment-#{early_reply.id}")

    for {sort, first_id} <- [{"newest", winner.id}, {"oldest", hd(roots).id}, {"top", winner.id}] do
      assert has_element?(
               view,
               "#discussion-comments-sort-#{sort}[href='#{path}?comment_sort=#{sort}']"
             )

      render_click(element(view, "#discussion-comments-sort-#{sort}"))
      assert_patch(view, path <> "?comment_sort=#{sort}")
      assert comment_root_ids(view) |> Enum.take(2) == [pinned.id, first_id]
      if sort != "oldest", do: assert(has_element?(view, "#comment-#{early_reply.id}"))

      assert has_element?(
               view,
               "nav[aria-label='Comments pagination'] a[href='#{path}?comment_sort=#{sort}&page=2#comments']"
             )
    end

    render_patch(view, path <> "?comment_sort=newest&page=2")
    render_click(element(view, "#discussion-comments-sort-oldest"))
    assert_patch(view, path <> "?comment_sort=oldest")
    assert has_element?(view, "#comment-#{hd(roots).id}")

    for sort <- ["newest", "oldest", "top", "invalid"] do
      {:ok, refreshed, _html} = live(conn, path <> "?comment_sort=#{sort}")
      selected = if sort == "invalid", do: "top", else: sort
      assert has_element?(refreshed, "#discussion-comments-sort-#{selected}[aria-current=true]")
    end

    {:ok, focused, _html} = live(conn, path <> "/c/#{winner.short_id}?comment_sort=top")
    refute has_element?(focused, "#discussion-comments-sort-trigger")
    assert has_element?(focused, "#comment-#{early_reply.id}")
    assert has_element?(focused, "#comment-#{later_reply.id}")
  end

  test "equal comment scores and timestamps use IDs to keep page boundaries stable" do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Stable sort ties",
        content: "All answers have the same score and timestamp.",
        category_type: :general
      })

    comments =
      for index <- 1..3 do
        insert_sort_comment!(post, author, "Tied answer #{index}", %{
          inserted_at: ~U[2026-01-01 00:00:00Z]
        })
      end

    ids = comments |> Enum.map(& &1.id) |> Enum.sort()

    for sort <- [:most_liked, :oldest, :newest] do
      expected = if sort == :oldest, do: ids, else: Enum.reverse(ids)

      actual =
        for page <- 1..3 do
          {:ok, %{items: [comment]}} =
            Discussions.list_comments_for_post(post.id, 3, %{
              page: page,
              page_size: 1,
              sort_by: sort
            })

          comment.id
        end

      assert actual == expected
    end
  end

  defp comment_root_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#discussion-comments .comments-list > [data-comment-thread-id]")
    |> LazyHTML.attribute("data-comment-thread-id")
  end

  defp insert_sort_comment!(post, user, content, attrs) do
    %Comment{}
    |> Comment.changeset(%{post_id: post.id, user_id: user.id, content: content})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  test "focused child comments do not load ancestors", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "child_focus_author")
    commenter = UserFixtures.insert_user!(username: "child_focus_commenter")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Focused child comment thread",
        content: "A post with nested replies.",
        category_type: :general
      })

    {:ok, parent} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Ancestor should not load."
      })

    {:ok, child} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        parent_comment_id: parent.id,
        content: "Focused child should load."
      })

    {:ok, _grandchild} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: child.id,
        content: "Direct reply to focused child should load."
      })

    {:ok, _view, html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{child.short_id}")

    refute html =~ "Ancestor should not load."
    assert html =~ "Focused child should load."
    assert html =~ "Direct reply to focused child should load."
  end

  test "focused comment descendant loading is bounded" do
    author = UserFixtures.insert_user!(username: "bounded_focus_author")
    commenter = UserFixtures.insert_user!(username: "bounded_focus_commenter")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Bounded focused comment thread",
        content: "A post with a very deep branch.",
        category_type: :general
      })

    {:ok, focused} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "Shared root for bounded replies."
      })

    comments =
      Enum.map(1..3, fn index ->
        {:ok, comment} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            parent_comment_id: focused.id,
            content: "Bounded reply #{index}"
          })

        comment
      end)

    assert {:ok, %{items: items, pagination: pagination}} =
             Discussions.list_comment_descendants_for_comment(post.id, focused.id, %{limit: 2})

    expected_ids = comments |> Enum.take(2) |> Enum.map(& &1.id)

    assert Enum.map(items, & &1.id) == expected_ids
    assert pagination.truncated?
  end

  test "focused comment links show when replies are truncated", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "truncated_focus_author")
    commenter = UserFixtures.insert_user!(username: "truncated_focus_commenter")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Truncated focused comment thread",
        content: "A post with many direct replies.",
        category_type: :general
      })

    {:ok, focused} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: commenter.id,
        content: "Shared root with many replies."
      })

    Enum.each(1..201, fn index ->
      {:ok, _comment} =
        Discussions.create_comment(%{
          post_id: post.id,
          user_id: author.id,
          parent_comment_id: focused.id,
          content: "Truncated reply #{index}"
        })
    end)

    {:ok, _view, html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{focused.short_id}")

    assert html =~ "Showing a shared comment and its replies"
    assert html =~ "(limited)"
    refute html =~ "Truncated reply 201"
  end

  test "focused comment recovery clears stale error after returning to full discussion", %{
    conn: conn
  } do
    author = UserFixtures.insert_user!(username: "focus_recovery_author")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Focused recovery thread",
        content: "A post with a recoverable focused link.",
        category_type: :general
      })

    {:ok, _comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Full thread comment."
      })

    missing_short_id = "deadbeef"

    {:ok, view, html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{missing_short_id}")

    assert html =~ "Comment not found."
    assert html =~ "This shared comment could not be loaded."

    html =
      view
      |> element("#focused-comment-recovery a", "View full discussion")
      |> render_click()

    refute html =~ "Comment not found."
    assert html =~ "Full thread comment."
  end

  test "focused hidden comments follow discussion moderator visibility", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "hidden_focus_author")
    moderator = UserFixtures.insert_user!(username: "hidden_focus_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Hidden focused comment thread",
        content: "A post with a hidden comment.",
        category_type: :general
      })

    {:ok, comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Moderator-only focused comment."
      })

    assert {:ok, 1} = Discussions.hide_comment(comment.id, %{reason: "Removed"})

    {:ok, _view, public_html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{comment.short_id}")

    assert public_html =~ "Comment not found."
    assert public_html =~ "This shared comment could not be loaded."
    assert public_html =~ "View full discussion"
    refute public_html =~ "Moderator-only focused comment."

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => moderator.id})

    {:ok, _view, mod_html} =
      live(conn, "/discussions/p/#{post.short_id}/#{post.slug}/c/#{comment.short_id}")

    assert mod_html =~ "Moderator-only focused comment."
    assert mod_html =~ "hidden"
  end

  test "discussion replies cannot target a parent comment from another post" do
    author = UserFixtures.insert_user!(username: "cross_post_author")
    other = UserFixtures.insert_user!(username: "cross_post_other")

    {:ok, first_post} =
      Discussions.create_post(author.id, %{
        title: "First post",
        content: "Parent lives here.",
        category_type: :general
      })

    {:ok, second_post} =
      Discussions.create_post(author.id, %{
        title: "Second post",
        content: "Reply should not attach here.",
        category_type: :general
      })

    {:ok, parent} =
      Discussions.create_comment(%{
        post_id: first_post.id,
        user_id: author.id,
        content: "Parent from first post."
      })

    assert {:error, :parent_not_in_post} =
             Discussions.create_comment(%{
               post_id: second_post.id,
               user_id: other.id,
               parent_comment_id: parent.id,
               content: "This should fail."
             })
  end

  test "discussion replies cannot target hidden parent comments" do
    author = UserFixtures.insert_user!(username: "hidden_parent_author")
    other = UserFixtures.insert_user!(username: "hidden_parent_other")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Hidden parent post",
        content: "Replies should not attach to hidden parents.",
        category_type: :general
      })

    {:ok, parent} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Hidden parent comment."
      })

    assert {:ok, 1} = Discussions.hide_comment(parent.id, %{reason: "Removed"})

    assert {:error, "Cannot reply to a hidden comment"} =
             Discussions.create_comment(%{
               post_id: post.id,
               user_id: other.id,
               parent_comment_id: parent.id,
               content: "This should fail."
             })
  end

  test "discussion moderators see Pin/Lock/Hide on the post actions menu", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "post_menu_author")
    moderator = UserFixtures.insert_user!(username: "post_menu_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Moderator-visible post",
        content: "Mods should see Pin/Lock/Hide here.",
        category_type: :general
      })

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => moderator.id})

    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    assert html =~ ~s(id="post-#{post.id}-actions-trigger")
    assert dropdown_event?(html, "toggle_pin_post")
    assert dropdown_event?(html, "toggle_lock_post")
    assert dropdown_event?(html, "start_hide_post")
    # Mod is not the author, so Delete (admin) should be present too.
    assert dropdown_event?(html, "confirm_delete_post")
  end

  test "site admins see Pin/Lock/Hide on the post actions menu without mod_discussions flag",
       %{conn: conn} do
    author = UserFixtures.insert_user!(username: "admin_menu_author")

    admin =
      UserFixtures.insert_user!(username: "admin_menu_admin")
      |> then(fn user ->
        {:ok, updated} =
          user
          |> Ecto.Changeset.change(role: :admin)
          |> Repo.update()

        updated
      end)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Admin-visible post",
        content: "Admins inherit mod rights without the explicit flag.",
        category_type: :general
      })

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => admin.id})
    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    assert dropdown_event?(html, "toggle_pin_post")
    assert dropdown_event?(html, "toggle_lock_post")
    assert dropdown_event?(html, "start_hide_post")
    assert dropdown_event?(html, "confirm_delete_post")
  end

  test "post owners see Edit + Delete (no mod actions) on their own post", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "post_menu_owner")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Owner-visible post",
        content: "Owner can edit/delete but not pin/hide.",
        category_type: :general
      })

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})

    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    assert dropdown_event?(html, "start_edit_post")
    assert dropdown_event?(html, "confirm_delete_post")
    refute dropdown_event?(html, "toggle_pin_post")
    refute dropdown_event?(html, "toggle_lock_post")
    refute dropdown_event?(html, "start_hide_post")
  end

  test "pinned comments show a pin icon and moderator comments show a MOD badge",
       %{conn: conn} do
    author = UserFixtures.insert_user!(username: "indicators_author")
    moderator = UserFixtures.insert_user!(username: "indicators_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Indicators thread",
        content: "Pin icon + MOD badge should render.",
        category_type: :general
      })

    {:ok, mod_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: moderator.id,
        content: "PINNED_MOD_COMMENT_BODY"
      })

    {:ok, _author_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "REGULAR_AUTHOR_COMMENT_BODY"
      })

    {:ok, _} = Discussions.admin_moderate_comment(mod_comment.id, %{is_pinned: true})

    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    # MOD badge appears in the header of the mod's comment, not the author's.
    assert html =~ "MOD"
    # Pin icon (lucide pin) renders next to the username of the pinned comment.
    # The svg ships with a `lucide-pin` class from lucide-static; assert that
    # it shows up on the page when a comment is pinned.
    assert html =~ "lucide-pin"
  end

  test "soft-deleted comments no longer render after refresh", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "delete_refresh_author")

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Delete refresh thread",
        content: "Deleted comments should vanish on next load.",
        category_type: :general
      })

    {:ok, comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "GONE_AFTER_DELETE_BODY"
      })

    {:ok, true} = Discussions.delete_comment(comment.id, author.id)

    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    refute html =~ "GONE_AFTER_DELETE_BODY"
  end

  test "a pinned comment renders above older unpinned comments", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "pin_order_author")
    moderator = UserFixtures.insert_user!(username: "pin_order_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Pin ordering thread",
        content: "Pinned comments should hop to the top of the list.",
        category_type: :general
      })

    {:ok, first} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "FIRST_OLDER_COMMENT_BODY"
      })

    {:ok, second} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "SECOND_NEWER_COMMENT_BODY"
      })

    # Pin the second (newer) comment.
    assert {:ok, _} =
             Discussions.admin_moderate_comment(second.id, %{is_pinned: true})

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => moderator.id})
    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    # The pinned (second) comment's body should appear earlier in the
    # rendered HTML than the unpinned (first) comment's body.
    pinned_pos = :binary.match(html, "SECOND_NEWER_COMMENT_BODY") |> elem(0)
    unpinned_pos = :binary.match(html, "FIRST_OLDER_COMMENT_BODY") |> elem(0)
    assert pinned_pos < unpinned_pos
    # And the pinned comment's Unpin button should be present (mod view).
    assert dropdown_event_for_id?(html, "unpin_comment", second.id)

    refute dropdown_event_for_id?(html, "unpin_comment", first.id)
  end

  test "clicking Pin on a top-level comment actually pins it", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "pin_click_author")
    moderator = UserFixtures.insert_user!(username: "pin_click_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Pin click thread",
        content: "Confirm the click actually flips the DB row.",
        category_type: :general
      })

    {:ok, top_level} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Pin me for real."
      })

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => moderator.id})
    {:ok, view, _html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    view
    |> with_target("#discussion-comments")
    |> render_click("pin_comment", %{"id" => top_level.id})

    assert %{is_pinned: true} = Repo.get!(Kaguya.Discussions.Comment, top_level.id)
  end

  test "moderators see the Pin action on top-level comments only", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "comment_pin_author")
    moderator = UserFixtures.insert_user!(username: "comment_pin_mod")
    moderator = promote_discussion_moderator(moderator)

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Comment pin thread",
        content: "Mods can pin top-level comments here.",
        category_type: :general
      })

    {:ok, top_level} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Top-level — pinnable."
      })

    {:ok, reply} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: top_level.id,
        content: "Reply — not pinnable."
      })

    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => moderator.id})

    {:ok, _view, html} = live(conn, "/discussions/p/#{post.short_id}/#{post.slug}")

    # Top-level: Pin button present, scoped to that comment id.
    assert dropdown_event_for_id?(html, "pin_comment", top_level.id)

    # Reply: no Pin button at all (pin_eligible is false because of parent_comment_id).
    refute dropdown_event_for_id?(html, "pin_comment", reply.id)
  end

  defp promote_discussion_moderator(user) do
    Repo.update_all(
      from(u in Kaguya.Users.User, where: u.id == ^user.id),
      set: [mod_discussions: true]
    )

    Repo.get!(Kaguya.Users.User, user.id)
  end

  defp create_ordered_post!(index, title) do
    author =
      UserFixtures.insert_user!(
        username: "discussion_author_#{index}",
        display_name: "Discussion Author #{index}"
      )

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: title,
        content: "Discussion body #{index}",
        category_type: :general
      })

    timestamp =
      DateTime.utc_now()
      |> DateTime.add(-index, :minute)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(p in Post, where: p.id == ^post.id),
      set: [inserted_at: timestamp, updated_at: timestamp, last_comment_at: timestamp]
    )

    Repo.get!(Post, post.id)
  end

  defp frontend_url do
    :kaguya
    |> Application.fetch_env!(:frontend_url)
    |> String.trim_trailing("/")
  end

  defp dropdown_event?(html, event) do
    html =~ ~s(&quot;event&quot;:&quot;#{event}&quot;)
  end

  defp dropdown_event_for_id?(html, event, id) do
    Regex.match?(
      ~r/&quot;id&quot;:&quot;#{Regex.escape(id)}&quot;[^\[]*&quot;event&quot;:&quot;#{event}&quot;/,
      html
    )
  end

  test "new post composer changes topic without clearing it", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "composer_author", display_name: "Composer")
    conn = Plug.Test.init_test_session(conn, %{"current_user_id" => author.id})

    {:ok, view, _html} = live(conn, ~p"/discussions")
    render_click(view, "open_new_post")

    assert has_element?(view, "#new-post-title[autocomplete=off]")
    assert has_element?(view, "#new-post-topic", "General")
    assert has_element?(view, "#new-post-body-editor [data-markdown-spoiler]")

    view |> element("#new-post-topic") |> render_click()

    assert has_element?(view, "#new-post-topic-search")
    assert has_element?(view, "#new-post-topic-results [role=group][aria-label=Topics]")
    refute has_element?(view, "#new-post-dialog button[type=submit][disabled]")

    view |> element("#new-post-topic-cancel") |> render_click()

    assert has_element?(view, "#new-post-topic", "General")
    refute has_element?(view, "#new-post-topic-results")
  end

  test "VN links on their own line render as cover cards in posts and comments", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "card_author", display_name: "Card Author")

    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "Full Metal Daemon Muramasa",
      slug: "full-metal-daemon-muramasa",
      description: "A" <> String.duplicate(" test visual novel description", 3)
    })
    |> Repo.insert!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Best VNs this year",
        content: "Mine:\n\n[Muramasa](/vn/full-metal-daemon-muramasa)",
        category_type: :general
      })

    {:ok, card_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "[Muramasa](/vn/full-metal-daemon-muramasa)"
      })

    {:ok, inline_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "I keep thinking about [Muramasa](/vn/full-metal-daemon-muramasa) lately."
      })

    {:ok, view, _html} = live(conn, ~p"/discussions/p/#{post.short_id}/#{post.slug}")

    card = "[data-vn-cards] a[href='/vn/full-metal-daemon-muramasa']"

    assert has_element?(view, "article #{card}", "Full Metal Daemon Muramasa")
    assert has_element?(view, "#comment-#{card_comment.id}-content #{card}")
    refute has_element?(view, "#comment-#{inline_comment.id}-content [data-vn-cards]")

    assert has_element?(
             view,
             "#comment-#{inline_comment.id}-content a[href='/vn/full-metal-daemon-muramasa']"
           )
  end
end

defmodule KaguyaWeb.VNLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Discussions
  alias Kaguya.Lists
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.Release
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Ratings
  alias Kaguya.Reviews.Review
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Shelves
  alias Kaguya.Social
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VisualNovels.VNTag
  alias Kaguya.VNTags.VNTagVote
  alias Kaguya.Test.UserFixtures

  # The VN-page core is cached per VN (`:vn_page_cache`). Clear it between
  # tests so a payload assembled in one test never serves another.
  setup do
    Cachex.clear(:vn_page_cache)
    :ok
  end

  test "renders a VN page from direct contexts", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Test VN",
        slug: "test-vn",
        description: "A" <> String.duplicate(" test visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, _view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert html =~ "Test VN"
    assert html =~ "Reviews"
    assert html =~ "Nothing recommended yet"
    assert html =~ "Sign in"
  end

  test "media galleries are noindex,follow; main page and quotes stay indexable",
       %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Robots VN",
        slug: "robots-vn",
        description: "A short description for the robots test."
      })
      |> Repo.insert!()

    # Meta tags live in the document <head> (the layout), which is only present
    # in the static render — so assert against the HTTP response, not the
    # connected LiveView render.
    covers = conn |> get(~p"/vn/#{vn.slug}/covers") |> html_response(200)
    assert covers =~ ~s(<meta name="robots" content="noindex,follow")

    screenshots = conn |> get(~p"/vn/#{vn.slug}/screenshots") |> html_response(200)
    assert screenshots =~ ~s(<meta name="robots" content="noindex,follow")

    main = conn |> get(~p"/vn/#{vn.slug}") |> html_response(200)
    refute main =~ ~s(name="robots" content="noindex)

    quotes = conn |> get(~p"/vn/#{vn.slug}/quotes") |> html_response(200)
    refute quotes =~ ~s(name="robots" content="noindex)
  end

  test "renders developer producer links and hides publishers when developers exist", %{
    conn: conn
  } do
    suffix = System.unique_integer([:positive])

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Developer Link Test",
        slug: "developer-link-test-#{suffix}",
        description: "A" <> String.duplicate(" developer link visual novel description", 3)
      })
      |> Repo.insert!()

    developer =
      %Producer{}
      |> Producer.changeset(%{
        name: "Linked Developer #{suffix}",
        slug: "linked-developer-#{suffix}"
      })
      |> Repo.insert!()

    publisher =
      %Producer{}
      |> Producer.changeset(%{
        name: "Hidden Publisher #{suffix}",
        slug: "hidden-publisher-#{suffix}"
      })
      |> Repo.insert!()

    %VNProducer{}
    |> VNProducer.changeset(%{
      visual_novel_id: vn.id,
      producer_id: developer.id,
      role: "developer"
    })
    |> Repo.insert!()

    %VNProducer{}
    |> VNProducer.changeset(%{
      visual_novel_id: vn.id,
      producer_id: publisher.id,
      role: "publisher"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert html =~ "Linked Developer #{suffix}"
    assert html =~ ~s(href="/developer/linked-developer-#{suffix}")
    refute html =~ ~s(href="/developer/hidden-publisher-#{suffix}")
  end

  test "shared auth prompt can set action-specific messages", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Auth Prompt VN",
        slug: "auth-prompt-vn",
        description: "A" <> String.duplicate(" auth prompt visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert html =~ ~s(id="vn-auth-prompt")
    assert html =~ ~s(href="/login?redirectTo=%2Fvn%2Fauth-prompt-vn")

    html = render_click(view, "show_auth_prompt", %{"message" => "Sign in to like reviews"})

    assert html =~ "Sign in to like reviews"
  end

  test "signed-in users can view reviews from followed users", %{conn: conn} do
    viewer = UserFixtures.insert_user!()
    friend = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Friend Review VN",
        slug: "friend-review-vn",
        description: "A" <> String.duplicate(" friend review visual novel description", 3)
      })
      |> Repo.insert!()

    assert {:ok, true} = Social.follow_user(viewer.id, friend.id)

    assert {:ok, review} =
             Reviews.create_review(friend.id, vn.id, %{
               content: "This friend review is long enough to satisfy the review validation."
             })

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => viewer.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    assert has_element?(view, "#friend-review-#{review.id}")
  end

  test "signed-in users can view activity from followed users", %{conn: conn} do
    viewer = UserFixtures.insert_user!()
    friend = UserFixtures.insert_user!(display_name: "Friend Activity User")

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Friend Activity VN",
        slug: "friend-activity-vn",
        description: "A" <> String.duplicate(" friend activity visual novel description", 3)
      })
      |> Repo.insert!()

    assert {:ok, true} = Social.follow_user(viewer.id, friend.id)
    assert {:ok, _status} = Shelves.set_reading_status(friend.id, vn.id, %{status: :read})
    assert {:ok, _rating} = Ratings.create_rating(friend.id, vn.id, 4.0)

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => viewer.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    assert has_element?(view, "#friend-activity-#{friend.id}")
    html = render(view)
    assert html =~ "Activity from Friends"
    assert html =~ "1 Read"
  end

  test "renders popular lists that contain the VN", %{conn: conn} do
    owner =
      UserFixtures.insert_user!(
        username: "popular_list_owner",
        display_name: "Popular List Owner"
      )

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Popular List VN",
        slug: "popular-list-vn",
        description: "A" <> String.duplicate(" popular list visual novel description", 3)
      })
      |> Repo.insert!()

    assert {:ok, list} =
             Lists.create_list(%{
               user_id: owner.id,
               name: "Popular VN Picks",
               description: "Public list that includes the VN.",
               vn_ids: [vn.id]
             })

    {:ok, view, _html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert has_element?(view, "#popular-list-#{list.id}")
    html = render(view)
    assert html =~ "Popular VN Picks"
    assert html =~ "Popular List Owner"
    assert html =~ ~s(href="/@#{owner.username}/list/#{list.slug}")
  end

  test "renders VN-scoped discussions", %{conn: conn} do
    author =
      UserFixtures.insert_user!(
        username: "vn_discussion_author",
        display_name: "VN Discussion Author"
      )

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Discussion Branch VN",
        slug: "discussion-branch-vn",
        description: "A" <> String.duplicate(" discussion branch visual novel description", 3)
      })
      |> Repo.insert!()

    assert {:ok, post} =
             Discussions.create_post(author.id, %{
               title: "A VN branch discussion",
               content: "Discussion content long enough for the VN scoped discussion fixture.",
               category_type: :visual_novel,
               entity_id: vn.id
             })

    {:ok, view, _html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert has_element?(view, "#vn-discussion-#{post.id}")
    html = render(view)
    assert html =~ "A VN branch discussion"
    assert html =~ "VN Discussion Author"
    assert html =~ ~s(href="/vn/#{vn.slug}/discussions/#{post.short_id}")
  end

  test "review date picker clears a selected single date when clicked again", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Review Date Toggle VN",
        slug: "review-date-toggle-vn",
        description: "A" <> String.duplicate(" review date toggle visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    html = render_click(view, "open_review_dialog")
    assert html =~ "Add dates"

    # The picker LiveComponent renders inside a server-gated disclosure panel
    # (`:if={@date_picker_open?}`) — the DOM is present in tests once toggled,
    # so we can drive the calendar directly. Shift back to Jan 2024 and click
    # 2 Jan.
    render_click(view, "toggle_review_date_picker")
    shift_picker_to(view, ~D[2024-01-01])

    render_click(element(view, "#review-date-range-picker button[phx-value-date='2024-01-02']"))
    html = render(view)

    assert html =~ ~s(name="review[date_finished]" value="2024-01-02")
    assert html =~ "2 Jan 2024"

    # Clicking the same day again clears the date.
    render_click(element(view, "#review-date-range-picker button[phx-value-date='2024-01-02']"))
    html = render(view)

    assert html =~ ~s(name="review[date_finished]" value="")
    assert html =~ "Add dates"
    refute html =~ "2 Jan 2024"
  end

  defp shift_picker_to(view, %Date{} = target) do
    today = Date.utc_today()
    delta = (target.year - today.year) * 12 + (target.month - today.month)
    btn = if delta < 0, do: "aria-label='Previous month'", else: "aria-label='Next month'"

    for _ <- 1..abs(delta) do
      render_click(element(view, "#review-date-range-picker button[#{btn}]"))
    end
  end

  test "remove VN asks for confirmation before clearing activity", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Remove VN Confirm Test",
        slug: "remove-vn-confirm-test",
        description: "A" <> String.duplicate(" remove vn confirm visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    render_click(view, "set_status", %{"status" => "READ"})

    assert Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)

    html = render_click(view, "clear_status")

    assert html =~ "Delete all activity for this VN?"

    assert html =~
             "Your review, rating, reading status, and shelf entries will be permanently removed."

    assert Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)

    html = render_click(view, "close_clear_status_dialog")

    refute html =~ "Delete all activity for this VN?"
    assert Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)

    render_click(view, "clear_status")
    html = render_click(view, "confirm_clear_status")

    refute html =~ "Delete all activity for this VN?"
    refute Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id)
  end

  test "signed-in users can vote and clear VN tag votes", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Tag Vote Test",
        slug: "tag-vote-test",
        description: "A" <> String.duplicate(" tag vote visual novel description", 3)
      })
      |> Repo.insert!()

    tag =
      %Tag{}
      |> Tag.changeset(%{
        name: "Comedy",
        slug: "comedy",
        category: :content,
        kind: :genre
      })
      |> Repo.insert!()

    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      vndb_vote_count: 10,
      vndb_avg_score: 2.0,
      relevance_score: 0.8,
      spoiler_level: :none
    })
    |> Repo.insert!()

    {:ok, view, html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    assert html =~ "Vote on Comedy"
    assert html =~ ~s(phx-value-vote="4")

    html = render_click(view, "vote_tag", %{"tag-id" => tag.id, "vote" => "4"})

    assert %VNTagVote{value: 4} =
             Repo.get_by(VNTagVote,
               user_id: user.id,
               visual_novel_id: vn.id,
               tag_id: tag.id
             )

    assert html =~ "Clear vote"
    assert html =~ ~s(aria-pressed="true")

    render_click(view, "clear_tag_vote", %{"tag-id" => tag.id})

    refute Repo.get_by(VNTagVote,
             user_id: user.id,
             visual_novel_id: vn.id,
             tag_id: tag.id
           )
  end

  test "signed-in users can search and add VN tags", %{conn: conn} do
    user = UserFixtures.insert_user!()
    suffix = System.unique_integer([:positive])

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Add Tag Test #{suffix}",
        slug: "add-tag-test-#{suffix}",
        description: "A" <> String.duplicate(" add tag visual novel description", 3)
      })
      |> Repo.insert!()

    source_vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Add Tag Source #{suffix}",
        slug: "add-tag-source-#{suffix}",
        description: "A" <> String.duplicate(" add tag source description", 3)
      })
      |> Repo.insert!()

    candidate_tag =
      %Tag{}
      |> Tag.changeset(%{
        name: "Romantic Comedy #{suffix}",
        slug: "romantic-comedy-#{suffix}",
        category: :content,
        kind: :genre
      })
      |> Repo.insert!()

    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: source_vn.id,
      tag_id: candidate_tag.id,
      vndb_vote_count: 20,
      vndb_avg_score: 2.2,
      relevance_score: 0.82,
      spoiler_level: :none
    })
    |> Repo.insert!()

    {:ok, view, html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    assert html =~ ~s(phx-click="open_tag_dialog")

    html = render_click(view, "open_tag_dialog")
    assert html =~ "Add tag"
    assert html =~ "Search tags..."

    html =
      render_change(view, "search_tags", %{
        "tag_search" => %{"query" => "romantic"}
      })

    assert html =~ "Romantic Comedy #{suffix}"
    assert html =~ "Content"

    html = render_click(view, "add_tag", %{"tag-id" => candidate_tag.id})

    assert %VNTagVote{value: 4} =
             Repo.get_by(VNTagVote,
               user_id: user.id,
               visual_novel_id: vn.id,
               tag_id: candidate_tag.id
             )

    refute html =~ "tag-dialog"
  end

  test "renders releases tab without requiring optional release flags", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Release Test",
        slug: "release-test",
        description: "A" <> String.duplicate(" release visual novel description", 3)
      })
      |> Repo.insert!()

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: "Windows English Edition",
      release_date: ~D[2020-01-02],
      platforms: ["win"],
      languages: ["en"]
    })
    |> Repo.insert!()

    {:ok, view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    refute html =~ "Windows English Edition"

    render_click(view, "switch_tab", %{"tab" => "releases"})
    assert render_async(view) =~ "Windows English Edition"
  end

  test "renders character cards without requiring image variants", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Character Test",
        slug: "character-test",
        description: "A" <> String.duplicate(" character visual novel description", 3)
      })
      |> Repo.insert!()

    character =
      %Character{}
      |> Character.changeset(%{name: "Makise Kurisu"})
      |> Repo.insert!()

    %VNCharacter{}
    |> VNCharacter.changeset(%{
      visual_novel_id: vn.id,
      character_id: character.id,
      role: :main
    })
    |> Repo.insert!()

    {:ok, _view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert html =~ "Makise Kurisu"
  end

  test "release filters narrow visible releases", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Release Filter Test",
        slug: "release-filter-test",
        description: "A" <> String.duplicate(" release visual novel description", 3)
      })
      |> Repo.insert!()

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: "Windows English Edition",
      release_date: ~D[2020-01-02],
      platforms: ["win"],
      languages: ["en"]
    })
    |> Repo.insert!()

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: "Switch Japanese Edition",
      release_date: ~D[2021-01-02],
      platforms: ["swi"],
      languages: ["ja"]
    })
    |> Repo.insert!()

    {:ok, view, _html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    render_click(view, "switch_tab", %{"tab" => "releases"})
    html = render_async(view)
    assert html =~ "Windows English Edition"
    refute html =~ "Switch Japanese Edition"

    render_change(view, "set_release_filters", %{
      "release_filters" => %{"language" => "ja", "platform" => "swi"}
    })

    html = render_async(view)

    assert html =~ "Switch Japanese Edition"
    refute html =~ "Windows English Edition"
  end

  # Guards the connect-param seeding path: the saved preference is honored on
  # mount, so the panel renders the right release without the client pushing a
  # correction event. If a future change re-adds a `release_filters` reset in
  # mount/handle_params, this fails — which is exactly the regression that
  # brought back the prod-only flicker.
  test "saved release filter preference seeds the panel on connect", %{conn: conn} do
    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Seeded Filter Test",
        slug: "seeded-filter-test",
        description: "A" <> String.duplicate(" release visual novel description", 3)
      })
      |> Repo.insert!()

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: "Windows English Edition",
      release_date: ~D[2020-01-02],
      platforms: ["win"],
      languages: ["en"]
    })
    |> Repo.insert!()

    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: "Switch Japanese Edition",
      release_date: ~D[2021-01-02],
      platforms: ["swi"],
      languages: ["ja"]
    })
    |> Repo.insert!()

    conn =
      put_connect_params(conn, %{
        "release_filter_prefs" => Jason.encode!(%{language: "ja", platform: "swi"})
      })

    {:ok, view, _html} = live(conn, ~p"/vn/#{vn.slug}")
    render_async(view)

    render_click(view, "switch_tab", %{"tab" => "releases"})
    html = render_async(view)

    assert html =~ "Switch Japanese Edition"
    refute html =~ "Windows English Edition"
  end

  test "renders VN description as expanded markdown", %{conn: conn} do
    long_description =
      Enum.map_join(1..90, " ", fn _ -> "The quick brown fox jumps over the lazy dog." end)

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Description Toggle Test",
        slug: "description-toggle-test",
        description: long_description
      })
      |> Repo.insert!()

    {:ok, view, html} = live_and_wait(conn, ~p"/vn/#{vn.slug}")

    assert html =~ "The quick brown fox jumps over the lazy dog."
    refute html =~ ~s(phx-click="toggle_vn_description_desktop")
    refute html =~ ~s(phx-click="toggle_vn_description_mobile")

    assert render(view) =~ "The quick brown fox jumps over the lazy dog."
  end

  test "signed-in users can write and save a review", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Write Review Test",
        slug: "write-review-test",
        description: "A" <> String.duplicate(" write review visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    html = render_click(view, "open_review_dialog")
    assert html =~ "Write a review..."

    content = "This review is comfortably longer than the forty character minimum."

    html =
      render_submit(view, "save_review", %{
        "review" => %{"content" => content, "status" => "READ"}
      })

    # Dialog closes on a successful save.
    refute html =~ "Write a review..."

    assert %Review{content: ^content} =
             Repo.get_by(Review, visual_novel_id: vn.id, user_id: user.id)
  end

  test "saving a too-short review shows an inline error and persists nothing", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Short Review Test",
        slug: "short-review-test",
        description: "A" <> String.duplicate(" short review visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    render_click(view, "open_review_dialog")

    html =
      render_submit(view, "save_review", %{
        "review" => %{"content" => "too short", "status" => "READ"}
      })

    # Dialog stays open with the inline minimum-length error; nothing saved.
    assert html =~ "Review must be at least 40 characters"
    assert html =~ "Write a review..."
    refute Repo.get_by(Review, visual_novel_id: vn.id, user_id: user.id)
  end

  test "closing the review editor dismisses it without a discard confirmation", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Close Review Test",
        slug: "close-review-test",
        description: "A" <> String.duplicate(" close review visual novel description", 3)
      })
      |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    render_click(view, "open_review_dialog")
    # Mirror an in-progress edit so a stale dirty-check would have triggered the
    # old confirmation. Closing must still dismiss silently.
    render_change(view, "update_review_form", %{"review" => %{"content" => "work in progress"}})

    html = render_click(view, "close_review_dialog")

    refute html =~ "Write a review..."
    refute html =~ "Discard changes?"
  end

  test "users can delete an existing review through the confirmation dialog", %{conn: conn} do
    user = UserFixtures.insert_user!()

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{
        title: "Delete Review Test",
        slug: "delete-review-test",
        description: "A" <> String.duplicate(" delete review visual novel description", 3)
      })
      |> Repo.insert!()

    assert {:ok, _review} =
             Reviews.create_review(user.id, vn.id, %{
               content: "This existing review is long enough to satisfy the validation rules."
             })

    {:ok, view, _html} =
      conn
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})
      |> live_and_wait(~p"/vn/#{vn.slug}")

    render_click(view, "open_review_dialog")

    html = render_click(view, "open_review_delete_dialog")
    assert html =~ "Delete review?"
    assert html =~ "This action cannot be undone."
    # Confirmation alone doesn't delete.
    assert Repo.get_by(Review, visual_novel_id: vn.id, user_id: user.id)

    html = render_click(view, "delete_review")

    refute html =~ "Delete review?"
    refute html =~ "Write a review..."
    refute Repo.get_by(Review, visual_novel_id: vn.id, user_id: user.id)
  end

  defp live_and_wait(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {:ok, view, render_async(view)}
  end
end

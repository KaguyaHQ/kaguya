defmodule KaguyaWeb.ProfileLive.ActivityTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Activities
  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Social
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/activity" do
    test "renders the empty state when the user has no activity" do
      _user = UserFixtures.insert_user!(username: "quiet", display_name: "Quiet")

      {:ok, _view, html} = live(build_conn(), "/@quiet/activity")

      assert html =~ "No recent activity"
      # Header still renders (mobile compact row + inner nav strip).
      assert html =~ ~s(href="/@quiet")
      # No banner on inner tabs.
      refute html =~ ~s(alt="profile cover")
    end

    test "renders one row per recorded activity verb" do
      user =
        UserFixtures.insert_user!(username: "active", display_name: "Active User")

      vn_id = UUIDv7.generate()
      followee = UserFixtures.insert_user!(username: "followee", display_name: "Followee")

      # rated VN
      {:ok, _} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :rated,
          entity_type: "rating",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "vn_slug" => "fate-stay-night",
            "vn_title" => "Fate/stay night",
            "rating" => 4.5
          }
        })

      # liked a cover
      {:ok, _} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :liked_cover,
          entity_type: "cover",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "vn_slug" => "tsukihime",
            "vn_title" => "Tsukihime",
            "cover_url" => "https://images.kaguya.io/covers/tsuki.webp"
          }
        })

      # followed another user
      {:ok, _} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :followed,
          entity_type: "user",
          entity_id: followee.id,
          metadata: %{"followed_username" => "followee", "followed_display_name" => "Followee"}
        })

      # status_changed → wishlisted
      {:ok, _} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :status_changed,
          entity_type: "library_status",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "vn_slug" => "umineko",
            "vn_title" => "Umineko",
            "status" => "want_to_read",
            "vn_id" => vn_id
          }
        })

      {:ok, _view, html} = live(build_conn(), "/@active/activity")

      # Actor link appears once per row, but display name is rendered each row.
      assert html =~ ~s(href="/@active")
      # Verb-specific copy.
      assert html =~ "rated"
      assert html =~ "Fate/stay night"
      assert html =~ "liked a cover from"
      assert html =~ "Tsukihime"
      assert html =~ "followed"
      assert html =~ "Followee"
      assert html =~ "wishlisted"
      assert html =~ "Umineko"

      # No "Load older activity" button for a small feed.
      refute html =~ "Load older activity"
      # End-of-feed sentinel is rendered when has_next is false.
      assert html =~ "End of recent activity"
    end

    test "renders reviewed activity as the full VN review card" do
      user = UserFixtures.insert_user!(username: "reviewer", display_name: "Reviewer")
      vn = insert_vn!("Steins;Gate")

      {:ok, _review} =
        Reviews.create_review(user.id, vn.id, %{
          content: "This review has enough words to satisfy the minimum content validation."
        })

      {:ok, _view, html} = live(build_conn(), "/@reviewer/activity")

      assert html =~ "Reviewer"
      assert html =~ "reviewed"
      assert html =~ vn.title
      assert html =~ ~s(href="/@reviewer/reviews/#{vn.slug}")
      assert html =~ "This review has enough words"
      refute html =~ "reviewed <"
    end

    test "renders created_list activity as a list card with covers, action, and date" do
      user = UserFixtures.insert_user!(username: "lister", display_name: "Lister")
      vn = insert_vn!("List Cover VN")

      {:ok, list} =
        Lists.create_list(%{user_id: user.id, name: "Starter Picks", vn_ids: [vn.id]})

      {:ok, _view, html} = live(build_conn(), "/@lister/activity")

      assert html =~ "Lister"
      assert html =~ "listed"
      assert html =~ "Starter Picks"
      assert html =~ ~s(href="/@lister/list/#{list.slug}")
      assert html =~ vn.title
      refute html =~ "created a list"
    end

    test "renders post comments with discussion wording and links" do
      user = UserFixtures.insert_user!(username: "post_commenter", display_name: "Poster")

      {:ok, _activity} =
        Activities.record_activity(%{
          user_id: user.id,
          action: :commented,
          entity_type: "post_comment",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "parent_entity_type" => "post",
            "post_title" => "Spoiler policy discussion",
            "post_short_id" => "def67890",
            "post_slug" => "spoiler-policy-discussion",
            "text_preview" => "This is a discussion reply, not a review reply."
          }
        })

      {:ok, _view, html} = live(build_conn(), "/@post_commenter/activity")

      assert html =~ "commented on"
      assert html =~ "Spoiler policy discussion"
      assert html =~ "This is a discussion reply, not a review reply."
      assert html =~ ~s(href="/discussions/p/def67890/spoiler-policy-discussion")
      refute html =~ "commented on a review of a visual novel"
    end

    test "load_more_activity advances the cursor and appends rows" do
      user = UserFixtures.insert_user!(username: "prolific", display_name: "Prolific")

      # 25 activities → 2 pages at page_size=20.
      for n <- 1..25 do
        {:ok, _} =
          Activities.record_activity(%{
            user_id: user.id,
            action: :rated,
            entity_type: "rating",
            entity_id: UUIDv7.generate(),
            metadata: %{"vn_slug" => "vn-#{n}", "vn_title" => "VN #{n}", "rating" => 4}
          })
      end

      {:ok, view, html} = live(build_conn(), "/@prolific/activity")
      refute html =~ "Load older activity"
      assert html =~ ~s(phx-hook="ActivityAutoLoad")
      assert html =~ "Loading more activity"
      # First page only contains the most recent 20 items.
      refute html =~ "VN 1<"

      html_after = render_click(view, "load_more_activity")
      # After load_more we should have rendered the older items.
      assert html_after =~ "VN 1"
      # And the button is replaced by end-of-feed.
      assert html_after =~ "End of recent activity"
      refute html_after =~ "Load older activity"
    end

    test "shows explicit load older activity button after two pages are loaded" do
      user = UserFixtures.insert_user!(username: "threshold", display_name: "Threshold")

      for n <- 1..45 do
        {:ok, _} =
          Activities.record_activity(%{
            user_id: user.id,
            action: :rated,
            entity_type: "rating",
            entity_id: UUIDv7.generate(),
            metadata: %{
              "vn_slug" => "threshold-vn-#{n}",
              "vn_title" => "Threshold VN #{n}",
              "rating" => 4
            }
          })
      end

      {:ok, view, html} = live(build_conn(), "/@threshold/activity")
      refute html =~ "Load older activity"
      assert html =~ ~s(phx-hook="ActivityAutoLoad")
      assert html =~ "Loading more activity"

      html_after_auto_page = render_click(view, "load_more_activity")
      assert html_after_auto_page =~ "Load older activity"
      refute html_after_auto_page =~ ~s(phx-hook="ActivityAutoLoad")
    end

    test "renders the following sidebar with avatars when the user follows others" do
      user = UserFixtures.insert_user!(username: "social_user", display_name: "Social")
      friend = UserFixtures.insert_user!(username: "friend1", display_name: "Friend One")
      {:ok, _} = Social.follow_user(user.id, friend.id)

      {:ok, _view, html} = live(build_conn(), "/@social_user/activity")

      # Sidebar heading + count link both point to /following.
      assert html =~ ~s(href="/@social_user/following")
      assert html =~ "Following"
      # Avatar link to the followed user appears in the sidebar grid.
      assert html =~ ~s(href="/@friend1")
    end
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end

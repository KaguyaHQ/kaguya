defmodule Kaguya.ModerationReasonsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Discussions
  alias Kaguya.Discussions.{Comment, Post}
  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListComment}
  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.{Review, ReviewComment}
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.Comments.ReviewAdapter

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  test "post hide reasons are optional, exposed as public profile tombstones, and cleared on restore" do
    author = UserFixtures.insert_user!()
    moderator = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Spoiler policy thread",
        content: "Please keep endgame spoilers tagged.",
        category_type: :general
      })

    assert {:ok, hidden_without_reason} = Discussions.hide_post(post.id)
    assert hidden_without_reason.hidden_reason == nil

    assert {:ok, hidden} =
             Discussions.hide_post(post.id, %{
               reason: "Unmarked endgame spoilers",
               actor_id: moderator.id,
               add_comment: true,
               comment: "Kaguya does not allow unmarked endgame spoilers."
             })

    assert hidden.hidden_reason == "Unmarked endgame spoilers"

    removal_comment = Repo.get_by!(Comment, post_id: post.id, user_id: moderator.id)
    assert removal_comment.is_pinned == true
    assert removal_comment.content == "Kaguya does not allow unmarked endgame spoilers."

    {:ok, reply_to_removal} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: removal_comment.id,
        content: "Following up on the removal."
      })

    {:ok, _regular_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "A regular visible comment."
      })

    {:ok, %{items: [first_comment, first_reply | _]}} =
      Discussions.list_comments_for_post_cursor(post.id, %{
        viewer_id: other.id,
        sort_by: :most_liked,
        limit: 1
      })

    assert first_comment.id == removal_comment.id
    assert first_reply.id == reply_to_removal.id

    assert {:ok, %{items: [flat_first, flat_regular], has_next: true, next_cursor: cursor}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer_id: other.id,
               sort_by: :newest,
               limit: 1
             })

    assert cursor != nil
    assert flat_first.id == removal_comment.id
    assert flat_regular.id != removal_comment.id

    assert {:ok, %{items: [profile_post]}} =
             Discussions.list_posts_for_user(author.id, %{viewer_id: author.id})

    assert profile_post.id == post.id
    assert profile_post.title == "Spoiler policy thread"
    assert profile_post.content == nil
    assert profile_post.comments_count == 3
    assert profile_post.hidden_reason == "Unmarked endgame spoilers"

    assert {:ok, %{items: [public_post]}} =
             Discussions.list_posts_for_user(author.id, %{viewer_id: other.id})

    assert public_post.id == post.id
    assert public_post.user_id == author.id
    assert public_post.title == "Spoiler policy thread"
    assert public_post.content == nil
    assert public_post.comments_count == 3
    assert public_post.hidden_reason == "Unmarked endgame spoilers"

    assert {:ok, %{items: [logged_out_post]}} =
             Discussions.list_posts_for_user(author.id, %{viewer_id: nil})

    assert logged_out_post.id == post.id
    assert logged_out_post.title == "Spoiler policy thread"
    assert logged_out_post.content == nil
    assert logged_out_post.hidden_reason == "Unmarked endgame spoilers"

    assert {:ok, scrubbed_detail} = Discussions.get_post_by_short_id_for_view(post.short_id, nil)
    assert scrubbed_detail.title == "Spoiler policy thread"
    assert scrubbed_detail.content == nil
    assert scrubbed_detail.comments_count == 3

    assert {:ok, mod_detail} =
             Discussions.get_post_by_short_id_for_view(post.short_id, moderator.id, %{
               mod_discussions: true
             })

    assert mod_detail.title == "Spoiler policy thread"
    assert mod_detail.content == "Please keep endgame spoilers tagged."

    assert {:ok, locked} = Discussions.admin_lock_post(post.id)
    assert locked.is_locked == true

    assert {:ok, restored} = Discussions.unhide_post(post.id)
    assert restored.hidden_at == nil
    assert restored.hidden_reason == nil

    assert {:ok, unlocked} = Discussions.admin_unlock_post(post.id)
    assert unlocked.is_locked == false
  end

  test "moderators can pin up to three top-level post comments with newest pins first" do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Pinned comment thread",
        content: "Testing manual comment pinning.",
        category_type: :general
      })

    comments =
      for content <- ["First pin", "Second pin", "Third pin", "Fourth pin"] do
        {:ok, comment} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            content: content
          })

        comment
      end

    [first_comment, second_comment, third_comment, fourth_comment] = comments

    {:ok, reply} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: first_comment.id,
        content: "Do not pin replies"
      })

    for comment <- [first_comment, second_comment, third_comment] do
      assert {:ok, pinned} = Discussions.admin_moderate_comment(comment.id, %{is_pinned: true})
      assert pinned.is_pinned == true
      assert pinned.pinned_at != nil
    end

    assert {:ok, %{items: [third, second, first | _]}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer_id: author.id,
               sort_by: :newest,
               limit: 20
             })

    assert [third.id, second.id, first.id] ==
             Enum.map([third_comment, second_comment, first_comment], & &1.id)

    assert {:ok, fourth_pinned} =
             Discussions.admin_moderate_comment(fourth_comment.id, %{is_pinned: true})

    assert fourth_pinned.is_pinned == true
    assert Repo.get!(Comment, first_comment.id).is_pinned == false
    assert Repo.get!(Comment, second_comment.id).is_pinned == true
    assert Repo.get!(Comment, third_comment.id).is_pinned == true

    assert {:ok, %{items: [fourth, third, second | _]}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer_id: author.id,
               sort_by: :newest,
               limit: 20
             })

    assert Enum.map([fourth, third, second], & &1.id) == [
             fourth_comment.id,
             third_comment.id,
             second_comment.id
           ]

    assert {:error, "Only top-level comments can be pinned"} =
             Discussions.admin_moderate_comment(reply.id, %{is_pinned: true})

    assert {:ok, unpinned} =
             Discussions.admin_moderate_comment(fourth_comment.id, %{is_pinned: false})

    assert unpinned.is_pinned == false
    assert unpinned.pinned_at == nil
  end

  test "hidden post comments remain visible to discussion moderators only" do
    author = UserFixtures.insert_user!()
    moderator = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Hidden comment thread",
        content: "Moderation visibility test.",
        category_type: :general
      })

    {:ok, comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Needs moderation context."
      })

    assert {:ok, 1} = Discussions.hide_comment(comment.id, %{reason: "Removed comment"})

    assert {:ok, %{items: []}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer_id: other.id,
               sort_by: :newest
             })

    assert {:ok, %{items: [hidden_comment]}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer: %{id: moderator.id, mod_discussions: true},
               sort_by: :newest
             })

    assert hidden_comment.id == comment.id
    assert hidden_comment.hidden_reason == "Removed comment"
  end

  test "hiding or deleting pinned comments clears the pin slot" do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Pinned slot cleanup",
        content: "Hidden and deleted pins should not consume slots.",
        category_type: :general
      })

    comments =
      for index <- 1..4 do
        {:ok, comment} =
          Discussions.create_comment(%{
            post_id: post.id,
            user_id: author.id,
            content: "Pin #{index}"
          })

        comment
      end

    [first_comment, second_comment, third_comment, fourth_comment] = comments

    for comment <- [first_comment, second_comment, third_comment] do
      assert {:ok, _} = Discussions.admin_moderate_comment(comment.id, %{is_pinned: true})
    end

    assert {:ok, 1} = Discussions.hide_comment(second_comment.id)
    assert Repo.get!(Comment, second_comment.id).is_pinned == false

    assert {:ok, true} = Discussions.delete_comment(third_comment.id, author.id)
    assert Repo.get!(Comment, third_comment.id).is_pinned == false

    assert {:ok, fourth_pinned} =
             Discussions.admin_moderate_comment(fourth_comment.id, %{is_pinned: true})

    assert fourth_pinned.is_pinned == true
    assert Repo.get!(Comment, first_comment.id).is_pinned == true

    assert {:ok, %{items: [fourth, first | _]}} =
             Discussions.list_comments_for_post_cursor(post.id, %{
               viewer_id: author.id,
               sort_by: :newest,
               limit: 20
             })

    assert [fourth.id, first.id] == [fourth_comment.id, first_comment.id]
  end

  test "rehiding a hidden child comment subtree keeps it hidden when the parent is unhidden" do
    author = UserFixtures.insert_user!()

    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "Nested moderation thread",
        content: "Testing independent subtree moderation timestamps.",
        category_type: :general
      })

    {:ok, parent_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        content: "Parent"
      })

    {:ok, child_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: parent_comment.id,
        content: "Child"
      })

    {:ok, grandchild_comment} =
      Discussions.create_comment(%{
        post_id: post.id,
        user_id: author.id,
        parent_comment_id: child_comment.id,
        content: "Grandchild"
      })

    assert {:ok, 3} = Discussions.hide_comment(parent_comment.id, %{reason: "Parent removal"})

    original_hidden_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-60)

    Repo.update_all(
      from(c in Comment,
        where: c.id in ^[parent_comment.id, child_comment.id, grandchild_comment.id]
      ),
      set: [hidden_at: original_hidden_at]
    )

    assert {:ok, 0} = Discussions.hide_comment(child_comment.id, %{reason: "Child removal"})

    parent_after_rehide = Repo.get!(Comment, parent_comment.id)
    child_after_rehide = Repo.get!(Comment, child_comment.id)
    grandchild_after_rehide = Repo.get!(Comment, grandchild_comment.id)

    assert parent_after_rehide.hidden_at == original_hidden_at
    assert child_after_rehide.hidden_at != original_hidden_at
    assert grandchild_after_rehide.hidden_at == child_after_rehide.hidden_at
    assert child_after_rehide.hidden_reason == "Child removal"
    assert grandchild_after_rehide.hidden_reason == nil

    assert {:ok, 1} = Discussions.unhide_comment(parent_comment.id)

    visible_parent = Repo.get!(Comment, parent_comment.id)
    still_hidden_child = Repo.get!(Comment, child_comment.id)
    still_hidden_grandchild = Repo.get!(Comment, grandchild_comment.id)
    refreshed_post = Repo.get!(Post, post.id)

    assert visible_parent.hidden_at == nil
    assert still_hidden_child.hidden_at == child_after_rehide.hidden_at
    assert still_hidden_grandchild.hidden_at == grandchild_after_rehide.hidden_at
    assert refreshed_post.comments_count == 1
  end

  test "review hide does not store moderation reasons and lock does not require a reason" do
    author = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()
    vn = insert_vn!("Moderated Review VN")
    review = insert_review!(author, vn)

    assert {:ok, hidden} = Reviews.hide_review(review.id, %{reason: "Harassment"})
    assert hidden.hidden_at != nil

    assert {:ok, %{items: [public_review]}} =
             Reviews.list_reviews_for_user(
               author.id,
               %{page: 1, page_size: 20, sort_by: :newest},
               other.id
             )

    assert public_review.id == review.id
    assert public_review.content == nil

    assert {:ok, locked} = Reviews.admin_lock_review(review.id)
    assert locked.is_locked == true

    assert {:ok, unhidden} = Reviews.unhide_review(review.id)
    assert unhidden.hidden_at == nil

    assert {:ok, unlocked} = Reviews.admin_unlock_review(review.id)
    assert unlocked.is_locked == false
  end

  test "review moderators can still read comments on hidden reviews" do
    author = UserFixtures.insert_user!()
    moderator = UserFixtures.insert_user!(%{mod_reviews: true})
    vn = insert_vn!("Hidden Review Comments VN")
    review = insert_review!(author, vn)

    comment =
      %ReviewComment{}
      |> ReviewComment.changeset(%{
        vn_review_id: review.id,
        user_id: author.id,
        content: "A visible comment before moderation."
      })
      |> Repo.insert!()

    assert {:ok, _hidden} = Reviews.hide_review(review.id, %{reason: "Harassment"})

    assert {:error, :not_found} =
             ReviewAdapter.load(review.id, nil, %{page: 1, page_size: 20})

    assert {:ok, mod_result} =
             ReviewAdapter.load(
               review.id,
               %{id: moderator.id, role: moderator.role, mod_reviews: true},
               %{page: 1, page_size: 20}
             )

    assert [%{id: comment_id, content: "A visible comment before moderation."}] = mod_result.items
    assert comment_id == comment.id
  end

  test "list hide does not store moderation reasons" do
    author = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()
    list = insert_list!(author)

    assert {:ok, hidden} = Lists.hide_list(list.id, %{reason: "Spam links in description"})
    assert hidden.hidden_at != nil

    assert {:ok, %{items: [public_list]}} =
             Lists.list_user_lists(author.id, other.id, %{
               page: 1,
               page_size: 20,
               sort_by: :updated_at_desc
             })

    assert public_list.id == list.id
    assert public_list.name == nil

    assert {:ok, unhidden} = Lists.unhide_list(list.id)
    assert unhidden.hidden_at == nil
  end

  test "hidden list tombstones do not allow new comments from public viewers" do
    author = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()
    list = insert_list!(author)

    assert {:ok, _hidden} = Lists.hide_list(list.id, %{reason: "Spam links in description"})

    assert {:error, :not_found} =
             Lists.create_list_comment(%{
               list_id: list.id,
               user_id: other.id,
               content: "This should not post"
             })

    refute Repo.exists?(from(c in ListComment, where: c.list_id == ^list.id))
  end

  defp insert_vn!(title) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{title: title})
    |> Repo.insert!()
  end

  defp insert_review!(author, vn) do
    content = String.duplicate("This is a thoughtful moderated review. ", 2)

    %Review{}
    |> Review.changeset(%{user_id: author.id, visual_novel_id: vn.id, content: content})
    |> Repo.insert!()
  end

  defp insert_list!(author) do
    %List{}
    |> List.changeset(%{user_id: author.id, name: "Moderated list"})
    |> Repo.insert!()
  end
end

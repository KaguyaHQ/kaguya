defmodule Kaguya.Discussions.Likes do
  @moduledoc false

  alias Kaguya.Repo
  alias Kaguya.Social
  alias Kaguya.Social.Likes, as: SocialLikes

  alias Kaguya.Discussions.{
    Comment,
    CommentLike,
    Comments,
    Policy,
    Post,
    PostLike,
    Posts,
    SideEffects
  }

  def like_post(post_id, user_id) do
    result =
      Repo.transact(fn ->
        with {:ok, post} <- Posts.get_post_for_viewer(post_id, user_id),
             {:ok, inserted?} <-
               SocialLikes.create_like(PostLike, %{
                 post_id: post_id,
                 user_id: user_id
               }) do
          if inserted? do
            SocialLikes.increment_likes(Post, post_id)
            {:ok, post}
          else
            {:ok, :already_liked}
          end
        end
      end)

    case result do
      {:ok, %Post{} = post} ->
        SideEffects.notify_post_like(post, user_id)
        {:ok, true}

      {:ok, :already_liked} ->
        {:ok, true}

      error ->
        error
    end
  end

  def unlike_post(post_id, user_id) do
    Repo.transact(fn ->
      with {:ok, _post} <- Posts.get_post_for_viewer(post_id, user_id) do
        case SocialLikes.delete_like(PostLike,
               post_id: post_id,
               user_id: user_id
             ) do
          {1, _} ->
            SocialLikes.decrement_likes(Post, post_id)
            {:ok, true}

          {0, _} ->
            {:ok, true}
        end
      end
    end)
  end

  def like_comment(comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- Comments.get_comment(comment_id),
           {:ok, _} <- Policy.check_visible(comment, user_id),
           {:ok, post} <- Posts.get_post_for_viewer(comment.post_id, user_id),
           {:ok, inserted?} <-
             SocialLikes.create_like(CommentLike, %{
               post_comment_id: comment_id,
               user_id: user_id
             }),
           :ok <- maybe_increment_comment_like(inserted?, comment, post, user_id) do
        {:ok, true}
      end
    end)
  end

  def unlike_comment(comment_id, user_id) do
    Repo.transact(fn ->
      with {:ok, comment} <- Comments.get_comment(comment_id),
           {:ok, _} <- Policy.check_visible(comment, user_id) do
        case SocialLikes.delete_like(CommentLike,
               post_comment_id: comment_id,
               user_id: user_id
             ) do
          {1, _} ->
            SocialLikes.decrement_likes(Comment, comment_id)
            {:ok, true}

          {0, _} ->
            {:ok, true}
        end
      end
    end)
  end

  defp maybe_increment_comment_like(false, _comment, _post, _user_id), do: :ok

  defp maybe_increment_comment_like(true, comment, post, user_id) do
    SocialLikes.increment_likes(Comment, comment.id)

    Social.create_notification(%{
      user_id: comment.user_id,
      action: :like,
      entity_type: :comment,
      entity_id: comment.id,
      actor_id: user_id,
      metadata: SideEffects.build_comment_metadata(post, comment)
    })

    :ok
  end
end

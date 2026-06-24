defmodule Kaguya.Discussions.SideEffects do
  @moduledoc false

  alias Kaguya.Activities
  alias Kaguya.Social
  alias Kaguya.Utils.TextPreview

  def post_comment_config(post) do
    %{
      comment_schema: Kaguya.Discussions.Comment,
      parent_schema: Kaguya.Discussions.Post,
      entity_type: :post,
      comment_changeset: &Kaguya.Discussions.Comment.changeset(%Kaguya.Discussions.Comment{}, &1),
      parent_id_field: & &1.post_id,
      get_parent: fn _attrs -> post end,
      get_parent_owner: & &1.user_id,
      build_metadata: &build_comment_metadata/2
    }
  end

  def notify_target_user(%{category_type: :user, entity_id: target_id} = post, actor_id)
      when not is_nil(target_id) do
    Social.create_notification(%{
      user_id: target_id,
      action: :mention,
      entity_type: :post,
      entity_id: post.id,
      actor_id: actor_id,
      metadata: post_metadata(post)
    })
  end

  def notify_target_user(_post, _actor_id), do: :ok

  def notify_post_like(post, user_id) do
    Social.create_notification(%{
      user_id: post.user_id,
      action: :like,
      entity_type: :post,
      entity_id: post.id,
      actor_id: user_id,
      metadata: post_metadata(post)
    })
  end

  def build_comment_metadata(post, comment) do
    post
    |> post_metadata()
    |> Map.merge(%{
      text_preview: comment.content |> TextPreview.truncate_on_words(),
      parent_entity_type: "post"
    })
  end

  def post_metadata(post) do
    %{
      post_title: post.title,
      post_slug: post.slug,
      post_short_id: post.short_id,
      post_category_type: to_string(post.category_type)
    }
  end

  def record_post_activity(user_id, post) do
    Activities.record_activity(%{
      user_id: user_id,
      action: :created_post,
      entity_type: "post",
      entity_id: post.id,
      metadata: post_metadata(post)
    })
  end

  def record_comment_activity(comment, post) do
    Activities.record_activity(%{
      user_id: comment.user_id,
      action: :commented,
      entity_type: "post_comment",
      entity_id: comment.id,
      metadata:
        post
        |> post_metadata()
        |> Map.merge(%{
          parent_entity_type: "post",
          comment_short_id: comment.short_id,
          text_preview: comment.content |> TextPreview.truncate_on_words()
        })
    })
  end
end

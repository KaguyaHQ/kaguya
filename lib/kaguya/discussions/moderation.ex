defmodule Kaguya.Discussions.Moderation do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Activities
  alias Kaguya.Comments, as: GenericComments
  alias Kaguya.Moderation.Reasons
  alias Kaguya.Repo
  alias Kaguya.Discussions.{Comment, Comments, Counters, Policy, Post, Posts, SideEffects}

  def delete_post(post_id, user_id) do
    with {:ok, post} <- Policy.get_post_by_owner(post_id, user_id),
         :ok <- Policy.check_not_deleted(post) do
      soft_delete_post(post, :user)
    end
  end

  def admin_delete_post(post_id) do
    with {:ok, post} <- Posts.get_post(post_id),
         :ok <- Policy.check_not_deleted(post) do
      soft_delete_post(post, :admin)
    end
  end

  defp soft_delete_post(post, deleted_by_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      Repo.transact(fn ->
        with {:ok, _} <-
               post
               |> Ecto.Changeset.change(deleted_at: now, deleted_by_type: deleted_by_type)
               |> Repo.update() do
          comment_ids =
            from(c in Comment,
              where: c.post_id == ^post.id and is_nil(c.deleted_at),
              select: c.id
            )
            |> Repo.all()

          unless comment_ids == [] do
            from(c in Comment, where: c.id in ^comment_ids)
            |> Repo.update_all(set: [deleted_at: now, deleted_by_type: deleted_by_type])
          end

          {:ok, comment_ids}
        end
      end)

    with {:ok, comment_ids} <- result do
      Activities.delete_activities_for_entity("post", post.id)
      Enum.each(comment_ids, &Activities.delete_activities_for_entity("post_comment", &1))
      {:ok, true}
    end
  end

  def delete_comment(comment_id, user_id) do
    with {:ok, comment} <- Policy.get_comment_by_owner(comment_id, user_id),
         :ok <- Policy.check_not_deleted(comment) do
      soft_delete_comment(comment, :user)
    end
  end

  defp soft_delete_comment(comment, deleted_by_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    post_id = comment.post_id
    was_visible = is_nil(comment.hidden_at)

    result =
      Repo.transact(fn ->
        with {:ok, _} <-
               comment
               |> Ecto.Changeset.change(
                 deleted_at: now,
                 deleted_by_type: deleted_by_type,
                 is_pinned: false,
                 pinned_at: nil
               )
               |> Repo.update() do
          if was_visible do
            from(t in Post, where: t.id == ^post_id)
            |> Repo.update_all(inc: [comments_count: -1])
          end

          {:ok, true}
        end
      end)

    with {:ok, true} <- result do
      Activities.delete_activities_for_entity("post_comment", comment.id)
      if post_id, do: Counters.recalculate_last_comment(post_id)
      {:ok, true}
    end
  end

  def hide_post(post_id, attrs \\ %{}) do
    attrs = normalize_moderation_attrs(attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, post} <- Posts.get_post(post_id),
         :ok <- Policy.check_not_deleted(post),
         {:ok, reason} <- Reasons.normalize_optional(Map.get(attrs, :reason)),
         {:ok, mod_note} <- Reasons.normalize_optional(Map.get(attrs, :mod_note)) do
      Repo.transact(fn ->
        with {:ok, updated} <-
               post
               |> Ecto.Changeset.change(
                 hidden_at: now,
                 hidden_reason: reason,
                 hidden_mod_note: mod_note,
                 is_locked:
                   truthy?(Map.get(attrs, :lock_thread) || Map.get(attrs, "lock_thread")) ||
                     post.is_locked
               )
               |> Repo.update(),
             :ok <- maybe_create_removal_comment(post, attrs, reason) do
          {:ok, updated}
        end
      end)
    end
  end

  def unhide_post(post_id) do
    with {:ok, post} <- Posts.get_post(post_id) do
      post
      |> Ecto.Changeset.change(hidden_at: nil, hidden_reason: nil, hidden_mod_note: nil)
      |> Repo.update()
    end
  end

  def hide_comment(comment_id, attrs \\ %{}) do
    with {:ok, comment} <- Comments.get_comment(comment_id),
         :ok <- Policy.check_not_deleted(comment) do
      subtree_ids = GenericComments.collect_subtree_ids(Comment, comment_id)

      with {:ok, hidden_count} <-
             GenericComments.hide_comment_subtree(
               Comment,
               Post,
               comment_id,
               :post_id,
               attrs
             ) do
        Comments.unpin_comments(subtree_ids)
        {:ok, hidden_count}
      end
    end
  end

  def unhide_comment(comment_id) do
    GenericComments.unhide_comment_subtree(
      Comment,
      Post,
      comment_id,
      :post_id
    )
  end

  defp normalize_moderation_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_moderation_attrs(reason) when is_binary(reason), do: %{reason: reason}
  defp normalize_moderation_attrs(_attrs), do: %{}

  defp maybe_create_removal_comment(_post, %{add_comment: false}, _reason), do: :ok
  defp maybe_create_removal_comment(_post, %{"add_comment" => false}, _reason), do: :ok
  defp maybe_create_removal_comment(_post, _attrs, nil), do: :ok

  defp maybe_create_removal_comment(post, attrs, reason) do
    if truthy?(Map.get(attrs, :add_comment) || Map.get(attrs, "add_comment")) do
      case Map.get(attrs, :actor_id) || Map.get(attrs, "actor_id") do
        nil ->
          :ok

        actor_id ->
          content = Map.get(attrs, :comment) || Map.get(attrs, "comment") || reason

          case GenericComments.create_comment(SideEffects.post_comment_config(post), %{
                 post_id: post.id,
                 user_id: actor_id,
                 is_pinned: false,
                 content: content
               }) do
            {:ok, comment} ->
              with {:ok, _comment} <- Comments.pin_comment(comment), do: :ok

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      :ok
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end

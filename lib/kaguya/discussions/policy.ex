defmodule Kaguya.Discussions.Policy do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Discussions.{Category, Comment, Post, PostLike}

  def can_modify?(record, user_id, role \\ nil)

  def can_modify?(%{deleted_at: d}, _user_id, _role) when not is_nil(d), do: false

  def can_modify?(_record, _user_id, :admin), do: true

  def can_modify?(%{user_id: uid}, user_id, _role) when uid == user_id and not is_nil(uid),
    do: true

  def can_modify?(_record, _user_id, _role), do: false

  @doc """
  Whether a post's title is locked from author edits because non-author engagement
  exists (a comment or like from someone other than the author). Body edits remain
  free; the `is_edited` flag is the accountability marker.
  """
  def title_locked?(%Post{id: post_id, user_id: author_id}) when not is_nil(author_id) do
    Repo.exists?(from c in Comment, where: c.post_id == ^post_id and c.user_id != ^author_id) or
      Repo.exists?(from l in PostLike, where: l.post_id == ^post_id and l.user_id != ^author_id)
  end

  def title_locked?(_), do: false

  def check_not_deleted(%{deleted_at: nil}), do: :ok
  def check_not_deleted(_), do: {:error, "This content has been deleted"}

  def check_parent_comment_for_post(%{parent_comment_id: nil}, _post_id), do: :ok

  def check_parent_comment_for_post(%{parent_comment_id: parent_id}, post_id) do
    case Repo.get(Comment, parent_id) do
      nil -> {:error, :not_found}
      %{post_id: ^post_id, deleted_at: nil, hidden_at: nil} -> :ok
      %{post_id: ^post_id, deleted_at: nil} -> {:error, "Cannot reply to a hidden comment"}
      %{post_id: ^post_id} -> {:error, "Cannot reply to a deleted comment"}
      _ -> {:error, :parent_not_in_post}
    end
  end

  def check_parent_comment_for_post(_attrs, _post_id), do: :ok

  def validate_target_entity(:user, entity_id, creator_id) when not is_nil(entity_id) do
    if entity_id == creator_id do
      {:error, "Cannot create a post about yourself"}
    else
      case Kaguya.Users.get_user(entity_id) do
        {:ok, _} -> :ok
        _ -> {:error, "User not found"}
      end
    end
  end

  def validate_target_entity(_, _, _), do: :ok

  # Block title changes only when the title actually changes AND non-author
  # engagement exists. Body edits and same-title submits always pass.
  def check_title_unlocked(%Post{title: current} = post, %{title: new_title})
      when not is_nil(new_title) and new_title != current do
    if title_locked?(post) do
      {:error,
       "Title can no longer be edited because others have engaged with this post. You can still edit the body."}
    else
      :ok
    end
  end

  def check_title_unlocked(_post, _attrs), do: :ok

  def check_visible(record, viewer_id), do: check_visible(record, viewer_id, %{})

  # Strict gate used by action paths (like, comment, etc.). Deleted posts pass
  # since other guards check deleted_at separately; only hidden_at blocks here.
  def check_visible(%{hidden_at: nil} = record, _viewer_id, _opts), do: {:ok, record}
  def check_visible(record, _viewer_id, %{mod_discussions: true}), do: {:ok, record}
  def check_visible(record, _viewer_id, %{role: :admin}), do: {:ok, record}
  def check_visible(%{user_id: uid} = record, uid, _opts) when not is_nil(uid), do: {:ok, record}
  def check_visible(_record, _viewer_id, _opts), do: {:error, :not_found}

  # View-mode visibility: returns the post as-is for authorized viewers, or a
  # scrubbed copy for everyone else so the frontend can render a tombstone.
  def scrub_for_viewer(%{hidden_at: nil} = post, _viewer_id, _opts), do: post
  def scrub_for_viewer(post, _viewer_id, %{mod_discussions: true}), do: post
  def scrub_for_viewer(post, _viewer_id, %{role: :admin}), do: post
  def scrub_for_viewer(post, _viewer_id, _opts), do: scrub_hidden(post)

  def scrub_hidden_for_profile(%{hidden_at: nil} = post, _viewer_id), do: post

  def scrub_hidden_for_profile(%Post{} = post, _viewer_id) do
    %{
      scrub_hidden(post)
      | user_id: post.user_id,
        category_type: post.category_type,
        entity_id: post.entity_id,
        slug: post.slug,
        short_id: post.short_id
    }
  end

  def scrub_hidden(%Post{} = post) do
    %{
      post
      | content: nil,
        user_id: nil,
        last_comment_user_id: nil,
        last_comment_at: nil,
        likes_count: 0,
        is_pinned: false,
        is_edited: false,
        deleted_at: nil,
        deleted_by_type: nil
    }
  end

  def get_post_by_owner(post_id, user_id) do
    case Repo.get_by(Post, id: post_id, user_id: user_id) do
      nil -> {:error, :not_found}
      post -> {:ok, post}
    end
  end

  def get_comment_by_owner(comment_id, user_id) do
    case Repo.get_by(Comment, id: comment_id, user_id: user_id) do
      nil -> {:error, :not_found}
      comment -> {:ok, comment}
    end
  end

  def check_admin_only_category(category_type, user_id, opts) do
    if Category.admin_only?(category_type), do: verify_admin_role(user_id, opts), else: :ok
  end

  def verify_admin_role(user_id, opts) do
    role =
      Keyword.get_lazy(opts, :role, fn ->
        case Kaguya.Users.get_user(user_id) do
          {:ok, user} -> user.role
          _ -> nil
        end
      end)

    if role == :admin, do: :ok, else: {:error, "Only admins can post in this category"}
  end

  def check_not_locked(%Post{is_locked: true}),
    do: {:error, "This post is locked."}

  def check_not_locked(_post), do: :ok
end

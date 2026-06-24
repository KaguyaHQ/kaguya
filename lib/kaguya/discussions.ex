defmodule Kaguya.Discussions do
  @moduledoc """
  Context for discussion posts and comments.

  Category-based system — posts belong to a category type with an optional
  entity reference (VN, producer, character).
  """

  alias Kaguya.Discussions

  defdelegate create_post(user_id, attrs, opts \\ []), to: Discussions.Posts
  defdelegate get_post(id), to: Discussions.Posts
  defdelegate get_post_for_viewer(id, viewer_id, viewer \\ %{}), to: Discussions.Posts
  defdelegate get_post_by_short_id(short_id), to: Discussions.Posts

  defdelegate get_post_by_short_id_for_viewer(short_id, viewer_id, viewer \\ %{}),
    to: Discussions.Posts

  defdelegate get_post_for_view(id, viewer_id, viewer \\ %{}), to: Discussions.Posts

  defdelegate get_post_by_short_id_for_view(short_id, viewer_id, viewer \\ %{}),
    to: Discussions.Posts

  defdelegate update_post(post_id, user_id, attrs), to: Discussions.Posts
  defdelegate admin_moderate_post(post_id, attrs), to: Discussions.Posts
  defdelegate admin_lock_post(post_id), to: Discussions.Posts
  defdelegate admin_unlock_post(post_id), to: Discussions.Posts
  defdelegate list_posts(opts \\ %{}), to: Discussions.Posts
  defdelegate list_posts_for_entity(category_type, entity_id, opts \\ %{}), to: Discussions.Posts
  defdelegate list_posts_for_user(user_id, opts \\ %{}), to: Discussions.Posts
  defdelegate list_pinned_posts(category_type \\ nil, viewer_id \\ nil), to: Discussions.Posts
  defdelegate recent_comment_users_by_post_ids(post_ids, limit \\ 3), to: Discussions.Posts
  defdelegate title_locked?(post), to: Discussions.Posts

  defdelegate create_comment(attrs), to: Discussions.Comments
  defdelegate get_comment(id), to: Discussions.Comments
  defdelegate get_comment_for_post(post_id, comment_id, viewer \\ nil), to: Discussions.Comments

  defdelegate get_comment_by_short_id_for_post(post_id, short_id, viewer \\ nil),
    to: Discussions.Comments

  defdelegate list_comment_descendants_for_comment(post_id, parent_comment_id, params \\ %{}),
    to: Discussions.Comments

  defdelegate update_comment(comment_id, user_id, content), to: Discussions.Comments
  defdelegate delete_comment(comment_id, user_id), to: Discussions.Comments

  defdelegate list_comments_for_post(post_id, comments_count, params, viewer_id \\ nil),
    to: Discussions.Comments

  defdelegate list_comments_for_post_cursor(post_id, params), to: Discussions.Comments
  defdelegate admin_moderate_comment(comment_id, attrs), to: Discussions.Comments

  defdelegate delete_post(post_id, user_id), to: Discussions.Moderation
  defdelegate admin_delete_post(post_id), to: Discussions.Moderation
  defdelegate hide_post(post_id, attrs \\ %{}), to: Discussions.Moderation
  defdelegate unhide_post(post_id), to: Discussions.Moderation
  defdelegate hide_comment(comment_id, attrs \\ %{}), to: Discussions.Moderation
  defdelegate unhide_comment(comment_id), to: Discussions.Moderation

  defdelegate like_post(post_id, user_id), to: Discussions.Likes
  defdelegate unlike_post(post_id, user_id), to: Discussions.Likes
  defdelegate like_comment(comment_id, user_id), to: Discussions.Likes
  defdelegate unlike_comment(comment_id, user_id), to: Discussions.Likes

  defdelegate search_category_targets(query), to: Discussions.Targets
  defdelegate user_vn_targets(user_id), to: Discussions.Targets
  defdelegate list_posts_for_sitemap(page \\ 1, page_size \\ 1000), to: Discussions.Sitemap
  defdelegate can_modify?(record, user_id, role \\ nil), to: Discussions.Policy
end

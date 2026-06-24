defmodule KaguyaWeb.NotificationsLive.Data do
  @moduledoc """
  Data loading and normalization for the notifications page.

  The page intentionally calls directly into the social context, while still
  reusing the same notification payload shape as other web surfaces.
  """

  alias Kaguya.Social
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @limit 12

  def page_size, do: @limit

  def load_page(current_user, params) when is_map(current_user) do
    params = params || %{}
    cursor = Map.get(params, "cursor")
    limit = normalize_limit(Map.get(params, "limit"))
    only_unread = normalize_only_unread(Map.get(params, "only_unread"))

    {items, next_cursor, has_next} =
      Social.list_notifications_for_user(current_user.id, only_unread, cursor, limit)

    unread_count = Social.unread_count(current_user.id)

    {:ok,
     %{
       notifications: normalize_notifications(items),
       has_next: has_next,
       next_cursor: next_cursor,
       unread_count: unread_count,
       limit: limit,
       only_unread: only_unread
     }}
  end

  def load_page(_current_user, _params), do: {:error, :not_found}

  def load_more(current_user, cursor, limit) when is_map(current_user) do
    {items, next_cursor, has_next} =
      Social.list_notifications_for_user(current_user.id, false, cursor, limit)

    {:ok,
     %{
       notifications: normalize_notifications(items),
       has_next: has_next,
       next_cursor: next_cursor
     }}
  end

  def load_more(_current_user, _cursor, _limit), do: {:error, :not_found}

  def mark_all_notifications_read(current_user) when is_map(current_user) do
    Social.mark_all_notifications_read(current_user.id)
  end

  def normalize_notification(notification) do
    meta = embed_metadata(notification.metadata)
    action = to_string(notification.action)
    entity_type = to_string(notification.entity_type)
    type_key = "#{action}_#{entity_type}"

    actors = normalize_actors(meta)

    %{
      id: notification.id,
      action: action,
      entity_type: entity_type,
      type_key: type_key,
      read: !!notification.read,
      actors: actors,
      actors_count: actors_count(meta, actors),
      metadata: meta,
      target_name: target_name(type_key, meta),
      message: nil,
      link: notification_link(type_key, meta),
      text_preview: normalized_text_preview(meta, type_key),
      thumbnail_url: notification_image(meta),
      list_cover_urls: normalized_list_cover_urls(meta),
      inserted_at: notification.inserted_at,
      inserted_label: SharedTime.calendar_custom(notification.inserted_at)
    }
  end

  def supported_type?(%{type_key: type_key}) do
    type_key in [
      "follow_user",
      "like_review",
      "like_comment",
      "reply_comment",
      "new_comment_review",
      "like_list",
      "new_comment_list",
      "like_vn_list",
      "new_comment_vn_list",
      "new_comment_post",
      "like_post",
      "mention_post",
      "report_reviewed_report"
    ]
  end

  defp normalize_notifications(items) do
    items
    |> Enum.map(&normalize_notification/1)
    |> Enum.filter(&supported_type?/1)
  end

  defp normalize_limit(value) when is_integer(value), do: clamp_limit(value)

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> clamp_limit(n)
      _ -> @limit
    end
  end

  defp normalize_limit(_), do: @limit

  defp clamp_limit(limit), do: max(1, min(limit, 64))

  defp normalize_only_unread(value) when value in [true, "true", "1", "on", "yes"], do: true
  defp normalize_only_unread(_), do: false

  defp embed_metadata(nil), do: %{}
  defp embed_metadata(%{} = metadata), do: metadata
  defp embed_metadata(metadata), do: Map.from_struct(metadata)

  defp actors_count(meta, actors) do
    case meta_value(meta, :actors_count) do
      n when is_integer(n) -> n
      _ -> length(actors)
    end
  end

  defp actor_snapshots(meta) do
    case meta_value(meta, :actor_snapshots) do
      actors when is_list(actors) -> actors
      _ -> []
    end
  end

  defp normalize_actors(meta) do
    meta
    |> actor_snapshots()
    |> Enum.map(&normalize_actor/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_actor(actor) when is_map(actor) do
    username = meta_value(actor, :username)

    if is_binary(username) and username != "" do
      %{
        id: meta_value(actor, :id),
        username: username,
        avatar_url: meta_value(actor, :avatar_url),
        href: "/@#{username}"
      }
    end
  end

  defp normalize_actor(_), do: nil

  defp first_actor_username(meta) do
    meta
    |> actor_snapshots()
    |> List.first()
    |> normalize_actor()
    |> case do
      %{username: username} -> username
      _ -> nil
    end
  end

  defp notification_image(meta) do
    value = meta_value(meta, :vn_image_url)

    case value do
      s when is_binary(s) and s != "" -> s
      _ -> nil
    end
  end

  defp normalized_list_cover_urls(meta) do
    list_cover_urls = meta_value(meta, :list_cover_urls)

    if is_list(list_cover_urls) do
      list_cover_urls
      |> Enum.map(&maybe_non_empty/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(3)
    else
      []
    end
  end

  defp maybe_non_empty(value) when is_binary(value) and value != "", do: value
  defp maybe_non_empty(_), do: nil

  defp target_name("follow_user", _meta), do: "you"
  defp target_name("like_review", meta), do: meta_value(meta, :vn_title) || "your review"
  defp target_name("new_comment_review", meta), do: meta_value(meta, :vn_title) || "your review"

  defp target_name("report_reviewed_report", meta) do
    meta_value(meta, :report_entity_name) || meta_value(meta, :report_entity_type) ||
      "your report"
  end

  defp target_name(type_key, meta) when type_key in ["like_comment", "reply_comment"] do
    parent_type = meta_value(meta, :parent_entity_type)

    cond do
      parent_type in ["review"] -> meta_value(meta, :vn_title) || "your review"
      parent_type in ["list"] -> meta_value(meta, :list_name) || "your list"
      parent_type in ["post"] -> meta_value(meta, :post_title) || "your discussion"
      true -> ""
    end
  end

  defp target_name("like_vn_list", meta), do: meta_value(meta, :list_name) || "your list"
  defp target_name("new_comment_vn_list", meta), do: meta_value(meta, :list_name) || "your list"
  defp target_name("like_list", meta), do: meta_value(meta, :list_name) || "your list"
  defp target_name("new_comment_list", meta), do: meta_value(meta, :list_name) || "your list"

  defp target_name(type_key, meta)
       when type_key in ["new_comment_post", "like_post", "mention_post"] do
    meta_value(meta, :post_title) || "your discussion"
  end

  defp target_name(_, _), do: ""

  defp normalized_text_preview(meta, type_key)
       when type_key in [
              "reply_comment",
              "new_comment_review",
              "new_comment_vn_list",
              "new_comment_post",
              "report_reviewed_report"
            ] do
    case meta_value(meta, :text_preview) do
      text when is_binary(text) and text != "" -> String.slice(text, 0, 120)
      _ -> nil
    end
  end

  defp normalized_text_preview(_meta, _type_key), do: nil

  defp notification_link("follow_user", meta) do
    case first_actor_username(meta) do
      username when is_binary(username) and username != "" -> "/@#{username}"
      _ -> "#"
    end
  end

  defp notification_link("like_review", meta), do: review_path(meta) || "#"
  defp notification_link("new_comment_review", meta), do: review_path(meta) || "#"

  defp notification_link("like_comment", meta) do
    post_path(meta) ||
      review_path(meta) ||
      list_path(meta) ||
      "#"
  end

  defp notification_link("reply_comment", meta) do
    post_path(meta) ||
      review_path(meta) ||
      list_path(meta) ||
      "#"
  end

  defp notification_link("new_comment_vn_list", meta), do: list_path(meta)
  defp notification_link("like_vn_list", meta), do: list_path(meta)
  defp notification_link("new_comment_list", meta), do: list_path(meta)
  defp notification_link("like_list", meta), do: list_path(meta)

  defp notification_link(type_key, meta)
       when type_key in ["new_comment_post", "like_post", "mention_post"] do
    standalone_post_path(meta)
  end

  defp notification_link("report_reviewed_report", meta) do
    meta_value(meta, :report_entity_path) || "/notifications"
  end

  defp notification_link(_, _), do: "#"

  defp post_path(meta) do
    if short_id = meta_value(meta, :post_short_id) do
      standalone_post_path(%{post_short_id: short_id, post_slug: meta_value(meta, :post_slug)})
    end
  end

  defp review_path(meta) do
    meta
    |> meta_value(:vn_review_path)
    |> canonical_review_path()
  end

  defp canonical_review_path("/vn/" <> rest) do
    case String.split(rest, "/reviews/", parts: 2) do
      [vn_slug, username] when vn_slug != "" and username != "" ->
        "/@#{username}/reviews/#{vn_slug}"

      _ ->
        "/vn/#{rest}"
    end
  end

  defp canonical_review_path(path) when is_binary(path) and path != "", do: path
  defp canonical_review_path(_), do: nil

  defp standalone_post_path(meta) do
    short_id = meta_value(meta, :post_short_id)
    slug = meta_value(meta, :post_slug) || "post"

    if is_binary(short_id) and short_id != "" do
      "/discussions/p/#{short_id}/#{slug}"
    else
      "#"
    end
  end

  defp list_path(meta) do
    creator = meta_value(meta, :list_creator_username)
    slug = meta_value(meta, :list_slug)

    if is_binary(creator) and is_binary(slug) and creator != "" and slug != "" do
      "/@#{creator}/list/#{slug}"
    else
      "#"
    end
  end

  defp meta_value(nil, _), do: nil

  defp meta_value(%{} = map, key) when is_atom(key) or is_binary(key) do
    [key, maybe_to_string(key), to_existing_atom(key)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find_value(fn candidate ->
      case Map.fetch(map, candidate) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp meta_value(map, key) when is_map(map), do: Map.get(map, key)
  defp meta_value(_, _), do: nil

  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value) when is_binary(value), do: value
  defp maybe_to_string(_), do: nil

  defp to_existing_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp to_existing_atom(_), do: nil
end

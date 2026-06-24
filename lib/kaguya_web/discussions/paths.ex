defmodule KaguyaWeb.Discussions.Paths do
  @moduledoc """
  Canonical discussion URLs, ported from
  `../personal/legacy-next-app/src/lib/discussion-url.ts`.

  Entity-scoped posts use the entity route as human-readable context.
  Standalone posts keep the decorative slug behind `/discussions/p/...`.
  """

  def post_url(%{short_id: short_id} = post) when is_binary(short_id) do
    entity_post_url(post) || standalone_post_url(short_id, Map.get(post, :slug))
  end

  def post_url(_post), do: "#"

  def standalone_post_url(short_id, slug) when is_binary(short_id),
    do: "/discussions/p/#{short_id}/#{slug || "post"}"

  def list_url(%{category_type: type} = post) do
    case normalize_category(type) do
      "visual_novel" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :visual_novel),
             do: "/vn/#{slug}/discussions"

      "producer" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :producer),
             do: "/developer/#{slug}/discussions"

      "character" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :character),
             do: "/character/#{slug}/discussions"

      "user" ->
        with %{username: username} when is_binary(username) <- Map.get(post, :target_user),
             do: "/users/#{username}/discussions"

      "announcements" ->
        "/discussions/announcements"

      "site_discussions" ->
        "/discussions/feedback"

      "general" ->
        "/discussions/general"

      _ ->
        "/discussions"
    end
  end

  def list_url(_post), do: "/discussions"

  def entity_tag(%{visual_novel: %{slug: slug, title: title}})
      when is_binary(slug) and is_binary(title),
      do: %{href: "/vn/#{slug}", label: title}

  def entity_tag(%{producer: %{slug: slug, name: name}})
      when is_binary(slug) and is_binary(name),
      do: %{href: "/developer/#{slug}", label: name}

  def entity_tag(%{character: %{slug: slug, name: name}})
      when is_binary(slug) and is_binary(name),
      do: %{href: "/character/#{slug}", label: name}

  def entity_tag(%{target_user: %{username: username}}) when is_binary(username),
    do: %{href: "/@#{username}", label: "@#{username}"}

  def entity_tag(_post), do: nil

  defp entity_post_url(post) do
    case normalize_category(Map.get(post, :category_type)) do
      "visual_novel" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :visual_novel),
             do: "/vn/#{slug}/discussions/#{post.short_id}"

      "producer" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :producer),
             do: "/developer/#{slug}/discussions/#{post.short_id}"

      "character" ->
        with %{slug: slug} when is_binary(slug) <- Map.get(post, :character),
             do: "/character/#{slug}/discussions/#{post.short_id}"

      "user" ->
        with %{username: username} when is_binary(username) <- Map.get(post, :target_user),
             do: "/users/#{username}/discussions/#{post.short_id}"

      _ ->
        nil
    end
  end

  defp normalize_category(nil), do: ""
  defp normalize_category(type), do: type |> to_string() |> String.downcase()
end

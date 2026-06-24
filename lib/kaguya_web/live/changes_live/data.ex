defmodule KaguyaWeb.ChangesLive.Data do
  @moduledoc """
  Data loading and normalization for the global recent changes page.

  The revisions context owns filtering/query behavior; this adapter keeps the
  LiveView render layer on plain maps with URLs and display labels prepared.
  """

  import Ecto.Query

  alias Kaguya.{Producers, Repo, Revisions, Users, VisualNovels}
  alias Kaguya.Users.User
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @page_size 25
  @max_page 200

  @entity_type_options [
    {"All", nil},
    {"Visual novels", "visual_novel"},
    {"Characters", "character"},
    {"Producers", "producer"},
    {"Releases", "release"},
    {"Series", "series"}
  ]

  @entity_type_params %{
    "visual_novel" => :visual_novel,
    "character" => :character,
    "producer" => :producer,
    "release" => :release,
    "series" => :series
  }

  def load(params) do
    page = params |> Map.get("page") |> parse_page()
    entity_type_param = Map.get(params, "type")
    entity_type = Map.get(@entity_type_params, entity_type_param)

    opts =
      [
        limit: @page_size,
        offset: (page - 1) * @page_size,
        entity_type: entity_type
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    changes = Revisions.recent_changes(opts)

    total_count =
      Revisions.recent_changes_count(Keyword.delete(opts, :limit) |> Keyword.delete(:offset))

    %{
      rows: normalize_changes(changes),
      page: page,
      page_size: @page_size,
      total_count: total_count,
      total_pages: max(ceil_div(total_count, @page_size), 1),
      has_previous: page > 1,
      has_next: page * @page_size < total_count,
      entity_type_param: entity_type_param,
      entity_type_options: @entity_type_options
    }
  end

  defp normalize_changes([]), do: []

  defp normalize_changes(changes) do
    entities =
      changes
      |> Enum.map(&{&1.entity_type, &1.entity_id})
      |> Revisions.batch_load_entities()

    users = load_users(changes)

    Enum.map(changes, fn change ->
      entity = Map.get(entities, {change.entity_type, change.entity_id})
      user = change.user_id && Map.get(users, change.user_id)
      normalized_entity = normalize_entity(change.entity_type, entity)

      %{
        id: change.id,
        revision_number: change.revision_number,
        action: change.action,
        action_label: action_label(change.action),
        entity_type: change.entity_type,
        entity_type_label: entity_type_label(change.entity_type),
        entity: normalized_entity,
        change_href: revision_href(change.entity_type, normalized_entity, change.id),
        summary: change.summary,
        changed_fields: change.changed_fields || [],
        source: change.source,
        source_label: source_label(change.source),
        user: normalize_user(user),
        inserted_at: change.inserted_at,
        inserted_at_label: absolute_time(change.inserted_at),
        relative_time: SharedTime.calendar_custom(change.inserted_at)
      }
    end)
  end

  defp load_users(changes) do
    user_ids =
      changes
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case user_ids do
      [] ->
        %{}

      ids ->
        Repo.all(from u in User, where: u.id in ^ids)
        |> Map.new(&{&1.id, &1})
    end
  end

  defp normalize_entity(_type, nil) do
    %{title: "Deleted entry", href: nil, image_url: nil}
  end

  defp normalize_entity(:visual_novel, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.title,
      href: "/vn/#{entity.slug}",
      image_url: image_url(VisualNovels.build_image_urls(entity)),
      is_image_nsfw: Map.get(entity, :is_image_nsfw, false),
      is_image_suggestive: Map.get(entity, :is_image_suggestive, false)
    }
  end

  defp normalize_entity(:character, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/character/#{entity.slug}",
      image_url: image_url(VisualNovels.build_character_image_urls(entity)),
      is_image_nsfw: Map.get(entity, :is_image_nsfw, false),
      is_image_suggestive: Map.get(entity, :is_image_suggestive, false)
    }
  end

  defp normalize_entity(:producer, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/developer/#{entity.slug}",
      image_url: image_url(Producers.build_image_urls(entity))
    }
  end

  defp normalize_entity(:release, entity) do
    %{
      id: entity.id,
      slug: release_parent_slug(entity),
      vn_slug: release_parent_slug(entity),
      title: entity.display_title || entity.title || "Release",
      href: release_href(entity),
      image_url: nil
    }
  end

  defp normalize_entity(:series, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/series/#{entity.slug}",
      image_url: entity.primary_image_url
    }
  end

  defp revision_href(:visual_novel, %{slug: slug}, change_id),
    do: "/vn/#{slug}/history/#{change_id}"

  defp revision_href(:character, %{slug: slug}, change_id),
    do: "/character/#{slug}/history/#{change_id}"

  defp revision_href(:producer, %{slug: slug}, change_id),
    do: "/developer/#{slug}/history/#{change_id}"

  defp revision_href(:series, %{slug: slug}, change_id),
    do: "/series/#{slug}/history/#{change_id}"

  defp revision_href(:release, %{id: id, vn_slug: slug}, change_id)
       when is_binary(slug) and is_binary(id) do
    "/vn/#{slug}/release/#{id}/history/#{change_id}"
  end

  defp revision_href(_, _entity, change_id), do: "/history/#{change_id}"

  defp release_href(%{visual_novel: %{slug: slug}, id: id}), do: "/vn/#{slug}/release/#{id}"
  defp release_href(_entity), do: nil

  defp release_parent_slug(%{visual_novel: %{slug: slug}}), do: slug
  defp release_parent_slug(_), do: nil

  defp normalize_user(nil),
    do: %{display_name: "System", username: nil, avatar_url: nil, href: nil}

  defp normalize_user(user) do
    avatar_url = user.avatar_id && image_url(Users.build_avatar_urls(user.avatar_id))

    %{
      display_name: user.display_name || user.username || "User",
      username: user.username,
      avatar_url: avatar_url,
      href: user.username && "/@#{user.username}"
    }
  end

  defp image_url(urls) when is_map(urls) do
    urls[:small] || urls[:medium] || urls[:large] || urls["small"] || urls["medium"] ||
      urls["large"]
  end

  defp image_url(_), do: nil

  defp action_label(:create), do: "Created"
  defp action_label(:edit), do: "Edited"
  defp action_label(:revert), do: "Reverted"
  defp action_label(:hide), do: "Hidden"
  defp action_label(:unhide), do: "Unhidden"
  defp action_label(:lock), do: "Locked"
  defp action_label(:unlock), do: "Unlocked"

  defp action_label(action),
    do: action |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp entity_type_label(:visual_novel), do: "VN"
  defp entity_type_label(:character), do: "Character"
  defp entity_type_label(:producer), do: "Producer"
  defp entity_type_label(:release), do: "Release"
  defp entity_type_label(:series), do: "Series"
  defp entity_type_label(type), do: to_string(type)

  defp source_label(:vndb_sync), do: "VNDB"
  defp source_label(:user), do: "User"
  defp source_label(:system), do: "System"
  defp source_label(source), do: to_string(source)

  defp absolute_time(value),
    do: KaguyaWeb.SharedComponents.Time.format_datetime_short(value)

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> min(page, @max_page)
      _ -> 1
    end
  end

  defp ceil_div(0, _denominator), do: 0
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end

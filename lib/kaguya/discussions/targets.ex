defmodule Kaguya.Discussions.Targets do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Discussions.Category
  alias Kaguya.Repo
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VisualNovels

  @category_target_limit 15

  @doc """
  Searches for category targets — unified search for the category picker dropdown.
  Empty query returns standalone categories only. With text, uses Meilisearch federated
  search to return one merged list ranked by relevance across VNs, characters, and
  producers.
  """
  def search_category_targets(""), do: {:ok, standalone_category_targets()}
  def search_category_targets(nil), do: {:ok, standalone_category_targets()}

  def search_category_targets(query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:ok, standalone_category_targets()}
    else
      static_matches = match_standalone_categories(query)

      entity_results =
        case Kaguya.Search.federated_search(
               [
                 %{indexUid: "visual_novels", q: query},
                 %{indexUid: "characters", q: query},
                 %{indexUid: "producers", q: query}
               ],
               limit: @category_target_limit
             ) do
          {:ok, hits} -> hits |> Enum.map(&parse_federated_hit/1) |> Enum.reject(&is_nil/1)
          {:error, _reason} -> []
        end

      user_results = search_user_category_targets(query)

      {:ok, static_matches ++ entity_results ++ user_results}
    end
  end

  defp standalone_category_targets do
    Category.standalone_categories()
    |> Enum.map(fn {type, config} ->
      %{category_type: type, entity_id: nil, name: config.name, slug: config.slug, image_url: nil}
    end)
  end

  defp match_standalone_categories(query) do
    q = String.downcase(query)

    Category.standalone_categories()
    |> Enum.filter(fn {_type, config} -> String.contains?(String.downcase(config.name), q) end)
    |> Enum.map(fn {type, config} ->
      %{category_type: type, entity_id: nil, name: config.name, slug: config.slug, image_url: nil}
    end)
  end

  defp parse_federated_hit(%{"_federation" => %{"indexUid" => "visual_novels"}} = hit) do
    %{
      category_type: :visual_novel,
      entity_id: hit["id"],
      name: hit["title"],
      slug: hit["slug"],
      image_url: hit["image_url"]
    }
  end

  defp parse_federated_hit(%{"_federation" => %{"indexUid" => "characters"}} = hit) do
    %{
      category_type: :character,
      entity_id: hit["id"],
      name: hit["name"],
      slug: hit["slug"],
      image_url: build_character_image_url(hit)
    }
  end

  defp parse_federated_hit(%{"_federation" => %{"indexUid" => "producers"}} = hit) do
    %{
      category_type: :producer,
      entity_id: hit["id"],
      name: hit["name"],
      slug: hit["slug"],
      image_url: build_producer_image_url(hit)
    }
  end

  defp parse_federated_hit(_), do: nil

  defp build_character_image_url(%{"primary_image_id" => id}) when is_binary(id) and id != "" do
    "https://images.kaguya.io/characters/#{id}-240w.webp"
  end

  defp build_character_image_url(%{"vndb_image_id" => vndb_id})
       when is_binary(vndb_id) and vndb_id != "" do
    numeric_id = String.replace(vndb_id, ~r/^ch/, "")

    case Integer.parse(numeric_id) do
      {num, ""} ->
        last_two = num |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
        "https://s.vndb.org/ch/#{last_two}/#{num}.jpg"

      _ ->
        nil
    end
  end

  defp build_character_image_url(_), do: nil

  defp build_producer_image_url(%{"primary_image_id" => id}) when is_binary(id) and id != "" do
    Kaguya.Images.url_for_key(Kaguya.Images.key(:producer, id, "120w"))
  end

  defp build_producer_image_url(_), do: nil

  @doc """
  Returns VN targets for the user's currently reading and recently completed VNs.
  Used to pre-populate the picker when the query is empty.
  """
  def user_vn_targets(nil), do: []

  def user_vn_targets(user_id) do
    from(rs in ReadingStatus,
      join: vn in VisualNovel,
      on: vn.id == rs.visual_novel_id,
      where: rs.user_id == ^user_id and rs.status in [:currently_reading, :read],
      order_by: [
        fragment("CASE WHEN ? = 'currently_reading' THEN 0 ELSE 1 END", rs.status),
        desc_nulls_last: rs.date_finished,
        desc: rs.library_added_at
      ],
      limit: 5,
      select: %{
        id: vn.id,
        title: vn.title,
        slug: vn.slug,
        primary_image_id: vn.primary_image_id,
        temp_image_url: vn.temp_image_url,
        is_image_nsfw: vn.is_image_nsfw,
        is_image_suggestive: vn.is_image_suggestive
      }
    )
    |> Repo.all()
    |> Enum.map(fn vn ->
      image_url = vn |> VisualNovels.build_image_urls() |> Map.get(:small)

      %{
        category_type: :visual_novel,
        entity_id: vn.id,
        name: vn.title,
        slug: vn.slug,
        image_url: image_url,
        is_image_nsfw: vn.is_image_nsfw,
        is_image_suggestive: vn.is_image_suggestive
      }
    end)
  end

  defp search_user_category_targets(query) do
    Kaguya.Users.search_users(query)
    |> Enum.take(@category_target_limit)
    |> Enum.map(fn user ->
      avatar = Kaguya.Users.build_avatar_urls(user.avatar_id)

      %{
        category_type: :user,
        entity_id: user.id,
        name: user.display_name || user.username,
        slug: user.username,
        image_url: Map.get(avatar, :small)
      }
    end)
  end
end

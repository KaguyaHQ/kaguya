defmodule KaguyaWeb.Discussions.PathsTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Discussions.Paths
  alias KaguyaWeb.NotFoundController
  alias KaguyaWeb.Router

  test "category list paths resolve to registered discussion routes" do
    paths =
      for category_type <- [
            :general,
            :announcements,
            :site_discussions,
            :visual_novel,
            :producer,
            :character,
            :user
          ] do
        Paths.list_url(%{category_type: category_type})
      end

    assert Enum.all?(paths, &routable?/1)
  end

  test "entity post paths use the registered scoped routes" do
    posts = [
      %{
        category_type: :visual_novel,
        short_id: "vn-post",
        visual_novel: %{slug: "example-vn"}
      },
      %{
        category_type: :producer,
        short_id: "producer-post",
        producer: %{slug: "example-producer"}
      },
      %{
        category_type: :character,
        short_id: "character-post",
        character: %{slug: "example-character"}
      },
      %{
        category_type: :user,
        short_id: "user-post",
        target_user: %{username: "example-user"}
      }
    ]

    paths = Enum.map(posts, &Paths.post_url/1)

    assert "/@example-user/discussions/user-post" in paths
    assert Enum.all?(paths, &routable?/1)
  end

  defp routable?(path) do
    case Phoenix.Router.route_info(Router, "GET", path, "kaguya.io") do
      %{plug: NotFoundController} -> false
      %{} -> true
      :error -> false
    end
  end
end

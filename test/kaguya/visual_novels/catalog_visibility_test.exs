defmodule Kaguya.VisualNovels.CatalogVisibilityTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.{Activities, Feed, Repo}
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Reviews.Review
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{Browse, TitleCategory, VisualNovel}

  setup do
    :ok = Sandbox.checkout(Repo)
    Cachex.clear(:vn_browse_cache)
    on_exit(fn -> Cachex.clear(:vn_browse_cache) end)

    titles =
      Map.new([:vn, :adjacent, :nukige], fn category ->
        vn =
          Repo.insert!(%VisualNovel{
            title: "Catalog #{category}",
            slug: "catalog-#{category}-#{System.unique_integer([:positive])}",
            title_category: category
          })

        {category, vn}
      end)

    %{titles: titles}
  end

  test "legacy hybrid preferences cannot exclude titles; nukige remains optional" do
    for viewer <- [%{}, %User{show_nukige: false, show_adjacent: false}] do
      assert MapSet.new(TitleCategory.allowed_categories(viewer)) == MapSet.new([:vn, :adjacent])
    end

    assert MapSet.new(
             TitleCategory.allowed_categories(%User{show_nukige: true, show_adjacent: false})
           ) ==
             MapSet.new([:vn, :adjacent, :nukige])
  end

  test "browse results and counts include hybrids even with obsolete exclusion filters", %{
    titles: titles
  } do
    for filters <- [%{}, %{include_nukige: false, include_adjacent: false}] do
      result = Browse.list(filters: filters)
      assert ids(result.items) == MapSet.new([titles.vn.id, titles.adjacent.id])
      assert result.pagination.total_count == 2
    end

    result = Browse.list(filters: %{include_nukige: true, include_adjacent: false})
    assert ids(result.items) == ids(Map.values(titles))
    assert result.pagination.total_count == 3
  end

  test "default community feeds include hybrid reviews and activity without nukige", %{
    titles: titles
  } do
    user = UserFixtures.insert_user!()

    records =
      Map.new(titles, fn {category, vn} ->
        review =
          Repo.insert!(%Review{user_id: user.id, visual_novel_id: vn.id, content: "A review"})

        activity =
          Repo.insert!(%UserActivity{
            user_id: user.id,
            action: :rated,
            entity_type: "rating",
            entity_id: Ecto.UUID.generate(),
            metadata: %{"vn_id" => vn.id}
          })

        {category, %{review: review, activity: activity}}
      end)

    assert {:ok, %{items: reviews}} = Feed.get_feed(nil)
    assert ids(reviews) == MapSet.new([records.vn.review.id, records.adjacent.review.id])

    assert {:ok, %{entries: entries}} = Activities.list_global_activities()

    assert ids(Enum.map(entries, & &1.representative)) ==
             MapSet.new([records.vn.activity.id, records.adjacent.activity.id])
  end

  test "user updates preserve the retired preference instead of accepting changes" do
    user = %User{show_adjacent: false}
    changeset = User.changeset(user, %{show_adjacent: true, show_nukige: true})

    refute Ecto.Changeset.get_field(changeset, :show_adjacent)
    assert Ecto.Changeset.get_field(changeset, :show_nukige)
  end

  defp ids(rows), do: MapSet.new(rows, & &1.id)
end

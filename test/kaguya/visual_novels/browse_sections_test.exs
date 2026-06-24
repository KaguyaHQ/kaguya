defmodule Kaguya.VisualNovels.BrowseSectionsTest do
  # Pure config / no DB — async safe.
  use ExUnit.Case, async: true

  alias Kaguya.VisualNovels.BrowseSections

  describe "all/0" do
    test "returns the explore-mode sections in display order" do
      assert [%{id: :popular}, %{id: :avn}, %{id: :romance}, %{id: :otome}, %{id: :free_on_itch}] =
               BrowseSections.all()
    end

    test "every section has a filters map and a sort_by (atom or nil)" do
      for %{id: id, filters: filters, sort_by: sort_by} <- BrowseSections.all() do
        assert is_atom(id)
        assert is_map(filters), "#{id} filters must be a map"
        assert is_nil(sort_by) or is_atom(sort_by), "#{id} sort_by must be atom or nil"
      end
    end

    test "AVN section filters by the curated is_avn flag" do
      avn = BrowseSections.get(:avn)
      assert avn.filters[:is_avn] == true
    end

    test "Otome section filters by the otome-game tag slug and lets resolver pick relevance sort" do
      otome = BrowseSections.get(:otome)
      assert otome.filters[:include_tags] == ["otome-game"]
      assert otome.sort_by == nil
    end

    test "Free-on-itch section uses the compound free_on_stores filter" do
      free_on_itch = BrowseSections.get(:free_on_itch)
      assert free_on_itch.filters[:free_on_stores] == ["itch"]
    end
  end

  describe "get/1" do
    test "returns nil for an unknown id" do
      assert BrowseSections.get(:does_not_exist) == nil
    end

    test "round-trips every id from all/0" do
      for %{id: id} = section <- BrowseSections.all() do
        assert BrowseSections.get(id) == section
      end
    end
  end

  describe "filter shapes are accepted by the resolver's cacheable filter list" do
    # Defensive: if someone adds a new filter to a section but forgets to
    # extend @cacheable_filter_keys, it would silently miss the cache.
    @cacheable_keys ~w(
      include_tags exclude_tags development_status length_category
      original_languages available_languages available_platforms engines
      vndb_rating_gte vndb_rating_lte average_rating_gte average_rating_lte
      ratings_count_gte ratings_count_lte released_after_year released_before_year
      include_nukige include_adjacent has_ero available_on_stores free_on_stores is_avn
    )a

    test "every section's filter keys are cacheable" do
      for %{id: id, filters: filters} <- BrowseSections.all(),
          key <- Map.keys(filters) do
        assert key in @cacheable_keys,
               "section #{id}: filter key #{inspect(key)} is not in @cacheable_filter_keys; " <>
                 "the cache would silently miss"
      end
    end
  end
end

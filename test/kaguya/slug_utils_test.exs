defmodule Kaguya.SlugUtilsTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Utils
  alias Kaguya.Utils.{SlugUtils, TextPreview}
  alias Kaguya.VisualNovels.VisualNovel

  test "batch slugs preserve order and resolve year and numeric collisions" do
    for slug <- ["winter-story", "winter-story-2020", "winter-story-2020-1"] do
      Repo.insert!(%VisualNovel{title: "Existing", slug: slug})
    end

    items = [
      %{title: "Winter Story", year: 2020},
      %{title: "Winter Story", year: 2020},
      %{title: "Winter Story", year: nil}
    ]

    result =
      SlugUtils.build_unique_slugs(items, VisualNovel, :slug, & &1.title, year_fun: & &1.year)

    assert Enum.map(result, & &1._slug) == [
             "winter-story-2020-2",
             "winter-story-2020-3",
             "winter-story-1"
           ]

    assert Enum.map(result, & &1.year) == [2020, 2020, nil]
  end

  test "single slugs use the year before numeric suffixes, including false dates" do
    for slug <- ["summer-story", "summer-story-2021", "summer-story-2021-1"] do
      Repo.insert!(%VisualNovel{title: "Existing", slug: slug})
    end

    assert Utils.generate_unique_slug("Summer Story", VisualNovel, release_date: ~D[2021-01-01]) ==
             "summer-story-2021-2"

    assert Utils.generate_unique_slug("Summer Story", VisualNovel, release_date: false) ==
             "summer-story-1"
  end

  test "word truncation counts Unicode graphemes and keeps existing spacing behavior" do
    assert TextPreview.truncate_on_words("café 月 hello", 6) == "café 月..."
    assert TextPreview.truncate_on_words("longword short", 3) == "..."
    assert TextPreview.truncate_on_words("a  b", 3) == "a ..."
  end
end

defmodule KaguyaWeb.SEOTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.SEO
  alias KaguyaWeb.SEO.JsonLd

  describe "vn/1" do
    test "builds title, description, canonical and screenshot OG for a fully-loaded VN" do
      vn = %{
        slug: "fate-stay-night",
        title: "Fate/stay night",
        description: "A 2004 visual novel by Type-Moon.",
        release_date: "2004-01-30",
        average_rating: 8.6,
        ratings_count: 1200,
        reviews_count: 240,
        length_minutes: 4000,
        images: %{
          small: "https://images.kaguya.io/visual_novels/v1-128w.webp",
          medium: "https://images.kaguya.io/visual_novels/v1-256w.webp",
          large: "https://images.kaguya.io/visual_novels/v1-512w.webp",
          xl: "https://images.kaguya.io/visual_novels/v1-1024w.webp"
        },
        featured_screenshot: %{
          large: "https://images.kaguya.io/screenshots/s1-1920w.webp"
        },
        producers: [
          %{role: "developer", producer: %{name: "Type-Moon", slug: "type-moon"}}
        ],
        tags: []
      }

      seo = SEO.vn(vn)

      assert seo.page_title == "Fate/stay night by Type-Moon"
      assert seo.canonical_url == "https://kaguya.io/vn/fate-stay-night"
      assert seo.og_title == "Fate/stay night by Type-Moon"
      assert seo.og_url == "https://kaguya.io/vn/fate-stay-night"
      assert seo.og_type == "website"
      assert seo.og_image == "https://images.kaguya.io/screenshots/s1-1920w.webp"
      assert seo.og_image_width == 1200
      assert seo.og_image_height == 630
      assert seo.twitter_card == "summary_large_image"
      assert seo.twitter_image == "https://images.kaguya.io/screenshots/s1-1920w.webp"
      assert seo.meta_description == "A 2004 visual novel by Type-Moon."
      assert seo.meta_robots == nil
      assert seo.json_ld =~ "\"@type\":\"VideoGame\""
      assert seo.json_ld =~ "\"ratingCount\":1200"
    end

    test "falls back to cover image and summary card when no featured screenshot" do
      vn = %{
        slug: "muv-luv",
        title: "Muv-Luv",
        description: "",
        images: %{large: "https://images.kaguya.io/visual_novels/v2-512w.webp"},
        featured_screenshot: %{},
        producers: [%{producer: %{name: "âge"}}],
        tags: []
      }

      seo = SEO.vn(vn)

      assert seo.og_image == "https://images.kaguya.io/visual_novels/v2-512w.webp"
      assert seo.og_image_width == nil
      assert seo.og_image_height == nil
      assert seo.twitter_card == "summary"
    end

    test "builds fallback description when vn description is blank" do
      vn = %{
        slug: "x",
        title: "Sample VN",
        description: "",
        release_date: "2020-05-01",
        average_rating: 7.5,
        ratings_count: 10,
        length_minutes: 400,
        images: %{},
        featured_screenshot: %{},
        producers: [%{producer: %{name: "Studio X"}}],
        tags: [
          %{name: "Romance", spoiler_level: "NONE"},
          %{name: "School Life", spoiler_level: "NONE"}
        ]
      }

      seo = SEO.vn(vn)

      assert seo.meta_description ==
               "Sample VN is a visual novel by Studio X (2020). Short length. Rated 7.5/10. Romance, School Life."
    end

    test "uses Unknown Developer when producers list is empty" do
      vn = %{
        slug: "y",
        title: "Y",
        description: "Desc.",
        images: %{},
        featured_screenshot: %{},
        producers: [],
        tags: []
      }

      seo = SEO.vn(vn)
      assert seo.page_title == "Y by Unknown Developer"
    end

    test "truncates long descriptions at 300 chars with ellipsis" do
      long = String.duplicate("a", 500)

      vn = %{
        slug: "z",
        title: "Z",
        description: long,
        images: %{},
        featured_screenshot: %{},
        producers: [%{producer: %{name: "P"}}],
        tags: []
      }

      seo = SEO.vn(vn)
      assert String.length(seo.meta_description) == 300
      assert String.ends_with?(seo.meta_description, "…")
    end

    test "vn_not_found is noindexed like every other not-found state" do
      seo = SEO.vn_not_found()
      assert seo.meta_robots == "noindex,follow"
      assert seo.json_ld == nil
      assert seo.page_title == "Visual Novel Not Found"
    end
  end

  describe "developer/2" do
    test "builds Producer title, profile OG type, 155-char description" do
      producer = %{
        slug: "type-moon",
        name: "Type-Moon",
        description: "A Japanese visual novel studio.",
        producer_type: "company"
      }

      seo = SEO.developer(producer, total_count: 12, first_vn_title: "Fate/stay night")

      assert seo.page_title == "Type-Moon (Visual Novel Producer)"
      assert seo.canonical_url == "https://kaguya.io/developer/type-moon"
      assert seo.og_type == "profile"
      assert seo.og_image == nil
      assert seo.twitter_card == "summary"
      assert seo.twitter_image == nil
      assert seo.meta_description == "A Japanese visual novel studio."
      assert seo.json_ld =~ "\"@type\":\"Organization\""
    end

    test "builds fallback description with type and first-vn when description is blank" do
      producer = %{slug: "p", name: "Studio P", description: nil, producer_type: "amateur"}

      seo = SEO.developer(producer, total_count: 3, first_vn_title: "Foo")

      assert seo.meta_description ==
               "Studio P is a indie producer with 3 visual novels listed on Kaguya, including Foo."
    end

    test "slices fallback description to 155 chars" do
      producer = %{
        slug: "p",
        name: "P",
        description: String.duplicate("a", 500),
        producer_type: nil
      }

      seo = SEO.developer(producer, total_count: 0)

      assert String.length(seo.meta_description) == 155
    end

    test "developer_not_found is noindexed" do
      seo = SEO.developer_not_found()
      assert seo.meta_robots == "noindex,follow"
      assert seo.page_title == "Producer Not Found • Kaguya"
    end
  end

  describe "list/4" do
    test "builds title with bullet, ItemList JSON-LD with positions" do
      owner = %{username: "alice", display_name: "Alice"}

      list = %{
        slug: "favorites",
        name: "Favorites",
        description: "My favorite visual novels."
      }

      items = [
        %{visual_novel: %{slug: "vn-a", title: "VN A", images: %{medium: "https://img/a.webp"}}},
        %{visual_novel: %{slug: "vn-b", title: "VN B", images: %{medium: "https://img/b.webp"}}}
      ]

      seo = SEO.list(list, owner, items, page: 1, page_size: 100, total_count: 2)

      assert seo.page_title == "Favorites, a list of visual novels by Alice • Kaguya"
      assert seo.canonical_url == "https://kaguya.io/@alice/list/favorites"
      assert seo.og_title == "Favorites"
      assert seo.og_type == "website"
      assert seo.og_image == "https://img/a.webp"
      assert seo.twitter_card == "summary"
      assert seo.json_ld =~ "\"@type\":\"ItemList\""
      assert seo.json_ld =~ "\"position\":1"
      assert seo.json_ld =~ "\"position\":2"
      assert seo.json_ld =~ "https://kaguya.io/vn/vn-a"
    end

    test "uses 'a Kaguya reader' fallback when owner has no display_name" do
      owner = %{username: "bob"}
      list = %{slug: "nope", name: nil, description: nil}

      seo = SEO.list(list, owner, [], page: 1, page_size: 100, total_count: 0)

      assert seo.page_title =~ "by bob • Kaguya"
    end

    test "offsets position by (page - 1) * page_size" do
      owner = %{username: "alice"}
      list = %{slug: "favs", name: "Favs", description: nil}
      items = [%{visual_novel: %{slug: "x", title: "X", images: %{}}}]

      seo = SEO.list(list, owner, items, page: 3, page_size: 100, total_count: 250)

      assert seo.json_ld =~ "\"position\":201"
    end

    test "list_not_found is noindexed" do
      seo = SEO.list_not_found()
      assert seo.meta_robots == "noindex,follow"
      assert seo.page_title == "List Not Found • Kaguya"
    end
  end

  describe "JsonLd builders" do
    test "website returns root WebSite schema" do
      assert JsonLd.website() == %{
               "@context" => "https://schema.org",
               "@type" => "WebSite",
               "url" => "https://kaguya.io/",
               "name" => "Kaguya",
               "alternateName" => "kaguya.io"
             }
    end

    test "video_game omits aggregateRating when ratings_count is 0" do
      vn = %{
        slug: "x",
        title: "X",
        description: "d",
        images: %{},
        producers: [],
        ratings_count: 0,
        average_rating: 0,
        reviews_count: 0
      }

      json = JsonLd.video_game(vn)
      refute Map.has_key?(json, "aggregateRating")
    end

    test "video_game includes reviewCount only when > 0" do
      vn = %{
        slug: "x",
        title: "X",
        description: "d",
        images: %{},
        producers: [],
        ratings_count: 5,
        average_rating: 8.0,
        reviews_count: 0
      }

      %{"aggregateRating" => agg} = JsonLd.video_game(vn)
      refute Map.has_key?(agg, "reviewCount")
      assert agg["ratingValue"] == "8.0"
      assert agg["ratingCount"] == 5
    end
  end

  describe "encode/1" do
    test "escapes </ so user-supplied </script> cannot break out of the tag" do
      json = SEO.encode(%{"x" => "</script><script>alert(1)</script>"})
      refute json =~ "</script>"
      assert json =~ "<\\/script>"
    end

    test "leaves plain / unescaped to match Next.js JSON.stringify output" do
      json = SEO.encode(%{"url" => "https://kaguya.io/vn/foo"})
      assert json =~ "https://kaguya.io/vn/foo"
    end
  end
end

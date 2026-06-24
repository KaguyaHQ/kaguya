defmodule Kaguya.SitemapsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.{Discussions, Lists, Repo, Reviews, Sitemaps}
  alias Kaguya.Characters.Character
  alias Kaguya.Producers.Producer
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "generate/1" do
    test "renders public visible lists" do
      owner = UserFixtures.insert_user!(username: "alice")
      vn = insert_vn!("List Sitemap VN")

      {:ok, list} = Lists.create_list(%{user_id: owner.id, name: "Alice Picks", vn_ids: [vn.id]})

      {:ok, private_list} =
        Lists.create_list(%{
          user_id: owner.id,
          name: "Private",
          is_public: false,
          vn_ids: [vn.id]
        })

      {:ok, hidden_list} =
        Lists.create_list(%{user_id: owner.id, name: "Hidden", vn_ids: [vn.id]})

      {:ok, _hidden_list} = Lists.hide_list(hidden_list.id)

      body = Sitemaps.generate([:vnlists])["vnlists-0.xml"]

      assert body =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
      assert body =~ "/@alice/list/#{list.slug}"
      refute body =~ "/@alice/list/#{private_list.slug}"
      refute body =~ "/@alice/list/#{hidden_list.slug}"
      assert body =~ "<lastmod>"
    end

    test "renders public visible reviews" do
      author = UserFixtures.insert_user!(username: "reviewer")
      hidden_author = UserFixtures.insert_user!(username: "hidden_reviewer")
      vn = insert_vn!("Review Sitemap VN")
      hidden_vn = insert_vn!("Hidden Review Sitemap VN")
      hidden_entry_vn = insert_vn!("Hidden VN Sitemap VN")

      {:ok, _review} =
        Reviews.create_review(author.id, vn.id, %{content: long_content("visible")})

      {:ok, hidden_review} =
        Reviews.create_review(hidden_author.id, hidden_vn.id, %{content: long_content("hidden")})

      {:ok, _hidden_review} = Reviews.hide_review(hidden_review.id)

      {:ok, _hidden_entry_review} =
        Reviews.create_review(author.id, hidden_entry_vn.id, %{
          content: long_content("hidden vn")
        })

      hidden_entry_vn
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      body = Sitemaps.generate([:reviews])["reviews-0.xml"]

      assert body =~ "/@reviewer/reviews/#{vn.slug}"
      refute body =~ "/@hidden_reviewer/reviews/#{hidden_vn.slug}"
      refute body =~ "/@reviewer/reviews/#{hidden_entry_vn.slug}"
      assert body =~ "<lastmod>"
    end

    test "renders standalone and entity-scoped visible posts" do
      author = UserFixtures.insert_user!(username: "post_author")
      target = UserFixtures.insert_user!(username: "target_user")
      vn = insert_vn!("Discussion Sitemap VN")

      {:ok, general_post} =
        Discussions.create_post(author.id, %{
          title: "General sitemap thread",
          content: "Standalone discussion body",
          category_type: :general
        })

      {:ok, vn_post} =
        Discussions.create_post(author.id, %{
          title: "VN sitemap thread",
          content: "Visual novel discussion body",
          category_type: :visual_novel,
          entity_id: vn.id
        })

      {:ok, user_post} =
        Discussions.create_post(author.id, %{
          title: "User sitemap thread",
          content: "User discussion body",
          category_type: :user,
          entity_id: target.id
        })

      body = Sitemaps.generate([:discussions])["discussions-0.xml"]

      assert body =~ "/discussions/p/#{general_post.short_id}/#{general_post.slug}"
      assert body =~ "/vn/#{vn.slug}/discussions/#{vn_post.short_id}"
      assert body =~ "/@#{target.username}/discussions/#{user_post.short_id}"
      assert body =~ "<lastmod>"
    end

    test "excludes hidden, deleted, and hidden-entity posts" do
      author = UserFixtures.insert_user!(username: "hidden_post_author")
      vn = insert_vn!("Hidden Discussion Sitemap VN")
      hidden_entity_vn = insert_vn!("Hidden Entity Discussion Sitemap VN")

      {:ok, hidden_post} =
        Discussions.create_post(author.id, %{
          title: "Hidden sitemap thread",
          content: "Hidden discussion body",
          category_type: :general
        })

      {:ok, deleted_post} =
        Discussions.create_post(author.id, %{
          title: "Deleted sitemap thread",
          content: "Deleted discussion body",
          category_type: :general
        })

      {:ok, hidden_entity_post} =
        Discussions.create_post(author.id, %{
          title: "Hidden entity sitemap thread",
          content: "Hidden entity discussion body",
          category_type: :visual_novel,
          entity_id: hidden_entity_vn.id
        })

      {:ok, visible_post} =
        Discussions.create_post(author.id, %{
          title: "Visible entity sitemap thread",
          content: "Visible entity discussion body",
          category_type: :visual_novel,
          entity_id: vn.id
        })

      {:ok, _hidden_post} = Discussions.hide_post(hidden_post.id)
      {:ok, _deleted_post} = Discussions.delete_post(deleted_post.id, author.id)

      hidden_entity_vn
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      body = Sitemaps.generate([:discussions])["discussions-0.xml"]

      assert body =~ "/vn/#{vn.slug}/discussions/#{visible_post.short_id}"
      refute body =~ hidden_post.short_id
      refute body =~ deleted_post.short_id
      refute body =~ hidden_entity_post.short_id
    end

    test "renders visible characters with image entries" do
      character = insert_character!("Sitemap Character", vndb_image_id: "ch12345")
      hidden = insert_character!("Hidden Sitemap Character")

      hidden
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      body = Sitemaps.generate([:characters])["characters-0.xml"]

      assert body =~ ~s(xmlns:image="http://www.google.com/schemas/sitemap-image/1.1")
      assert body =~ "/character/#{character.slug}"
      assert body =~ "https://s.vndb.org/ch/45/12345.jpg"
      refute body =~ "/character/#{hidden.slug}"
      assert body =~ "<lastmod>"
    end

    test "renders visible visual novels with image entries" do
      cover_url = "https://images.example.test/sitemap-vn.webp"
      vn = insert_vn!("Sitemap VN", temp_image_url: cover_url)
      hidden = insert_vn!("Hidden Sitemap VN")

      hidden
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      body = Sitemaps.generate([:vns])["vns-0.xml"]

      assert body =~ ~s(xmlns:image="http://www.google.com/schemas/sitemap-image/1.1")
      assert body =~ "/vn/#{vn.slug}"
      assert body =~ cover_url
      refute body =~ "/vn/#{hidden.slug}"
      assert body =~ "<lastmod>"
    end

    test "renders the homepage and core navigation paths without lastmod" do
      body = Sitemaps.generate([:static])["static-0.xml"]
      base = KaguyaWeb.Endpoint.url() |> String.trim_trailing("/")

      assert body =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
      assert body =~ "<loc>#{base}/</loc>"
      assert body =~ "<loc>#{base}/browse</loc>"
      assert body =~ "<loc>#{base}/lists</loc>"
      assert body =~ "<loc>#{base}/members</loc>"
      refute body =~ "<lastmod>"
    end

    test "renders visible producers and excludes hidden ones" do
      producer = insert_producer!("Visible Sitemap Producer")
      hidden = insert_producer!("Hidden Sitemap Producer")

      hidden
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      body = Sitemaps.generate([:producers])["producers-0.xml"]

      assert body =~ "/developer/#{producer.slug}"
      refute body =~ "/developer/#{hidden.slug}"
      assert body =~ "<lastmod>"
    end
  end

  describe "render_index/2" do
    test "renders canonical app sitemap URLs" do
      body =
        Sitemaps.render_index(
          ["vns-0.xml", "reviews-0.xml"],
          ~U[2026-05-22 00:00:00Z]
        )

      base = KaguyaWeb.Endpoint.url() |> String.trim_trailing("/")

      assert body =~ ~s(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
      assert body =~ "<loc>#{base}/sitemap/vns-0.xml</loc>"
      assert body =~ "<loc>#{base}/sitemap/reviews-0.xml</loc>"
      assert body =~ "<lastmod>2026-05-22T00:00:00Z</lastmod>"
    end
  end

  defp insert_producer!(name, attrs \\ []) do
    attrs = Map.new(attrs)
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %Producer{}
    |> Producer.changeset(Map.merge(%{name: "#{name} #{suffix}"}, attrs))
    |> Repo.insert!()
  end

  defp insert_vn!(title, attrs \\ []) do
    attrs = Map.new(attrs)
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(
      Map.merge(%{title: "#{title} #{suffix}", original_language: "en"}, attrs)
    )
    |> Repo.insert!()
  end

  defp insert_character!(name, attrs \\ []) do
    attrs = Map.new(attrs)
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %Character{}
    |> Character.changeset(Map.merge(%{name: "#{name} #{suffix}"}, attrs))
    |> Repo.insert!()
  end

  defp long_content(seed),
    do: seed <> String.duplicate(" filler for the 40-char min length", 5)
end

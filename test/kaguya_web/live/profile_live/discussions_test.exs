defmodule KaguyaWeb.ProfileLive.DiscussionsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Discussions.Post
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/discussions" do
    test "renders the production empty state instead of the placeholder", %{conn: conn} do
      _owner =
        UserFixtures.insert_user!(username: "quiet_discussions", display_name: "Quiet")

      {:ok, _view, html} = live(conn, "/@quiet_discussions/discussions")

      assert html =~ "No discussions yet."
      refute html =~ "coming soon"
    end

    test "renders user posts with preview, counts, entity tag, and canonical href", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "talker", display_name: "Talker")
      vn = insert_vn!("Post VN")
      post = insert_post!(owner, vn)

      {:ok, _view, html} = live(conn, "/@talker/discussions")

      assert html =~ "A profile discussion"
      assert html =~ "bold preview"
      assert html =~ "3"
      assert html =~ "2"
      assert html =~ vn.title
      assert html =~ ~s(href="/vn/#{vn.slug}/discussions/#{post.short_id}")
      refute html =~ "coming soon"
    end

    test "owner sees the start-post CTA", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "post_owner", display_name: "Owner")
      vn = insert_vn!("Owner Post VN")
      insert_post!(owner, vn)

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@post_owner/discussions")

      assert html =~ "Start a new post"
      assert html =~ ~s(phx-click="start_new_post")
    end
  end

  defp insert_post!(owner, vn) do
    post =
      %Post{}
      |> Post.changeset(%{
        title: "A profile discussion",
        content: "A **bold preview** with [a link](https://example.com).",
        user_id: owner.id,
        category_type: :visual_novel,
        entity_id: vn.id
      })
      |> Repo.insert!()

    Repo.update_all(
      from(p in Post, where: p.id == ^post.id),
      set: [comments_count: 3, likes_count: 2]
    )

    Repo.get!(Post, post.id)
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end

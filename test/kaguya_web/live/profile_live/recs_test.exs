defmodule KaguyaWeb.ProfileLive.RecsTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Recommendations.UserVnRecommendation
  alias Kaguya.Repo
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves
  alias Kaguya.Tags.Tag
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VNTag
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/recs" do
    test "renders other-user empty copy instead of the placeholder", %{conn: conn} do
      _owner = UserFixtures.insert_user!(username: "empty_recs", display_name: "Empty")

      {:ok, _view, html} = live(conn, "/@empty_recs/recs")

      assert html =~ "No recommendations to show yet."
      assert html =~ "Once they rate or shelve more VNs"
      refute html =~ "coming soon"
    end

    test "renders recommendation cards and hides feedback for visitors", %{conn: conn} do
      owner =
        UserFixtures.insert_user!(username: "rec_public", display_name: "Rec Public")

      target = insert_vn!("Target VN")
      reason = insert_vn!("Reason VN")
      insert_rating!(owner, reason, 4.5)
      insert_rec!(owner, target, reason)

      {:ok, _view, html} = live(conn, "/@rec_public/recs")

      assert html =~ target.title
      assert html =~ "Because they rated #{reason.title} 4.5★"
      assert html =~ "%"
      refute html =~ "Wishlist"
      refute html =~ "Not interested"
    end

    test "owner feedback actions update optimistically", %{conn: conn} do
      owner = UserFixtures.insert_user!(username: "rec_owner", display_name: "Rec Owner")
      target = insert_vn!("Owner Target")
      reason = insert_vn!("Owner Reason")
      insert_rating!(owner, reason, 4.0)
      insert_rec!(owner, target, reason)

      {:ok, view, html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@rec_owner/recs")

      assert html =~ "Wishlist"
      assert html =~ "Not interested"

      html =
        view
        |> element(~s(button[aria-label="Add to wishlist"]))
        |> render_click()

      assert html =~ "Wishlisted"
    end

    test "hide wishlisted filter uses the owner's library state", %{conn: conn} do
      owner =
        UserFixtures.insert_user!(username: "rec_filtered", display_name: "Filtered")

      target = insert_vn!("Filtered Target")
      reason = insert_vn!("Filtered Reason")
      insert_rating!(owner, reason, 4.0)
      insert_rec!(owner, target, reason)
      {:ok, _} = Shelves.set_reading_status(owner.id, target.id, %{status: :want_to_read})

      {:ok, _view, html} =
        conn
        |> Plug.Test.init_test_session(%{"current_user_id" => owner.id})
        |> live("/@rec_filtered/recs?hideWishlisted=1")

      assert html =~ "No recommendations match the current filters."
      assert html =~ "Wishlisted hidden"
      refute html =~ target.title
    end

    test "renders tag filter options for client-side search without changing the recommendation list",
         %{conn: conn} do
      owner =
        UserFixtures.insert_user!(username: "rec_tag_search", display_name: "Tag Search")

      reason = insert_vn!("Tag Search Reason")
      romance_target = insert_vn!("Alpha Candidate")
      time_target = insert_vn!("Beta Candidate")
      insert_rating!(owner, reason, 4.0)
      insert_rec!(owner, romance_target, reason)
      insert_rec!(owner, time_target, reason)

      romance = insert_tag!("Romance")
      time_travel = insert_tag!("Time Travel")
      attach_tag!(romance_target, romance)
      attach_tag!(time_target, time_travel)

      {:ok, view, html} = live(conn, "/@rec_tag_search/recs")

      assert html =~ romance_target.title
      assert html =~ time_target.title

      assert has_element?(
               view,
               ~s(#rec-filter-tag-options button[phx-value-slug="#{romance.slug}"])
             )

      assert has_element?(
               view,
               ~s(#rec-filter-tag-options button[phx-value-slug="#{time_travel.slug}"])
             )

      assert html =~ romance_target.title
      assert html =~ time_target.title

      assert has_element?(
               view,
               ~s(#rec-filter-tag-options button[data-client-tag-filter-option][data-tag-name="#{String.downcase(romance.name)}"])
             )

      assert has_element?(
               view,
               ~s(#rec-filter-tag-options button[data-client-tag-filter-option][data-tag-name="#{String.downcase(time_travel.name)}"])
             )
    end

    test "selecting a tag filter patches the URL and narrows recommendations", %{conn: conn} do
      owner =
        UserFixtures.insert_user!(
          username: "rec_tag_select",
          display_name: "Tag Select"
        )

      reason = insert_vn!("Tag Select Reason")
      romance_target = insert_vn!("Gamma Candidate")
      time_target = insert_vn!("Delta Candidate")
      insert_rating!(owner, reason, 4.0)
      insert_rec!(owner, romance_target, reason)
      insert_rec!(owner, time_target, reason)

      romance = insert_tag!("Romance")
      time_travel = insert_tag!("Time Travel")
      attach_tag!(romance_target, romance)
      attach_tag!(time_target, time_travel)

      {:ok, view, _html} = live(conn, "/@rec_tag_select/recs")

      view
      |> element(~s(#rec-filter-tag-options button[phx-value-slug="#{romance.slug}"]))
      |> render_click()

      assert_patched(view, "/@rec_tag_select/recs?tag=#{romance.slug}")

      html = render(view)
      assert html =~ romance_target.title
      refute html =~ time_target.title
      assert html =~ romance.name
    end
  end

  defp insert_rec!(owner, target, reason) do
    %UserVnRecommendation{}
    |> UserVnRecommendation.changeset(%{
      user_id: owner.id,
      visual_novel_id: target.id,
      score: 10.0,
      ease_score: 10.0,
      rank: 1,
      reasons: [%{"visual_novel_id" => reason.id, "contribution" => 8.0}],
      total_positive_contribution: 10.0,
      model_version: "test",
      generated_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp insert_tag!(name) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    %Tag{}
    |> Tag.changeset(%{
      name: "#{name} #{suffix}",
      slug: "#{Slug.slugify(name)}-#{suffix}",
      source: "manual",
      category: :content,
      kind: :theme
    })
    |> Repo.insert!()
  end

  defp attach_tag!(vn, tag) do
    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      relevance_score: 0.8,
      spoiler_level: :none
    })
    |> Repo.insert!()
  end

  defp insert_rating!(owner, vn, rating) do
    %Rating{}
    |> Rating.changeset(%{user_id: owner.id, visual_novel_id: vn.id, rating: rating})
    |> Repo.insert!()
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end

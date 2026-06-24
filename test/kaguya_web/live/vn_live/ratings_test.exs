defmodule KaguyaWeb.VNLive.RatingsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Reviews
  alias Kaguya.Reviews.Ratings
  alias Kaguya.Reviews.Rating
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "VN ratings chart links each bucket to the rater page", %{conn: conn} do
    vn = insert_vn!("Rating Link VN", "rating-link-vn")
    [first, second, third] = insert_users(["first_rater", "second_rater", "third_rater"])

    {:ok, _} = Ratings.create_rating(first.id, vn.id, 4.0)
    {:ok, _} = Ratings.create_rating(second.id, vn.id, 4.0)
    {:ok, _} = Ratings.create_rating(third.id, vn.id, 5.0)

    set_status!(first, vn, :currently_reading)
    set_status!(second, vn, :want_to_read)

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}")

    assert html =~ ~s(href="/vn/#{vn.slug}/ratings/4")
    assert html =~ ~s(href="/vn/#{vn.slug}/ratings/4.5")
  end

  test "renders users who gave the selected rating", %{conn: conn} do
    vn = insert_vn!("Raters Page VN", "raters-page-vn")
    [target, other] = insert_users(["target_rater", "other_rater"])

    {:ok, _} = Ratings.create_rating(target.id, vn.id, 4.0)
    {:ok, _} = Ratings.create_rating(other.id, vn.id, 5.0)

    {:ok, _review} =
      Reviews.create_review(target.id, vn.id, %{
        content: "This review has enough text to satisfy the validation rule."
      })

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/ratings/4")

    assert html =~ "Everyone who has rated"
    assert html =~ "target_rater"
    assert html =~ "Review"
    refute html =~ "other_rater"
    # Per-rating rater lists are thin and unbounded by rating value — noindex.
    assert html =~ ~s(<meta name="robots" content="noindex,follow")
  end

  test "renders compact calendar labels for rater timestamps", %{conn: conn} do
    vn = insert_vn!("Timestamp Raters VN", "timestamp-raters-vn")
    [target] = insert_users(["timed_rater"])

    {:ok, _} = Ratings.create_rating(target.id, vn.id, 4.0)

    rated_at = DateTime.utc_now() |> DateTime.add(-3, :hour) |> DateTime.truncate(:second)

    Repo.update_all(
      from(r in Rating, where: r.user_id == ^target.id and r.visual_novel_id == ^vn.id),
      set: [updated_at: rated_at]
    )

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/ratings/4")

    assert html =~ "timed_rater"
    assert html =~ "3h"
    refute html =~ Regex.escape(Calendar.strftime(rated_at, "%b %-d, %Y"))
  end

  defp insert_vn!(title, slug) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: title,
      slug: slug,
      description: "A" <> String.duplicate(" ratings visual novel description", 3)
    })
    |> Repo.insert!()
  end

  defp insert_users(usernames) do
    Enum.map(usernames, fn username ->
      UserFixtures.insert_user!(username: username, display_name: username)
    end)
  end

  defp set_status!(user, vn, status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(ReadingStatus, user_id: user.id, visual_novel_id: vn.id) do
      nil ->
        %ReadingStatus{}
        |> ReadingStatus.changeset(%{
          user_id: user.id,
          visual_novel_id: vn.id,
          status: status,
          library_added_at: now
        })
        |> Repo.insert!()

      reading_status ->
        reading_status
        |> ReadingStatus.changeset(%{status: status, library_added_at: now})
        |> Repo.update!()
    end
  end
end

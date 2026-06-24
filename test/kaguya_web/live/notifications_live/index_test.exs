defmodule KaguyaWeb.NotificationsLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Social.Notification
  alias Kaguya.Test.UserFixtures
  alias KaguyaWeb.NotificationsLive.Data

  test "renders migrated notification cards without the manual mark-all button", %{conn: conn} do
    user = UserFixtures.insert_user!()
    actor = UserFixtures.insert_user!(username: "reader_actor")

    insert_notification!(user, actor,
      vn_title: "Test VN",
      vn_review_path: "/vn/test-vn/reviews/#{user.username}",
      text_preview: "A short comment preview.",
      vn_image_url: "https://images.example.test/cover.webp"
    )

    {:ok, _view, html} = conn |> conn_for(user) |> live("/notifications")

    assert html =~ "reader_actor"
    assert html =~ "commented on your review of"
    assert html =~ "Test VN"
    assert html =~ "A short comment preview."
    assert html =~ "https://images.example.test/cover.webp"
    assert html =~ ~s(phx-value-url="/@#{user.username}/reviews/test-vn")
    refute html =~ "Mark all as read"
  end

  test "normalizes notification links to match Next.js routes" do
    assert normalized_link(:follow, :user, %{
             actor_snapshots: [%{id: Ecto.UUID.generate(), username: "vas"}]
           }) == "/@vas"

    assert normalized_link(:like, :review, %{vn_review_path: "/vn/the-house/reviews/vas"}) ==
             "/@vas/reviews/the-house"

    assert normalized_link(:new_comment, :review, %{
             vn_review_path: "/@vas/reviews/the-house"
           }) == "/@vas/reviews/the-house"

    assert normalized_link(:like, :comment, %{
             post_short_id: "abc123",
             post_slug: "hello-world"
           }) == "/discussions/p/abc123/hello-world"

    assert normalized_link(:reply, :comment, %{
             vn_review_path: "/vn/the-house/reviews/vas"
           }) == "/@vas/reviews/the-house"

    assert normalized_link(:new_comment, :vn_list, %{
             list_creator_username: "vas",
             list_slug: "favorites"
           }) == "/@vas/list/favorites"

    assert normalized_link(:report_reviewed, :report, %{
             report_entity_path: "/vn/the-house-in-fata-morgana"
           }) == "/vn/the-house-in-fata-morgana"
  end

  test "visiting the page marks all unread notifications read", %{conn: conn} do
    user = UserFixtures.insert_user!()
    actor = UserFixtures.insert_user!(username: "passive_reader")
    first = insert_notification!(user, actor, vn_title: "First VN")
    second = insert_notification!(user, actor, vn_title: "Second VN")

    {:ok, _view, _html} = conn |> conn_for(user) |> live("/notifications")

    # Acknowledged in the DB on visit, which clears the navbar bell.
    assert Repo.get!(Notification, first.id).read
    assert Repo.get!(Notification, second.id).read
  end

  test "shows manual Load More button when list grows beyond pagination threshold", %{conn: conn} do
    user = UserFixtures.insert_user!()
    actor = UserFixtures.insert_user!(username: "manual_load_reader")

    for index <- 1..61 do
      insert_notification!(user, actor, vn_title: "Manual VN #{index}")
    end

    {:ok, _view, html} = conn |> conn_for(user) |> live("/notifications?limit=50")

    assert html =~ "Load More"
  end

  defp conn_for(conn, user) do
    Plug.Test.init_test_session(conn, %{current_user_id: user.id})
  end

  defp insert_notification!(user, actor, attrs) do
    metadata =
      %{
        actors_count: 1,
        actor_snapshots: [
          %{
            id: actor.id,
            username: actor.username,
            avatar_url: "https://images.example.test/#{actor.username}.webp"
          }
        ],
        vn_review_path:
          Keyword.get(attrs, :vn_review_path, "/@#{user.username}/reviews/example-vn"),
        vn_title: Keyword.get(attrs, :vn_title, "Example VN"),
        vn_image_url: Keyword.get(attrs, :vn_image_url),
        text_preview: Keyword.get(attrs, :text_preview)
      }

    %Notification{}
    |> Notification.changeset(%{
      user_id: user.id,
      action: :new_comment,
      entity_type: :review,
      entity_id: Ecto.UUID.generate(),
      read: false,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  defp normalized_link(action, entity_type, metadata) do
    %Notification{
      id: Ecto.UUID.generate(),
      action: action,
      entity_type: entity_type,
      read: false,
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    }
    |> Data.normalize_notification()
    |> Map.fetch!(:link)
  end
end

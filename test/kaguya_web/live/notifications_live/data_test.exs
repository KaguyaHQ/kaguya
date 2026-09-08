defmodule KaguyaWeb.NotificationsLive.DataTest do
  use ExUnit.Case, async: true

  alias Kaguya.Social.Notification
  alias Kaguya.Social.Notification.Metadata
  alias KaguyaWeb.NotificationsLive.Data

  test "embedded metadata becomes a plain map without losing notification content" do
    result =
      normalize(%Metadata{vn_title: "Test VN", vn_review_path: "/vn/test-vn/reviews/reader"})

    refute is_struct(result.metadata)
    assert result.metadata.vn_title == "Test VN"
    assert result.link == "/@reader/reviews/test-vn"
  end

  test "map and missing metadata keep their supported fallback behavior" do
    metadata = %{"vn_review_path" => "/vn/test-vn/reviews/reader"}
    result = normalize(metadata)
    assert result.metadata == metadata
    assert result.link == "/@reader/reviews/test-vn"

    result = normalize(nil)
    assert result.metadata == %{}
    assert result.link == "#"
  end

  defp normalize(metadata) do
    Data.normalize_notification(%Notification{
      id: Ecto.UUID.generate(),
      action: :like,
      entity_type: :review,
      read: false,
      metadata: metadata,
      inserted_at: ~U[2026-09-08 00:00:00Z]
    })
  end
end

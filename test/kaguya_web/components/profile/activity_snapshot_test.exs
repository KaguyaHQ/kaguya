defmodule KaguyaWeb.Components.Profile.ActivitySnapshotTest do
  use KaguyaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KaguyaWeb.Components.Profile.ActivitySnapshot

  # The snapshot is a flattened projection of the same activity rows the
  # `/@user/activity` tab renders. It must agree with the shared verb/href
  # source of truth (`Activity.Helpers`) used by the other two feeds, not
  # carry its own divergent copy. These tests pin the agreed wording/links
  # per action so the dedupe can't silently drift.

  @ts ~U[2024-01-01 12:00:00Z]

  defp item(action, attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        action: action,
        metadata: %{},
        inserted_at: @ts,
        entity_type: nil,
        entity_id: nil,
        entity_ref: nil,
        followed_user: nil,
        followed_producer: nil
      },
      attrs
    )
  end

  defp render_one(item) do
    render_component(&ActivitySnapshot.activity_snapshot/1,
      items: [item],
      username: "alice",
      display_name: "Alice"
    )
  end

  test "empty items renders nothing" do
    html =
      render_component(&ActivitySnapshot.activity_snapshot/1,
        items: [],
        username: "alice",
        display_name: "Alice"
      )

    assert String.trim(html) == ""
  end

  test "header links to the activity tab and shows the actor" do
    html =
      render_one(item(:rated, %{metadata: %{"vn_title" => "Clannad", "vn_slug" => "clannad"}}))

    assert html =~ ~s(href="/@alice/activity")
    assert html =~ ~s(href="/@alice")
    assert html =~ "Alice"
  end

  describe "verb wording + target href per action (shared-helper parity)" do
    test ":rated" do
      html =
        render_one(item(:rated, %{metadata: %{"vn_title" => "Clannad", "vn_slug" => "clannad"}}))

      assert html =~ "rated"
      assert html =~ "Clannad"
      assert html =~ ~s(href="/vn/clannad")
    end

    test ":status_changed read" do
      html =
        render_one(
          item(:status_changed, %{
            metadata: %{"status" => "read", "vn_title" => "Clannad", "vn_slug" => "clannad"}
          })
        )

      assert html =~ "read"
      assert html =~ "Clannad"
    end

    test ":status_changed on_hold carries the suffix" do
      html =
        render_one(
          item(:status_changed, %{
            metadata: %{"status" => "on_hold", "vn_title" => "Clannad", "vn_slug" => "clannad"}
          })
        )

      assert html =~ "put"
      assert html =~ "on hold"
    end

    test ":status_changed is case-insensitive (canonical downcases)" do
      html =
        render_one(
          item(:status_changed, %{metadata: %{"status" => "READ", "vn_title" => "Clannad"}})
        )

      assert html =~ "read"
      refute html =~ "updated status of"
    end

    test ":reviewed links to the review url" do
      html =
        render_one(
          item(:reviewed, %{
            metadata: %{
              "vn_title" => "Clannad",
              "vn_slug" => "clannad",
              "review_username" => "bob"
            }
          })
        )

      assert html =~ "reviewed"
      assert html =~ ~s(href="/@bob/reviews/clannad")
    end

    test ":liked_review" do
      html =
        render_one(
          item(:liked_review, %{metadata: %{"vn_title" => "Clannad", "vn_slug" => "clannad"}})
        )

      assert html =~ "liked a review of"
      assert html =~ "Clannad"
    end

    test ":created_list" do
      html =
        render_one(
          item(:created_list, %{
            metadata: %{
              "list_name" => "My Faves",
              "list_slug" => "faves",
              "list_username" => "alice"
            }
          })
        )

      assert html =~ "created"
      assert html =~ "My Faves"
      assert html =~ ~s(href="/@alice/list/faves")
    end

    test ":liked_list" do
      html =
        render_one(
          item(:liked_list, %{
            metadata: %{
              "list_name" => "My Faves",
              "list_slug" => "faves",
              "list_username" => "bob"
            }
          })
        )

      assert html =~ "liked"
      assert html =~ "My Faves"
      assert html =~ ~s(href="/@bob/list/faves")
    end

    test ":voted_tag carries the graded phrase as suffix" do
      html =
        render_one(
          item(:voted_tag, %{
            metadata: %{"tag_name" => "Comedy", "value" => 2},
            entity_ref: %{name: "Clannad", slug: "clannad", entity_type: "visual_novel"}
          })
        )

      assert html =~ "voted"
      assert html =~ "Comedy"
      assert html =~ "a minor element of"
      assert html =~ "Clannad"
    end

    test ":created_entity" do
      html =
        render_one(
          item(:created_entity, %{
            entity_ref: %{name: "Some VN", slug: "some-vn", entity_type: "visual_novel"}
          })
        )

      assert html =~ "added"
      assert html =~ "Some VN"
      assert html =~ "to the database"
    end

    test ":edited_entity links to the revision diff" do
      html =
        render_one(
          item(:edited_entity, %{
            metadata: %{"revision_id" => 7},
            entity_ref: %{name: "Some VN", slug: "some-vn", entity_type: "visual_novel"}
          })
        )

      assert html =~ "edited"
      assert html =~ "Some VN"
      assert html =~ ~s(href="/vn/some-vn/history/7")
    end

    test ":reverted_entity carries the revision suffix" do
      html =
        render_one(
          item(:reverted_entity, %{
            metadata: %{"reverted_from_revision" => 3},
            entity_ref: %{name: "Some VN", slug: "some-vn", entity_type: "visual_novel"}
          })
        )

      assert html =~ "reverted"
      assert html =~ "to revision #3"
    end

    test ":followed a user" do
      html =
        render_one(
          item(:followed, %{
            metadata: %{"followed_username" => "bob", "followed_display_name" => "Bob"}
          })
        )

      assert html =~ "followed"
      assert html =~ "Bob"
    end

    test ":followed a producer" do
      html =
        render_one(
          item(:followed, %{
            metadata: %{"followed_producer_name" => "Key", "followed_producer_slug" => "key"},
            followed_producer: %{id: 1, name: "Key", slug: "key"}
          })
        )

      assert html =~ "followed"
      assert html =~ "Key"
    end

    test ":recommended_similar uses canonical 'on <source>' wording" do
      html =
        render_one(
          item(:recommended_similar, %{
            metadata: %{
              "similar_vn_title" => "Kanon",
              "similar_vn_slug" => "kanon",
              "source_vn_title" => "Clannad",
              "source_vn_slug" => "clannad"
            }
          })
        )

      assert html =~ "recommended"
      assert html =~ "Kanon"
      assert html =~ "on Clannad"
      refute html =~ "as similar to"
    end

    test ":imported_vndb links the library (no dead target)" do
      html = render_one(item(:imported_vndb))
      assert html =~ "imported"
      assert html =~ "their library"
      assert html =~ "from VNDB"
      assert html =~ ~s(href="/@alice/library")
    end

    test ":liked_screenshot" do
      html =
        render_one(
          item(:liked_screenshot, %{metadata: %{"vn_title" => "Clannad", "vn_slug" => "clannad"}})
        )

      assert html =~ "liked a screenshot from"
      assert html =~ ~s(href="/vn/clannad/screenshots")
    end

    test ":liked_cover" do
      html =
        render_one(
          item(:liked_cover, %{metadata: %{"vn_title" => "Clannad", "vn_slug" => "clannad"}})
        )

      assert html =~ "liked a cover from"
      assert html =~ ~s(href="/vn/clannad/covers")
    end

    test ":added_quote" do
      html =
        render_one(
          item(:added_quote, %{
            entity_ref: %{name: "Clannad", slug: "clannad", entity_type: "visual_novel"}
          })
        )

      assert html =~ "added a quote from"
      assert html =~ "Clannad"
    end

    test ":liked_quote" do
      html =
        render_one(
          item(:liked_quote, %{
            entity_ref: %{name: "Clannad", slug: "clannad", entity_type: "visual_novel"}
          })
        )

      assert html =~ "liked a quote from"
      assert html =~ "Clannad"
    end

    test ":created_post" do
      html = render_one(item(:created_post, %{metadata: %{"post_title" => "Best VNs"}}))
      assert html =~ "posted"
      assert html =~ "Best VNs"
    end

    test ":commented on a discussion renders verb + preview" do
      html =
        render_one(
          item(:commented, %{
            metadata: %{
              "parent_entity_type" => "post",
              "post_title" => "Best VNs",
              "post_short_id" => "abc123",
              "post_slug" => "best-vns",
              "text_preview" => "totally agree"
            }
          })
        )

      assert html =~ "commented on"
      assert html =~ "Best VNs"
      assert html =~ "totally agree"
    end

    test ":commented with a blank preview suppresses the italic line" do
      html =
        render_one(
          item(:commented, %{
            metadata: %{
              "parent_entity_type" => "post",
              "post_title" => "Best VNs",
              "post_short_id" => "abc123",
              "post_slug" => "best-vns",
              "text_preview" => "   "
            }
          })
        )

      assert html =~ "commented on"
      refute html =~ "italic"
    end

    test "unknown target renders no dead '#' link" do
      html = render_one(item(:rated, %{metadata: %{"vn_title" => "Clannad"}}))
      assert html =~ "Clannad"
      refute html =~ ~s(href="#")
    end
  end
end

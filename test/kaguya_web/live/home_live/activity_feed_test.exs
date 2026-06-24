defmodule KaguyaWeb.HomeLive.ActivityFeedTest do
  @moduledoc """
  Smoke tests for the signed-in home activity sidebar.

  Companion to `KaguyaWeb.ProfileLive.ActivityTest` — exercises the
  multi-actor home feed, the same-actor compaction rule, and the
  grouped-entry summary sentences (`liked N covers from`, `read X and Y`,
  `followed A and B`).
  """

  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Activities
  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.HomeLive.Data
  alias KaguyaWeb.UserAuth

  defp login(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp action_present?(%{entries: entries}, action) do
    Enum.any?(entries, fn entry ->
      Enum.any?(entry.members, &(&1.action == action))
    end)
  end

  describe "GET / (signed in)" do
    test "renders the empty state when there's no global activity" do
      viewer = UserFixtures.insert_user!(username: "viewer", display_name: "Viewer")

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      assert html =~ "No recent activity"
    end

    test "renders status_changed with the per-status verb (not 'updated')" do
      viewer = UserFixtures.insert_user!(username: "viewer1", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "akari", display_name: "Akari")

      {:ok, _} =
        Activities.record_activity(%{
          user_id: author.id,
          action: :status_changed,
          entity_type: "reading_status",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "status" => "currently_reading",
            "vn_id" => UUIDv7.generate(),
            "vn_slug" => "muramasa",
            "vn_title" => "Full Metal Daemon Muramasa"
          }
        })

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      assert html =~ "started reading"
      assert html =~ "Full Metal Daemon Muramasa"
      assert html =~ ~s(href="/vn/muramasa")
      refute html =~ "updated a visual novel"
    end

    test "renders rated with inline star icons and VN title" do
      viewer = UserFixtures.insert_user!(username: "viewer2", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "ren", display_name: "Ren")

      {:ok, _} =
        Activities.record_activity(%{
          user_id: author.id,
          action: :rated,
          entity_type: "rating",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "rating" => 4.5,
            "vn_slug" => "tsukihime",
            "vn_title" => "Tsukihime"
          }
        })

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      assert html =~ "rated"
      assert html =~ "Tsukihime"
      # Inline stars render (DisplayRatings SVG polygon path).
      assert html =~ ~s|polygon points="12 2 15.09|
      # We render stars, not a "4.5/5" text suffix.
      refute html =~ "4.5/5"
    end

    test "renders recommended_similar with 'on <source>' suffix" do
      viewer = UserFixtures.insert_user!(username: "viewer3", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "sumi", display_name: "Sumi")

      {:ok, _} =
        Activities.record_activity(%{
          user_id: author.id,
          action: :recommended_similar,
          entity_type: "similarity",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "similar_vn_title" => "Asphyxia",
            "similar_vn_slug" => "asphyxia",
            "source_vn_title" => "Steins;Gate",
            "source_vn_slug" => "steins-gate"
          }
        })

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      assert html =~ "recommended"
      assert html =~ "Asphyxia"
      assert html =~ "Steins;Gate"
      # Both VNs are independently clickable — mirrors RecommendedSimilarItem
      # in Next.js's ActivityItem.tsx.
      assert html =~ ~s(href="/vn/asphyxia")
      assert html =~ ~s(href="/vn/steins-gate")
    end

    test "groups consecutive liked_cover rows into one summary" do
      viewer = UserFixtures.insert_user!(username: "viewer4", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "haru", display_name: "Haru")

      for _ <- 1..3 do
        {:ok, _} =
          Activities.record_activity(%{
            user_id: author.id,
            action: :liked_cover,
            entity_type: "cover",
            entity_id: UUIDv7.generate(),
            metadata: %{
              "vn_slug" => "umineko",
              "vn_title" => "Umineko",
              "cover_url" => "https://images.kaguya.io/c.webp"
            }
          })
      end

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      assert html =~ "liked 3 covers from"
      assert html =~ "Umineko"
    end

    test "load_activity excludes :reviewed and :created_list on every cursor page" do
      # Parity guard. Per the Next.js commits 888d4373 and ab1ac169,
      # reviews and lists are not part of the activity stream — they
      # have their own home-feed slot and dedicated pages.
      # `Data.load_activity/4` passes @activity_excluded_actions on
      # every call so cursor-based pagination can't sneak them in
      # either. An earlier `:mobile` mode re-included them on Load More,
      # which both duplicated content with the home feed and crashed
      # the LV on `:created_list` rows.
      viewer = UserFixtures.insert_user!(username: "viewer_excl", display_name: "Viewer")

      author =
        UserFixtures.insert_user!(username: "listmaker2", display_name: "List Maker")

      vn = insert_vn!("Cover VN")

      # Older :created_list — would land past the page-1 cursor.
      {:ok, _list} =
        Lists.create_list(%{user_id: author.id, name: "Excluded Tier List", vn_ids: [vn.id]})

      # 21 newer non-excluded activities → page 1 full (has_next: true).
      for n <- 1..21 do
        {:ok, _} =
          Activities.record_activity(%{
            user_id: author.id,
            action: :liked_cover,
            entity_type: "cover",
            entity_id: UUIDv7.generate(),
            metadata: %{
              "vn_slug" => "excl-vn-#{n}",
              "vn_title" => "Excl VN #{n}",
              "cover_url" => "https://images.kaguya.io/c.webp"
            }
          })
      end

      {:ok, page1} = Data.load_activity(viewer, :global, nil, Data.activity_limit())
      assert page1.has_next
      refute action_present?(page1, :created_list)
      refute action_present?(page1, :reviewed)

      {:ok, page2} =
        Data.load_activity(viewer, :global, page1.next_cursor, Data.activity_limit())

      refute action_present?(page2, :created_list)
      refute action_present?(page2, :reviewed)
    end

    test "load_more_activity advances the cursor without crashing the LV" do
      viewer = UserFixtures.insert_user!(username: "viewer_pag", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "pager", display_name: "Pager")

      for n <- 1..21 do
        {:ok, _} =
          Activities.record_activity(%{
            user_id: author.id,
            action: :liked_cover,
            entity_type: "cover",
            entity_id: UUIDv7.generate(),
            metadata: %{
              "vn_slug" => "pag-vn-#{n}",
              "vn_title" => "Pag VN #{n}",
              "cover_url" => "https://images.kaguya.io/c.webp"
            }
          })
      end

      {:ok, view, _html} = live(login(build_conn(), viewer), "/")
      html_after = render_click(view, "load_more_activity")

      # Page-2 content arrived; LV did not remount (mobile_tab default
      # would have wiped it if the renderer had crashed).
      assert html_after =~ "Pag VN 1"
    end

    test "two consecutive status_changed entries with same status render both VN titles" do
      viewer = UserFixtures.insert_user!(username: "viewer5", display_name: "Viewer")
      author = UserFixtures.insert_user!(username: "noa", display_name: "Noa")

      {:ok, _} =
        Activities.record_activity(%{
          user_id: author.id,
          action: :status_changed,
          entity_type: "reading_status",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "status" => "read",
            "vn_slug" => "alpha",
            "vn_title" => "Alpha"
          }
        })

      {:ok, _} =
        Activities.record_activity(%{
          user_id: author.id,
          action: :status_changed,
          entity_type: "reading_status",
          entity_id: UUIDv7.generate(),
          metadata: %{
            "status" => "read",
            "vn_slug" => "beta",
            "vn_title" => "Beta"
          }
        })

      {:ok, _view, html} = live(login(build_conn(), viewer), "/")

      # count == 2 rendering: "read <Alpha> and <Beta>"
      assert html =~ "read"
      assert html =~ "Alpha"
      assert html =~ "Beta"
      assert html =~ "and"
      refute html =~ "and 1 more"
    end
  end
end

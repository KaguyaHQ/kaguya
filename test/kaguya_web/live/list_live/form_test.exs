defmodule KaguyaWeb.ListLive.FormTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListItem, ListTier}
  alias Kaguya.Repo
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.UserAuth

  describe "new" do
    test "requires a signed-in user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/list/new")

      assert html =~ "Sign in to create lists"
    end

    test "renders the Next editor shell structure", %{conn: conn} do
      user = insert_user!()

      {:ok, _view, html} = conn |> log_in(user) |> live(~p"/list/new")

      assert html =~ "max-w-[988px]"
      assert html =~ "New list"
      assert html =~ "desktop-list-vn-search"
      assert html =~ "desktop-vn-search"
      assert html =~ "max-lg:hidden"
      assert html =~ "sticky -top-10"
      assert html =~ "form=\"list-form\""
      assert html =~ "disabled"
      refute html =~ "max-w-[1060px]"
      refute html =~ "lg:grid-cols-[260px_minmax(0,1fr)]"
    end

    test "creates a list through LiveView", %{conn: conn} do
      user = insert_user!()
      vn = insert_vn!("New Flow VN")

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/list/new")

      view
      |> element("form#list-form")
      |> render_change(%{
        "list" => %{
          "name" => "My picks",
          "description" => "",
          "is_public" => "true",
          "is_ranked" => "false",
          "display_mode" => "grid"
        }
      })

      render_click(view, "add_vn", %{"id" => vn.id})

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> element("form#list-form")
        |> render_submit(%{
          "list" => %{
            "name" => "My picks",
            "description" => "",
            "is_public" => "true",
            "is_ranked" => "false",
            "display_mode" => "grid"
          }
        })

      list = Repo.get_by!(List, user_id: user.id, name: "My picks")
      assert to == ~p"/@#{user.username}/list/#{list.slug}"
      assert Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn.id).position == 1
    end

    test "cancel leaves immediately while clean", %{conn: conn} do
      user = insert_user!()

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/list/new")

      {:error, {:live_redirect, %{to: to}}} = render_click(view, "cancel")
      assert to == ~p"/@#{user.username}/lists"
    end

    test "cancel asks for confirmation after edits", %{conn: conn} do
      user = insert_user!()

      {:ok, view, _html} = conn |> log_in(user) |> live(~p"/list/new")

      view
      |> element("form#list-form")
      |> render_change(%{
        "list" => %{
          "name" => "Draft",
          "description" => "",
          "is_public" => "true",
          "is_ranked" => "false",
          "display_mode" => "grid"
        }
      })

      assert render_click(view, "cancel") =~ "Discard changes?"
    end
  end

  describe "edit" do
    test "updates list metadata and layout", %{conn: conn} do
      user = insert_user!()
      vn1 = insert_vn!("First")
      vn2 = insert_vn!("Second")
      {:ok, list} = Lists.create_list(%{user_id: user.id, name: "Old name", vn_ids: [vn1.id]})

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/@#{user.username}/list/#{list.slug}/edit")

      render_click(view, "add_vn", %{"id" => vn2.id})
      render_click(view, "move_vn", %{"id" => vn2.id, "direction" => "up"})

      view
      |> element("form#list-form")
      |> render_submit(%{
        "list" => %{
          "name" => "New name",
          "description" => "Better",
          "is_public" => "false",
          "is_ranked" => "true",
          "display_mode" => "grid"
        }
      })

      persisted = Repo.get!(List, list.id)
      assert persisted.name == "New name"
      assert persisted.description == "Better"
      assert persisted.is_public == false
      assert persisted.is_ranked == true

      assert [vn2.id, vn1.id] ==
               Repo.all(
                 from(li in ListItem,
                   where: li.list_id == ^list.id,
                   order_by: li.position,
                   select: li.visual_novel_id
                 )
               )
    end

    test "saves tier layout from the DnD island boundary", %{conn: conn} do
      user = insert_user!()
      vn1 = insert_vn!("Tier one")
      vn2 = insert_vn!("Tier two")

      {:ok, list} =
        Lists.create_list(%{
          user_id: user.id,
          name: "Tiered",
          display_mode: "tier",
          vn_ids: [vn1.id, vn2.id]
        })

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/@#{user.username}/list/#{list.slug}/edit")

      render_hook(view, "save_layout", %{
        "displayMode" => "tier",
        "tiers" => [
          %{"id" => "tier-s", "label" => "S", "color" => "#f87171", "position" => 1},
          %{"id" => "tier-a", "label" => "A", "color" => "#fb923c", "position" => 2}
        ],
        "items" => [
          %{
            "visualNovelId" => vn2.id,
            "position" => 1,
            "tierId" => "tier-s",
            "tierPosition" => 1
          },
          %{"visualNovelId" => vn1.id, "position" => 2, "tierId" => nil, "tierPosition" => nil}
        ]
      })

      view
      |> element("form#list-form")
      |> render_submit(%{
        "list" => %{
          "name" => "Tiered",
          "description" => "",
          "is_public" => "true",
          "is_ranked" => "false",
          "display_mode" => "tier"
        }
      })

      assert [%ListTier{label: "S", id: s_id}, %ListTier{label: "A"}] =
               Repo.all(from(t in ListTier, where: t.list_id == ^list.id, order_by: t.position))

      assert %ListItem{position: 1, tier_id: ^s_id, tier_position: 1} =
               Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn2.id)

      assert %ListItem{position: 2, tier_id: nil, tier_position: nil} =
               Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn1.id)
    end

    test "adding a tier preserves the current visible tier order", %{conn: conn} do
      user = insert_user!()
      vn = insert_vn!("Tier order")

      {:ok, list} =
        Lists.create_list(%{
          user_id: user.id,
          name: "Ordered tiers",
          display_mode: "tier",
          vn_ids: [vn.id]
        })

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/@#{user.username}/list/#{list.slug}/edit")

      existing_tiers =
        1..9
        |> Enum.map(fn position ->
          %{
            "id" => "tier-#{position}",
            "label" => "Tier #{position}",
            "color" => "#f87171",
            "position" => Integer.to_string(position)
          }
        end)

      render_hook(view, "save_layout", %{
        "displayMode" => "tier",
        "tiers" => existing_tiers,
        "items" => [
          %{
            "visualNovelId" => vn.id,
            "position" => 1,
            "tierId" => nil,
            "tierPosition" => nil
          }
        ]
      })

      render_click(view, "open_tier_editor")
      render_click(view, "add_tier")
      render_click(view, "save_tier_draft")

      view
      |> element("form#list-form")
      |> render_submit(%{
        "list" => %{
          "name" => "Ordered tiers",
          "description" => "",
          "is_public" => "true",
          "is_ranked" => "false",
          "display_mode" => "tier"
        }
      })

      labels =
        Repo.all(
          from(t in ListTier,
            where: t.list_id == ^list.id,
            order_by: t.position,
            select: t.label
          )
        )

      assert labels == [
               "Tier 1",
               "Tier 2",
               "Tier 3",
               "Tier 4",
               "Tier 5",
               "Tier 6",
               "Tier 7",
               "Tier 8",
               "Tier 9",
               "Tier 10"
             ]
    end

    test "moves tiers without renaming them", %{conn: conn} do
      user = insert_user!()
      vn = insert_vn!("Tier mover")

      {:ok, list} =
        Lists.create_list(%{
          user_id: user.id,
          name: "Movable tiers",
          display_mode: "tier",
          vn_ids: [vn.id]
        })

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/@#{user.username}/list/#{list.slug}/edit")

      render_hook(view, "save_layout", %{
        "displayMode" => "tier",
        "tiers" => [
          %{"id" => "tier-s", "label" => "S", "color" => "#f87171", "position" => 1},
          %{"id" => "tier-a", "label" => "A", "color" => "#fb923c", "position" => 2},
          %{"id" => "tier-b", "label" => "B", "color" => "#facc15", "position" => 3}
        ],
        "items" => [
          %{
            "visualNovelId" => vn.id,
            "position" => 1,
            "tierId" => "tier-a",
            "tierPosition" => 1
          }
        ]
      })

      render_click(view, "open_tier_editor")
      render_click(view, "move_tier", %{"id" => "tier-b", "direction" => "up"})
      render_click(view, "save_tier_draft")

      view
      |> element("form#list-form")
      |> render_submit(%{
        "list" => %{
          "name" => "Movable tiers",
          "description" => "",
          "is_public" => "true",
          "is_ranked" => "false",
          "display_mode" => "tier"
        }
      })

      tiers =
        Repo.all(
          from(t in ListTier,
            where: t.list_id == ^list.id,
            order_by: t.position,
            select: {t.label, t.position}
          )
        )

      assert tiers == [{"S", 1}, {"B", 2}, {"A", 3}]

      assert %ListItem{tier_id: tier_a_id, tier_position: 1} =
               Repo.get_by!(ListItem, list_id: list.id, visual_novel_id: vn.id)

      assert Repo.get_by!(ListTier, list_id: list.id, label: "A").id == tier_a_id
    end

    test "deletes an owned list", %{conn: conn} do
      user = insert_user!()
      vn = insert_vn!("Delete me")
      {:ok, list} = Lists.create_list(%{user_id: user.id, name: "Temporary", vn_ids: [vn.id]})

      {:ok, view, _html} =
        conn |> log_in(user) |> live(~p"/@#{user.username}/list/#{list.slug}/edit")

      {:error, {:live_redirect, %{to: to}}} = render_click(view, "delete")
      assert to == ~p"/@#{user.username}/lists"
      refute Repo.get(List, list.id)
    end
  end

  defp log_in(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end

  defp insert_user! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.create_changeset(%{
      id: Ecto.UUID.generate(),
      username: "list_user_#{suffix}",
      display_name: "List User #{suffix}",
      email: "list-user-#{suffix}@example.com"
    })
    |> Repo.insert!()
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end

defmodule KaguyaWeb.ListLive.CharacterListTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListCharacterItem}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    vn = insert_vn!()
    hero = insert_character!("Hero")
    rival = insert_character!("Rival")
    secret = insert_character!("Secret")
    link!(hero, vn, :main)
    link!(rival, vn, :side)
    link!(secret, vn, :primary, 2)

    %{user: UserFixtures.insert_user!(), vn: vn, hero: hero, rival: rival, secret: secret}
  end

  describe "editor" do
    test "creates a character tier list from a VN's cast", ctx do
      {:ok, view, _html} = live(conn_for(ctx.user), ~p"/list/new?type=character")

      assert has_element?(view, "#list-form-item-type [aria-selected='true']", "Characters")
      refute has_element?(view, "#list-form-display-grid")

      render_click(view, "pick_cast_vn", %{"id" => ctx.vn.id})

      assert has_element?(view, "#cast-picker-character-#{ctx.hero.id}")
      assert has_element?(view, "#cast-picker-character-#{ctx.rival.id}")
      # Appearances flagged as spoilers stay out of the picker.
      refute has_element?(view, "#cast-picker-character-#{ctx.secret.id}")

      view |> element("#cast-picker-character-#{ctx.hero.id}") |> render_click()
      refute has_element?(view, "#cast-picker-character-#{ctx.hero.id}")

      view |> element("#cast-picker-add-all") |> render_click()
      refute has_element?(view, "#cast-picker-character-#{ctx.rival.id}")

      # Once items are on the list, the type can't change.
      render_click(view, "set_item_type", %{"type" => "vn"})
      assert has_element?(view, "#list-form-item-type [aria-selected='true']", "Characters")

      {:error, {:live_redirect, %{to: to}}} =
        view
        |> element("form#list-form")
        |> render_submit(%{"list" => %{"name" => "Cast ranking"}})

      list = Repo.get_by!(List, user_id: ctx.user.id, name: "Cast ranking")
      assert to == ~p"/@#{ctx.user.username}/list/#{list.slug}"
      assert list.item_type == "character"
      assert list.display_mode == "tier"

      ids =
        Repo.all(
          from(li in ListCharacterItem,
            where: li.list_id == ^list.id,
            order_by: li.position,
            select: li.character_id
          )
        )

      assert ids == [ctx.hero.id, ctx.rival.id]
    end

    test "switching to characters before adding anything keeps the typed name", ctx do
      {:ok, view, _html} = live(conn_for(ctx.user), ~p"/list/new")

      view
      |> element("form#list-form")
      |> render_change(%{"list" => %{"name" => "Draft name"}})

      view |> element("#list-form-item-type button", "Characters") |> render_click()

      assert has_element?(view, "#list-form-item-type [aria-selected='true']", "Characters")
      assert has_element?(view, "#list_name[value='Draft name']")
    end

    test "VN search results don't add VNs to a character list", ctx do
      {:ok, view, _html} = live(conn_for(ctx.user), ~p"/list/new?type=character")

      render_click(view, "add_item", %{"id" => ctx.vn.id})

      refute has_element?(view, "#list-layout-island")
    end

    test "edits an existing character list without offering the type switch", ctx do
      list = character_list!(ctx.user, [ctx.hero])

      {:ok, view, _html} =
        live(conn_for(ctx.user), ~p"/@#{ctx.user.username}/list/#{list.slug}/edit")

      refute has_element?(view, "#list-form-item-type")

      render_click(view, "pick_cast_vn", %{"id" => ctx.vn.id})
      # Already-listed characters aren't offered again.
      refute has_element?(view, "#cast-picker-character-#{ctx.hero.id}")
      view |> element("#cast-picker-character-#{ctx.rival.id}") |> render_click()

      view |> element("form#list-form") |> render_submit(%{"list" => %{"name" => list.name}})

      assert Repo.aggregate(from(li in ListCharacterItem, where: li.list_id == ^list.id), :count) ==
               2
    end
  end

  describe "list page" do
    test "renders character tiles without VN reading progress", ctx do
      list = character_list!(ctx.user, [ctx.hero, ctx.rival])

      {:ok, view, html} = live(build_conn(), ~p"/@#{ctx.user.username}/list/#{list.slug}")

      assert has_element?(view, ~s(a[href="/character/#{ctx.hero.slug}"]))
      assert has_element?(view, ~s(a[href="/character/#{ctx.rival.slug}"]))
      refute has_element?(view, "#sidebar-fade-read")
      assert html =~ "a list of characters by"
    end
  end

  describe "profile lists" do
    test "shows character portraits on the list card", ctx do
      list = character_list!(ctx.user, [ctx.hero])

      {:ok, _view, html} = live(build_conn(), ~p"/@#{ctx.user.username}/lists")

      assert html =~ list.name
      assert html =~ ctx.hero.name
    end
  end

  defp character_list!(user, characters) do
    {:ok, list} =
      Lists.create_list_with_layout(
        user.id,
        %{name: "Characters #{System.unique_integer([:positive])}", item_type: "character"},
        %{
          display_mode: "tier",
          tiers: [%{id: "tier-s", label: "S", color: "#f87171", position: 1}],
          items: Enum.map(characters, &%{character_id: &1.id, tier_id: "tier-s"})
        }
      )

    list
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  defp insert_vn! do
    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "Cast VN #{System.unique_integer([:positive])}",
      original_language: "en"
    })
    |> Repo.insert!()
  end

  defp insert_character!(name) do
    %Character{}
    |> Character.changeset(%{name: "#{name} #{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp link!(character, vn, role, spoiler_level \\ 0) do
    %VNCharacter{}
    |> VNCharacter.changeset(%{
      character_id: character.id,
      visual_novel_id: vn.id,
      role: role,
      spoiler_level: spoiler_level
    })
    |> Repo.insert!()
  end
end

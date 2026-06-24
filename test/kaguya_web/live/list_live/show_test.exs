defmodule KaguyaWeb.ListLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.List, as: VnList
  alias Kaguya.Lists.ListLike
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders a public user list through direct LiveView routing" do
    owner = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
    [vn1, vn2] = insert_vns!(2)

    {:ok, list} =
      Lists.create_list(%{user_id: owner.id, name: "Alice Picks", vn_ids: [vn1.id, vn2.id]})

    {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/list/#{list.slug}")

    assert html =~ "Alice Picks"
    assert html =~ "Alice"
    assert html =~ vn1.title
    assert html =~ "application/ld+json"
  end

  test "emits SEO meta tags and ItemList JSON-LD for a public list" do
    owner = UserFixtures.insert_user!(username: "alice", display_name: "Alice")
    [vn1, _vn2] = insert_vns!(2)

    {:ok, list} =
      Lists.create_list(%{user_id: owner.id, name: "Alice Picks", vn_ids: [vn1.id]})

    {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/list/#{list.slug}")

    canonical = "https://kaguya.io/@#{owner.username}/list/#{list.slug}"

    assert html =~ ~s(<title>Alice Picks, a list of visual novels by Alice • Kaguya</title>)
    assert html =~ ~s(<link rel="canonical" href="#{canonical}")
    assert html =~ ~s(<meta property="og:title" content="Alice Picks")
    assert html =~ ~s(<meta property="og:type" content="website")
    assert html =~ ~s(<meta name="twitter:card" content="summary")
    assert html =~ ~s("@type":"WebSite")
    assert html =~ ~s("@type":"ItemList")
    assert html =~ ~s("position":1)
  end

  test "noindexes a non-existent list" do
    {:ok, _view, html} = live(build_conn(), "/@nope/list/does-not-exist")

    assert html =~ ~s(<meta name="robots" content="noindex,follow")
    assert html =~ ~s(<title>List Not Found • Kaguya</title>)
  end

  test "validates the username in the URL" do
    owner = UserFixtures.insert_user!(username: "right_owner")
    [vn] = insert_vns!(1)
    {:ok, list} = Lists.create_list(%{user_id: owner.id, name: "Owned List", vn_ids: [vn.id]})

    {:ok, _view, html} = live(build_conn(), "/@wrong_owner/list/#{list.slug}")

    assert html =~ "https://images.kaguya.io/ui/404.webp"
    assert html =~ "Return home"
    refute html =~ "Owned List"
  end

  test "hides private lists from non-owners and shows them to owners" do
    owner = UserFixtures.insert_user!(username: "private_owner")
    viewer = UserFixtures.insert_user!()
    [vn] = insert_vns!(1)

    {:ok, list} =
      Lists.create_list(%{
        user_id: owner.id,
        name: "Secret Shelf",
        is_public: false,
        vn_ids: [vn.id]
      })

    {:ok, _view, html} = live(conn_for(viewer), "/@#{owner.username}/list/#{list.slug}")
    assert html =~ "https://images.kaguya.io/ui/404.webp"
    assert html =~ "Return home"

    {:ok, _view, owner_html} = live(conn_for(owner), "/@#{owner.username}/list/#{list.slug}")
    assert owner_html =~ "Secret Shelf"
    assert owner_html =~ "Make this list public"
  end

  test "like and unlike update list likes through LiveView" do
    owner = UserFixtures.insert_user!(username: "like_owner")
    viewer = UserFixtures.insert_user!()
    [vn] = insert_vns!(1)
    {:ok, list} = Lists.create_list(%{user_id: owner.id, name: "Likeable", vn_ids: [vn.id]})

    {:ok, view, _html} = live(conn_for(viewer), "/@#{owner.username}/list/#{list.slug}")

    assert render_click(element(view, "#like-list-sidebar")) =~ "Unlike (1)"
    assert Repo.aggregate(from(l in ListLike, where: l.list_id == ^list.id), :count) == 1

    assert render_click(element(view, "#like-list-sidebar")) =~ "Like (0)"
    assert Repo.aggregate(from(l in ListLike, where: l.list_id == ^list.id), :count) == 0
  end

  test "owner can toggle public/private visibility" do
    owner = UserFixtures.insert_user!(username: "visibility_owner")
    [vn] = insert_vns!(1)
    {:ok, list} = Lists.create_list(%{user_id: owner.id, name: "Visibility", vn_ids: [vn.id]})

    {:ok, view, _html} = live(conn_for(owner), "/@#{owner.username}/list/#{list.slug}")

    assert render_click(element(view, "#toggle-visibility-sidebar")) =~
             "Make this list public"

    refute Repo.get!(VnList, list.id).is_public
  end

  test "renders readonly tier rows" do
    owner = UserFixtures.insert_user!(username: "tier_owner")
    [vn1, vn2] = insert_vns!(2)

    {:ok, list} =
      Lists.create_list(%{user_id: owner.id, name: "Tiered", vn_ids: [vn1.id, vn2.id]})

    assert {:ok, _saved} =
             Lists.save_list_layout(list.id, owner.id, %{
               display_mode: "tier",
               tiers: [
                 %{id: "tier-s", label: "S", color: "#ff5555", position: 1},
                 %{id: "tier-a", label: "A", color: "#55aaff", position: 2}
               ],
               items: [
                 %{visual_novel_id: vn1.id, tier_id: "tier-s", tier_position: 1},
                 %{visual_novel_id: vn2.id, tier_id: "tier-a", tier_position: 1}
               ]
             })

    {:ok, _view, html} = live(build_conn(), "/@#{owner.username}/list/#{list.slug}")

    assert html =~ "tier-board"
    assert html =~ "S"
    assert html =~ vn1.title
    assert html =~ vn2.title
  end

  test "paginates list items with listPage and page size 100" do
    owner = UserFixtures.insert_user!(username: "page_owner")
    vns = insert_vns!(101)

    {:ok, list} =
      Lists.create_list(%{user_id: owner.id, name: "Paged", vn_ids: Enum.map(vns, & &1.id)})

    {:ok, _view, first_html} = live(build_conn(), "/@#{owner.username}/list/#{list.slug}")
    assert first_html =~ Enum.at(vns, 99).title
    refute first_html =~ Enum.at(vns, 100).title

    {:ok, _view, second_html} =
      live(build_conn(), "/@#{owner.username}/list/#{list.slug}?listPage=2")

    assert second_html =~ Enum.at(vns, 100).title
    refute second_html =~ Enum.at(vns, 0).title
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{current_user_id: user.id})
  end

  defp insert_vns!(count) do
    for n <- 1..count, do: insert_vn!("Live List VN #{n}")
  end

  defp insert_vn!(title) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end
end

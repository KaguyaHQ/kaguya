defmodule Kaguya.Lists.ListSlugTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)

    vn =
      %VisualNovel{}
      |> VisualNovel.changeset(%{title: "Slug VN", original_language: "en"})
      |> Repo.insert!()

    %{vn: vn}
  end

  test "slugs are per owner, so two users can both have /list/to-read", %{vn: vn} do
    [first, second] = for _ <- 1..2, do: UserFixtures.insert_user!()

    a = list!(first, "to read", vn)
    b = list!(second, "to read", vn)

    assert a.slug == "to-read"
    assert b.slug == "to-read"

    # Each URL resolves to its own owner's list.
    assert {:ok, %{id: a_id}} = Lists.get_user_list_for_view(first.username, "to-read")
    assert {:ok, %{id: b_id}} = Lists.get_user_list_for_view(second.username, "to-read")
    assert {a_id, b_id} == {a.id, b.id}
  end

  test "an owner's lists still get distinct slugs", %{vn: vn} do
    user = UserFixtures.insert_user!()

    assert list!(user, "to read", vn).slug == "to-read"
    assert list!(user, "To Read!", vn).slug == "to-read-1"
  end

  test "reusing one of your own list names is a readable name error", %{vn: vn} do
    user = UserFixtures.insert_user!()
    list!(user, "to read", vn)

    assert {:error, changeset} =
             Lists.create_list(%{user_id: user.id, name: "to read", vn_ids: [vn.id]})

    assert {"is already used by another of your lists", _} = changeset.errors[:name]
  end

  test "the list page needs the owner's username", %{vn: vn} do
    owner = UserFixtures.insert_user!()
    other = UserFixtures.insert_user!()
    list!(owner, "to read", vn)

    assert {:error, :not_found} = Lists.get_user_list_for_view(other.username, "to-read")
  end

  test "staff picks are pinned to their owners, not to bare slugs", %{vn: vn} do
    curator = UserFixtures.insert_user!(username: "lovelyz")
    impostor = UserFixtures.insert_user!()

    pick = list!(curator, "yuri", vn)
    list!(impostor, "yuri", vn)

    assert {:ok, lists} = Lists.list_hidden_gem_lists_for_viewer(nil)
    assert Enum.map(lists, & &1.id) == [pick.id]
  end

  defp list!(user, name, vn) do
    {:ok, list} = Lists.create_list(%{user_id: user.id, name: name, vn_ids: [vn.id]})
    list
  end
end

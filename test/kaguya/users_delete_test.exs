defmodule Kaguya.UsersDeleteTest do
  # async: false — delete_user wraps a Repo.transaction that doesn't play
  # nicely with sandboxes in parallel.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Characters.{Character, CharacterFavorite}
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.Users.User

  import UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "delete_user/1" do
    test "decrements character favorites while preserving another user's pin" do
      user = insert_user!()
      other = insert_user!()

      character =
        %Character{} |> Character.changeset(%{name: "Favorite character"}) |> Repo.insert!()

      assert {:ok, true} = Users.add_favorite_character(user, character.id)
      assert {:ok, true} = Users.add_favorite_character(other, character.id)
      assert Repo.get!(Character, character.id).favorites_count == 2

      assert {:ok, true} = Users.delete_user(user.id)
      refute Repo.get_by(CharacterFavorite, user_id: user.id, character_id: character.id)
      assert Repo.get_by(CharacterFavorite, user_id: other.id, character_id: character.id)
      assert Repo.get!(Character, character.id).favorites_count == 1
    end

    test "deletes the user" do
      user = insert_user!()
      assert {:ok, true} = Users.delete_user(user.id)
      refute Repo.get(User, user.id)
    end
  end
end

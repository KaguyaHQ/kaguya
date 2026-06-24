defmodule Kaguya.UsersDeleteTest do
  # async: false — delete_user wraps a Repo.transaction that doesn't play
  # nicely with sandboxes in parallel.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.Users.User

  import UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  describe "delete_user/1" do
    test "deletes the user" do
      user = insert_user!()
      assert {:ok, true} = Users.delete_user(user.id)
      refute Repo.get(User, user.id)
    end
  end
end

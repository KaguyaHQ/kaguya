defmodule Kaguya.Test.UserFixtures do
  @moduledoc false
  # Shared fixture helper for inserting test users. Centralises the
  # random-suffix scheme and default user shape every test reaches for.

  alias Kaguya.Repo
  alias Kaguya.Users.User

  @doc """
  Insert a test user. `attrs` may be a map or a keyword list; entries are
  merged over the defaults.
  """
  def insert_user!(attrs \\ %{})

  def insert_user!(attrs) when is_list(attrs), do: insert_user!(Map.new(attrs))

  def insert_user!(attrs) when is_map(attrs) do
    suffix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(
        %{
          id: UUIDv7.generate(),
          email: "u#{suffix}@fixture.test",
          username: "u_#{suffix}",
          display_name: "U#{suffix}"
        },
        attrs
      )

    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert!()
  end
end

defmodule Kaguya.Characters.CharacterFavorite do
  @moduledoc """
  Join table row representing "user U has character C in their profile
  favorites at position P". The authoritative store for character
  favorites — `users.favorite_characters` was replaced by this table.

  Writes happen via `Kaguya.Users.update_user/2`, which compares the
  desired favorite set against the existing rows for the user and
  applies inserts / deletes / position updates in a single transaction.
  The `characters.favorites_count` denormalized counter is kept in sync
  inside that same transaction.
  """

  use Ecto.Schema

  alias Kaguya.Users.User
  alias Kaguya.Characters.Character

  @primary_key false
  @foreign_key_type :binary_id

  schema "character_favorites" do
    belongs_to :user, User, primary_key: true, type: :binary_id
    belongs_to :character, Character, primary_key: true, type: :binary_id

    field :position, :integer

    # `updated_at` is intentionally omitted: a favorite row is either
    # present or not — position changes are treated as the same row
    # "still favorited", so the original `inserted_at` is the signal
    # consumers care about for the "who favorited this recently" feed.
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

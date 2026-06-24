defmodule Kaguya.Characters.CharacterLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Characters.Character

  @primary_key false
  @foreign_key_type :binary_id
  schema "character_likes" do
    belongs_to :user, User, primary_key: true
    belongs_to :character, Character, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :character_id])
    |> validate_required([:user_id, :character_id])
    |> unique_constraint([:user_id, :character_id], name: :character_likes_pkey)
  end
end

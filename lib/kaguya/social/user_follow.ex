defmodule Kaguya.Social.UserFollow do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.Users.User

  @primary_key false
  @foreign_key_type :binary_id
  schema "user_follows" do
    belongs_to :follower, User, primary_key: true
    belongs_to :followed, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_follow, attrs) do
    user_follow
    |> cast(attrs, [:follower_id, :followed_id])
    |> validate_required([:follower_id, :followed_id])
    |> check_constraint(:followed_id,
      name: :cannot_follow_self,
      message: "A user cannot follow themselves"
    )
    |> unique_constraint([:follower_id, :followed_id],
      name: :user_follows_pkey,
      message: "You are already following this user"
    )
  end
end

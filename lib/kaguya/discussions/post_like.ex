defmodule Kaguya.Discussions.PostLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Discussions.Post

  @primary_key false
  @foreign_key_type :binary_id

  schema "post_likes" do
    belongs_to :post, Post, primary_key: true
    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:post_id, :user_id])
    |> assoc_constraint(:post)
    |> assoc_constraint(:user)
    |> unique_constraint([:post_id, :user_id],
      name: :post_likes_pkey,
      message: "You have already liked this post."
    )
  end
end

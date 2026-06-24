defmodule Kaguya.Discussions.CommentLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Discussions.Comment

  @primary_key false
  @foreign_key_type :binary_id

  schema "post_comment_likes" do
    belongs_to :post_comment, Comment, primary_key: true
    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:post_comment_id, :user_id])
    |> assoc_constraint(:post_comment)
    |> assoc_constraint(:user)
    |> unique_constraint([:post_comment_id, :user_id],
      name: :post_comment_likes_pkey,
      message: "You have already liked this comment."
    )
  end
end

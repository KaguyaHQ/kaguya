defmodule Kaguya.Lists.ListCommentLike do
  use Kaguya.Schema

  alias Kaguya.Lists.ListComment
  alias Kaguya.Users.User

  @primary_key false
  @foreign_key_type :binary_id

  schema "list_comment_likes" do
    field :vn_list_comment_id, :binary_id, primary_key: true, source: :list_comment_id

    belongs_to :vn_list_comment, ListComment,
      primary_key: true,
      define_field: false,
      foreign_key: :vn_list_comment_id

    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vn_list_comment_like, attrs) do
    vn_list_comment_like
    |> cast(attrs, [:vn_list_comment_id, :user_id])
    |> assoc_constraint(:vn_list_comment)
    |> assoc_constraint(:user)
    |> unique_constraint([:vn_list_comment_id, :user_id],
      name: :vn_list_comment_likes_pkey,
      message: "You have already liked this comment."
    )
  end
end

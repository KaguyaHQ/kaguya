defmodule Kaguya.Lists.ListLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Lists.List

  @primary_key false
  @foreign_key_type :binary_id

  schema "list_likes" do
    belongs_to :list, List, primary_key: true
    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(like, attrs) do
    like
    |> cast(attrs, [:list_id, :user_id])
    |> validate_required([:list_id, :user_id])
    |> assoc_constraint(:list)
    |> assoc_constraint(:user)
    |> unique_constraint([:list_id, :user_id],
      name: :vn_list_likes_pkey,
      message: "You have already liked this list."
    )
  end
end

defmodule Kaguya.Reviews.ReviewLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Reviews.Review

  @primary_key false
  @foreign_key_type :binary_id

  schema "review_likes" do
    field :vn_review_id, :binary_id, primary_key: true, source: :review_id

    belongs_to :vn_review, Review,
      primary_key: true,
      define_field: false,
      foreign_key: :vn_review_id

    belongs_to :user, User, primary_key: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vn_review_like, attrs) do
    vn_review_like
    |> cast(attrs, [:vn_review_id, :user_id])
    |> assoc_constraint(:vn_review)
    |> assoc_constraint(:user)
    |> unique_constraint([:vn_review_id, :user_id],
      name: :vn_review_likes_pkey,
      message: "You have already liked this review."
    )
  end
end

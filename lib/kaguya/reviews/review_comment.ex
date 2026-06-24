defmodule Kaguya.Reviews.ReviewComment do
  use Kaguya.Schema

  alias Kaguya.Reviews.Review
  alias Kaguya.Users.User

  schema "review_comments" do
    field :content, :string
    field :likes_count, :integer, default: 0
    field :is_edited, :boolean, default: false
    field :hidden_at, :utc_datetime

    field :vn_review_id, :binary_id, source: :review_id

    belongs_to :vn_review, Review, define_field: false, foreign_key: :vn_review_id
    belongs_to :user, User
    belongs_to :parent_comment, __MODULE__

    has_many :child_comments, __MODULE__, foreign_key: :parent_comment_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vn_review_comment, attrs) do
    vn_review_comment
    |> cast(attrs, [
      :vn_review_id,
      :user_id,
      :parent_comment_id,
      :content,
      :is_edited
    ])
    |> validate_required([
      :content
    ])
    |> assoc_constraint(:vn_review)
    |> assoc_constraint(:user)
    |> assoc_constraint(:parent_comment)
  end
end

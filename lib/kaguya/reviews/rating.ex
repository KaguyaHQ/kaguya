defmodule Kaguya.Reviews.Rating do
  use Kaguya.Schema

  alias Kaguya.RatingDistribution
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Users.User

  schema "ratings" do
    belongs_to :user, User
    belongs_to :visual_novel, VisualNovel

    field :rating, :float
    field :source, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_rating, attrs) do
    vn_rating
    |> cast(attrs, [:user_id, :visual_novel_id, :rating])
    |> validate_required([:user_id, :visual_novel_id, :rating])
    |> validate_inclusion(:rating, RatingDistribution.valid_rating_values(),
      message: "Rating must be between 0.5 and 5.0 in 0.5 steps."
    )
    |> unique_constraint([:user_id, :visual_novel_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:visual_novel)
  end
end

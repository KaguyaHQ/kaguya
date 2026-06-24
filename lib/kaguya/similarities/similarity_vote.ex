defmodule Kaguya.Similarities.SimilarityVote do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Users.User

  @primary_key false
  @foreign_key_type :binary_id
  schema "vn_similarity_votes" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :similar_vn, VisualNovel, primary_key: true
    belongs_to :user, User, primary_key: true
    field :vote_value, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:visual_novel_id, :similar_vn_id, :user_id, :vote_value])
    |> validate_required([:visual_novel_id, :similar_vn_id, :user_id, :vote_value])
    |> validate_inclusion(:vote_value, [-1, 1])
    |> unique_constraint([:visual_novel_id, :similar_vn_id, :user_id],
      name: :vn_similarity_votes_pkey
    )
  end
end

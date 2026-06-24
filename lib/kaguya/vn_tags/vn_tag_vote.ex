defmodule Kaguya.VNTags.VNTagVote do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Tags.Tag

  schema "vn_tag_votes" do
    belongs_to :user, User
    belongs_to :visual_novel, VisualNovel
    belongs_to :tag, Tag

    # Graded relevance: 0 = Not Relevant (single downvote), 1..5 = degree
    # 1 Small / 2 Minor / 3 Moderate / 4 Major / 5 Main Theme
    # (labels live in the tag panel buckets + `Activity.Helpers.tag_vote_phrase/1`)
    field :value, :integer
    field :spoiler_level, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:user_id, :visual_novel_id, :tag_id, :value, :spoiler_level])
    |> validate_required([:user_id, :visual_novel_id, :tag_id, :value])
    |> validate_inclusion(:value, 0..5)
    |> validate_inclusion(:spoiler_level, [0, 1, 2])
    |> unique_constraint([:user_id, :visual_novel_id, :tag_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:tag)
  end
end

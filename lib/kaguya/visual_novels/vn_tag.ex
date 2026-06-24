defmodule Kaguya.VisualNovels.VNTag do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Tags.Tag

  @primary_key false
  @spoiler_levels [none: 0, minor: 1, major: 2]

  schema "vn_tags" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :tag, Tag, primary_key: true

    # VNDB vote data
    field :vndb_vote_count, :integer, default: 0
    field :vndb_avg_score, :float

    # Kaguya graded votes are computed live from the vn_tag_votes table.
    # Not denormalized — see migration moduledoc for rationale.

    # Computed relevance
    field :relevance_score, :float, default: 0.0

    # Spoiler level (from VNDB)
    field :spoiler_level, Ecto.Enum, values: @spoiler_levels, default: :none

    # Moderation
    field :is_overruled, :boolean, default: false
    field :overruled_by, :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_tag, attrs) do
    vn_tag
    |> cast(attrs, [
      :visual_novel_id,
      :tag_id,
      :vndb_vote_count,
      :vndb_avg_score,
      :relevance_score,
      :spoiler_level,
      :is_overruled,
      :overruled_by
    ])
    |> validate_required([:visual_novel_id, :tag_id])
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:tag)
  end
end

defmodule Kaguya.Similarities.Similarity do
  @moduledoc """
  Schema for community-driven VN similarities.
  """
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel

  @primary_key false

  schema "vn_similarities" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :similar_vn, VisualNovel, foreign_key: :similar_vn_id, primary_key: true

    field :upvotes_count, :integer, default: 0
    field :downvotes_count, :integer, default: 0
    field :score, :float, default: 0.0

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_similarity, attrs) do
    vn_similarity
    |> cast(attrs, [:visual_novel_id, :similar_vn_id, :upvotes_count, :downvotes_count, :score])
    |> validate_required([:visual_novel_id, :similar_vn_id])
    |> validate_different_vns()
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:similar_vn)
    |> unique_constraint([:visual_novel_id, :similar_vn_id], name: :vn_similarities_pkey)
  end

  defp validate_different_vns(changeset) do
    vn_id = get_field(changeset, :visual_novel_id)
    similar_vn_id = get_field(changeset, :similar_vn_id)

    if vn_id && similar_vn_id && vn_id == similar_vn_id do
      add_error(changeset, :similar_vn_id, "cannot be the same as visual_novel")
    else
      changeset
    end
  end
end

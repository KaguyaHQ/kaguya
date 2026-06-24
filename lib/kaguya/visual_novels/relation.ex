defmodule Kaguya.VisualNovels.Relation do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel

  @primary_key false

  # Relation types:
  # - 'sequel'            : Direct story continuation
  # - 'prequel'           : Story that happened before
  # - 'fandisc'           : Supplementary spinoff/expansion
  # - 'side_story'        : Story in same universe, different focus
  # - 'parent_story'      : Main story a side story expands on
  # - 'same_setting'      : Different story in same universe
  # - 'alternative'       : Remake or alternative version
  # - 'shares_characters' : Unrelated work with cameo/crossover
  # - 'same_series'       : Part of franchise but loose connection

  schema "vn_relations" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :related_vn, VisualNovel, foreign_key: :related_vn_id, primary_key: true

    field :relation_type, :string
    field :is_official, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_relation, attrs) do
    vn_relation
    |> cast(attrs, [:visual_novel_id, :related_vn_id, :relation_type, :is_official])
    |> validate_required([:visual_novel_id, :related_vn_id, :relation_type])
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:related_vn)
  end
end

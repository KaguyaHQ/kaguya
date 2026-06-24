defmodule Kaguya.Revisions.Hist.VnRelationHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_relations_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :related_vn_id, :binary_id
    field :relation_type, :string
    field :is_official, :boolean, default: true
  end
end

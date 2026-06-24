defmodule Kaguya.Revisions.Hist.VnCharacterHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_characters_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :visual_novel_id, :binary_id
    field :character_id, :binary_id
    field :role, :string
    field :spoiler_level, :integer, default: 0
  end
end

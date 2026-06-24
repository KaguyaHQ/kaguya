defmodule Kaguya.Revisions.Hist.SeriesItemHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_series_items_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :visual_novel_id, :binary_id
    field :position, :float
  end
end

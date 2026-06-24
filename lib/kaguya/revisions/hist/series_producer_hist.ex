defmodule Kaguya.Revisions.Hist.SeriesProducerHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_series_producers_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :producer_id, :binary_id
    field :role, :string
  end
end

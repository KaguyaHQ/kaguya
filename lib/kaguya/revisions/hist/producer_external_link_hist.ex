defmodule Kaguya.Revisions.Hist.ProducerExternalLinkHist do
  use Ecto.Schema

  @primary_key false

  schema "producer_external_links_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :site, :string
    field :value, :string
  end
end

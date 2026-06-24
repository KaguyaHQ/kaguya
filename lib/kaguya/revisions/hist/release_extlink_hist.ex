defmodule Kaguya.Revisions.Hist.ReleaseExtlinkHist do
  use Ecto.Schema

  @primary_key false

  schema "release_extlinks_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :site, :string
    field :label, :string
    field :url, :string
  end
end

defmodule Kaguya.Revisions.Hist.VnCoverHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_covers_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :cover_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
    field :language, :string
    field :release_date, :date
  end
end

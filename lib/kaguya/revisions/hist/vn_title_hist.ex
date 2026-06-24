defmodule Kaguya.Revisions.Hist.VnTitleHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_titles_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :lang, :string
    field :title, :string
    field :latin, :string
    field :official, :boolean, default: true
  end
end

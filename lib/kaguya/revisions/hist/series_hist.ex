defmodule Kaguya.Revisions.Hist.SeriesHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_series_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id, primary_key: true
    field :name, :string
    field :slug, :string
    field :description, :string
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
    field :source, :string
    field :manual_fields, {:array, :string}, default: []
    field :imported_root_visual_novel_id, :binary_id
  end
end

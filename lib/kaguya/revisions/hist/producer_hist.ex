defmodule Kaguya.Revisions.Hist.ProducerHist do
  use Ecto.Schema

  @primary_key false

  schema "producers_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id, primary_key: true
    field :name, :string
    field :slug, :string
    field :description, :string
    field :producer_type, :string
    field :language, :string
    field :primary_image_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
  end
end

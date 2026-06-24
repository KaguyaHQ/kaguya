defmodule Kaguya.Revisions.Hist.CharacterImageHist do
  use Ecto.Schema

  @primary_key false

  schema "character_images_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :image_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
  end
end

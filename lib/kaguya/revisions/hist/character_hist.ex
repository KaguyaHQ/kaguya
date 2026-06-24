defmodule Kaguya.Revisions.Hist.CharacterHist do
  use Ecto.Schema

  @primary_key false

  schema "characters_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id, primary_key: true
    field :name, :string
    field :slug, :string
    field :description, :string
    field :sex, :string
    field :spoiler_sex, :string
    field :gender, :string
    field :spoiler_gender, :string
    field :blood_type, :string
    field :height, :integer
    field :weight, :integer
    field :age, :integer
    field :birthday, :integer
    field :bust, :integer
    field :waist, :integer
    field :hip, :integer
    field :cup_size, :string
    field :primary_image_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
  end
end

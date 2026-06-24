defmodule Kaguya.Revisions.Hist.VnHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id, primary_key: true
    field :title, :string
    field :slug, :string
    field :description, :string
    field :aliases, {:array, :string}, default: []
    field :development_status, :string
    field :length_category, :string
    field :length_minutes, :integer
    field :original_language, :string
    field :release_date, :date
    field :min_age, :integer
    field :has_ero, :boolean, default: false
    field :is_avn, :boolean, default: false
    field :title_category, :string, default: "vn"
    field :primary_image_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
    field :primary_vn_series_id, :binary_id
    field :primary_series_position, :float
    field :featured_screenshot_id, :binary_id
    field :is_cover_pinned, :boolean, default: false
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
  end
end

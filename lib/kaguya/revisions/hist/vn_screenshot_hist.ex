defmodule Kaguya.Revisions.Hist.VnScreenshotHist do
  use Ecto.Schema

  @primary_key false

  schema "vn_screenshots_hist" do
    belongs_to :change, Kaguya.Revisions.Change, type: :binary_id
    field :screenshot_id, :binary_id
    field :is_nsfw, :boolean, default: false
    field :is_brutal, :boolean, default: false
    field :release_id, :binary_id
  end
end

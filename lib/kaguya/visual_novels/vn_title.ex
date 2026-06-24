defmodule Kaguya.VisualNovels.VNTitle do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel

  schema "vn_titles" do
    belongs_to :visual_novel, VisualNovel
    field :lang, :string
    field :official, :boolean, default: true
    field :title, :string
    field :latin, :string
  end
end

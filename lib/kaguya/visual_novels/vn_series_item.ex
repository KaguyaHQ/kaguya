defmodule Kaguya.VisualNovels.VNSeriesItem do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.{VisualNovel, Series}

  @primary_key false

  schema "vn_series_items" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :vn_series, Series, primary_key: true
    field :position, :float

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:visual_novel_id, :vn_series_id, :position])
    |> validate_required([:visual_novel_id, :vn_series_id, :position])
    |> foreign_key_constraint(:visual_novel_id)
    |> foreign_key_constraint(:vn_series_id)
  end
end

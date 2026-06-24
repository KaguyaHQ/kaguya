defmodule Kaguya.VisualNovels.VnExternalLink do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel

  @primary_key false
  schema "vn_external_links" do
    field :site, :string
    field :value, :string

    belongs_to :visual_novel, VisualNovel, foreign_key: :vn_id

    timestamps(type: :utc_datetime)
  end

  def changeset(external_link, attrs) do
    external_link
    |> cast(attrs, [:site, :value, :vn_id])
    |> validate_required([:site, :value, :vn_id])
    |> validate_length(:site, max: 50)
    |> validate_length(:value, max: 1000)
    |> assoc_constraint(:visual_novel)
  end
end

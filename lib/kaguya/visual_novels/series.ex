defmodule Kaguya.VisualNovels.Series do
  use Kaguya.Schema

  alias Kaguya.Utils
  alias Kaguya.Producers.VNSeriesProducer
  alias Kaguya.VisualNovels.{VisualNovel, VNSeriesItem}

  @sources [:user, :vndb_sync]

  schema "vn_series" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :entry_count, :integer, virtual: true
    field :primary_image_url, :string, virtual: true
    field :root_cover_needs_blur, :boolean, virtual: true
    field :root_has_ero, :boolean, virtual: true
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false
    field :source, Ecto.Enum, values: @sources, default: :vndb_sync
    field :manual_fields, {:array, :string}, default: []

    belongs_to :imported_root_visual_novel, VisualNovel

    has_many :vn_series_items, VNSeriesItem, foreign_key: :vn_series_id
    has_many :series_producers, VNSeriesProducer, foreign_key: :vn_series_id
    has_many :visual_novels, through: [:vn_series_items, :visual_novel]

    # VNs where this is the primary series
    has_many :primary_visual_novels, VisualNovel, foreign_key: :primary_vn_series_id

    timestamps()
  end

  def changeset(series, attrs) do
    series
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :hidden_at,
      :is_locked,
      :source,
      :manual_fields,
      :imported_root_visual_novel_id
    ])
    |> Utils.put_unique_slug(:name)
    |> validate_required([:name, :slug])
    |> validate_change(:manual_fields, fn :manual_fields, fields ->
      invalid =
        fields
        |> List.wrap()
        |> Enum.map(&to_string/1)
        |> Enum.reject(&(&1 in ["general", "entries", "producers"]))

      if invalid == [], do: [], else: [manual_fields: "contains invalid value"]
    end)
    |> unique_constraint(:slug)
  end
end

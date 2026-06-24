defmodule Kaguya.Releases.Release do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Releases.ReleaseExtlink

  schema "vn_releases" do
    belongs_to :visual_novel, VisualNovel
    has_many :extlinks, ReleaseExtlink, foreign_key: :vn_release_id

    field :vndb_id, :string
    field :title, :string
    field :display_title, :string
    field :latin_title, :string
    field :original_language, :string
    field :release_date, :date
    field :release_type, :string
    field :patch, :boolean, default: false
    field :freeware, :boolean, default: false
    field :official, :boolean, default: true
    field :has_ero, :boolean, default: false
    field :uncensored, :boolean
    field :voiced, :integer
    field :minage, :integer
    field :engine, :string
    field :platforms, {:array, :string}, default: []
    field :languages, {:array, :string}, default: []
    field :mtl_languages, {:array, :string}, default: []
    field :producers, {:array, :map}, default: []
    field :notes, :string
    field :reso_x, :integer
    field :reso_y, :integer
    field :media, {:array, :map}, default: []

    # Moderation
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(release, attrs) do
    release
    |> cast(attrs, [
      :visual_novel_id,
      :vndb_id,
      :title,
      :display_title,
      :latin_title,
      :original_language,
      :release_date,
      :release_type,
      :patch,
      :freeware,
      :official,
      :has_ero,
      :uncensored,
      :voiced,
      :minage,
      :engine,
      :platforms,
      :languages,
      :mtl_languages,
      :producers,
      :notes,
      :reso_x,
      :reso_y,
      :media
    ])
    |> validate_required([:visual_novel_id, :title])
    |> validate_length(:notes, max: 5000)
    |> assoc_constraint(:visual_novel)
    |> unique_constraint([:vndb_id, :visual_novel_id])
  end
end

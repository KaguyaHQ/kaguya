defmodule Kaguya.VisualNovels.VisualNovel do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.{
    Relation,
    VNTag,
    VNTitle,
    VnExternalLink,
    Image,
    Series,
    VNSeriesItem
  }

  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.Release
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Tags.Tag
  alias Kaguya.Utils

  schema "visual_novels" do
    field :title, :string
    field :description, :string
    field :slug, :string

    # VN-specific fields
    field :vndb_id, :string
    field :development_status, :string
    field :length_category, :string
    field :length_minutes, :integer
    field :original_language, :string
    field :release_date, :date
    field :min_age, :integer
    field :has_ero, :boolean, default: false
    field :is_avn, :boolean, default: false
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false
    field :title_category, Ecto.Enum, values: [:vn, :nukige, :adjacent], default: :vn

    # Aggregated stats
    field :average_rating, :float
    field :ratings_count, :integer, default: 0
    field :ratings_dist, {:array, :integer}, default: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    field :reviews_count, :integer, default: 0

    # VNDB reference scores
    field :vndb_rating, :decimal
    field :vndb_vote_count, :integer

    # Latin-script aliases from VNDB (for search)
    field :aliases, {:array, :string}, default: []

    # Image
    field :temp_image_url, :string
    field :is_cover_pinned, :boolean, default: false
    belongs_to :primary_image, Image, foreign_key: :primary_image_id
    belongs_to :featured_screenshot, Screenshot, foreign_key: :featured_screenshot_id

    # Associations
    has_many :vn_titles, VNTitle
    has_many :vn_producers, VNProducer
    many_to_many :producers, Producer, join_through: VNProducer, on_replace: :delete
    many_to_many :tags, Tag, join_through: "vn_tags"
    has_many :vn_tags, VNTag
    has_many :vn_releases, Release
    has_many :vn_screenshots, Screenshot
    has_many :vn_images, Image
    has_many :external_links, VnExternalLink, foreign_key: :vn_id
    has_many :vn_relations, Relation, foreign_key: :visual_novel_id
    has_many :reading_statuses, ReadingStatus

    # Moderation
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false

    # Content completeness — computed by Kaguya.ContentScore on every user
    # edit. Not user-editable; not cast in changeset.
    field :content_score, :integer, default: 0
    field :content_score_breakdown, :map, default: %{}
    field :content_score_updated_at, :utc_datetime

    # Series
    belongs_to :primary_vn_series, Series
    field :primary_series_position, :float
    has_many :vn_series_items, VNSeriesItem

    timestamps(type: :utc_datetime)
  end

  def changeset(visual_novel, attrs) do
    visual_novel
    |> cast(attrs, [
      :title,
      :description,
      :vndb_id,
      :development_status,
      :length_category,
      # length_minutes — sync-only. Set directly via Repo.insert_all/update_all
      # by dump_sync/vndb_sync. Users edit length_category instead. Still kept
      # in the schema + vn_hist so revert restores it when present.
      :original_language,
      :release_date,
      :min_age,
      :has_ero,
      :is_avn,
      :is_image_nsfw,
      :is_image_suggestive,
      :average_rating,
      :ratings_count,
      :ratings_dist,
      :reviews_count,
      :vndb_rating,
      :vndb_vote_count,
      :aliases,
      :temp_image_url,
      :primary_image_id,
      :primary_vn_series_id,
      :primary_series_position,
      :title_category
    ])
    |> Utils.put_unique_slug(:title)
    |> validate_required([:title, :slug])
    |> validate_length(:title, min: 1, max: 1000)
    |> validate_length(:description, max: 5000)
    |> unique_constraint(:slug)
    |> unique_constraint(:vndb_id)
  end
end

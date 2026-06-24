defmodule Kaguya.Producers.Producer do
  use Kaguya.Schema

  alias Kaguya.Producers.{VNProducer, ProducerExternalLink, ProducerImage}
  alias Kaguya.Utils

  schema "producers" do
    field :vndb_id, :string
    field :name, :string
    field :description, :string
    field :producer_type, :string
    field :language, :string
    field :slug, :string
    field :primary_image_id, :binary_id
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false

    # Moderation
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false

    field :follower_count, :integer, default: 0

    has_many :vn_producers, VNProducer
    has_many :external_links, ProducerExternalLink
    has_many :producer_images, ProducerImage
    belongs_to :primary_image, ProducerImage, foreign_key: :primary_image_id, define_field: false

    timestamps(type: :utc_datetime)
  end

  def changeset(producer, attrs) do
    producer
    |> cast(attrs, [
      :vndb_id,
      :name,
      :description,
      :producer_type,
      :language,
      :slug,
      :primary_image_id,
      :is_image_nsfw,
      :is_image_suggestive
    ])
    |> validate_required([:name])
    |> validate_length(:description, max: 5000)
    |> Utils.put_unique_slug(:name)
    |> unique_constraint(:vndb_id)
    |> unique_constraint(:slug)
  end
end

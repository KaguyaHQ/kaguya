defmodule Kaguya.Producers.ProducerImage do
  use Kaguya.Schema

  alias Kaguya.Producers.Producer
  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "producer_images" do
    belongs_to :producer, Producer
    belongs_to :uploader, User, foreign_key: :uploaded_by

    field :width, :integer
    field :height, :integer
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(producer_image, attrs) do
    producer_image
    |> cast(attrs, [
      :id,
      :producer_id,
      :width,
      :height,
      :uploaded_by,
      :is_image_nsfw,
      :is_image_suggestive
    ])
    |> validate_required([:producer_id])
    |> assoc_constraint(:producer)
  end
end

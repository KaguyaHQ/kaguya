defmodule Kaguya.Characters.CharacterImage do
  use Kaguya.Schema

  alias Kaguya.Characters.Character
  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "character_images" do
    belongs_to :character, Character
    belongs_to :uploader, User, foreign_key: :uploaded_by

    field :width, :integer
    field :height, :integer
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(character_image, attrs) do
    character_image
    |> cast(attrs, [
      :id,
      :character_id,
      :width,
      :height,
      :uploaded_by,
      :is_image_nsfw,
      :is_image_suggestive
    ])
    |> validate_required([:character_id])
    |> assoc_constraint(:character)
  end
end

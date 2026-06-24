defmodule Kaguya.Characters.Character do
  use Kaguya.Schema

  alias Kaguya.Characters.{VNCharacter, CharacterImage}
  alias Kaguya.Utils

  # VNDB thresholds: sexual/violence_avg stored as 0-200 (vote * 100)
  # Level 2 (explicit/nsfw): > 130, Level 1 (suggestive): > 40
  @sexual_suggestive_threshold 40
  @sexual_explicit_threshold 130

  schema "characters" do
    field :vndb_id, :string
    field :name, :string
    field :description, :string
    field :slug, :string

    # Physical attributes
    field :sex, Ecto.Enum, values: [:male, :female, :both, :unknown]
    field :spoiler_sex, Ecto.Enum, values: [:male, :female, :both, :unknown]
    field :gender, Ecto.Enum, values: [:male, :female, :other, :ambiguous]
    field :spoiler_gender, Ecto.Enum, values: [:male, :female, :other, :ambiguous]
    field :blood_type, Ecto.Enum, values: [:a, :b, :ab, :o]
    field :height, :integer
    field :weight, :integer
    field :age, :integer
    field :birthday, :integer
    field :bust, :integer
    field :waist, :integer
    field :hip, :integer
    field :cup_size, :string

    # Image
    field :vndb_image_id, :string
    field :primary_image_id, :binary_id
    field :temp_image_url, :string
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false

    # Moderation
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false

    # Denormalized like count, kept in sync by Characters.like_character/2 and unlike_character/2
    field :likes_count, :integer, default: 0

    # Denormalized counter of users who have this character in their
    # profile's `favorite_characters` array. Kept in sync by
    # Users.update_user/2 and Users.delete_user/1. Backfilled by the
    # AddFavoritesCountToCharacters migration.
    field :favorites_count, :integer, default: 0

    has_many :vn_characters, VNCharacter
    has_many :character_images, CharacterImage

    timestamps(type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [
      :vndb_id,
      :name,
      :description,
      :sex,
      :spoiler_sex,
      :gender,
      :spoiler_gender,
      :blood_type,
      :height,
      :weight,
      :age,
      :birthday,
      :bust,
      :waist,
      :hip,
      :cup_size,
      :vndb_image_id,
      :primary_image_id,
      :is_image_nsfw,
      :is_image_suggestive
    ])
    |> Utils.put_unique_slug(:name)
    |> validate_required([:name, :slug])
    |> validate_length(:description, max: 5000)
    |> unique_constraint(:vndb_id)
    |> unique_constraint(:slug)
  end

  # VNDB value mappings for import
  def map_sex("m"), do: :male
  def map_sex("f"), do: :female
  def map_sex("b"), do: :both
  def map_sex("n"), do: :unknown
  def map_sex(_), do: nil

  def map_gender("m"), do: :male
  def map_gender("f"), do: :female
  def map_gender("o"), do: :other
  def map_gender("a"), do: :ambiguous
  def map_gender(_), do: nil

  def map_blood_type("a"), do: :a
  def map_blood_type("b"), do: :b
  def map_blood_type("ab"), do: :ab
  def map_blood_type("o"), do: :o
  def map_blood_type(_), do: nil

  def image_nsfw?(sexual_avg), do: sexual_avg > @sexual_explicit_threshold
  def image_suggestive?(sexual_avg), do: sexual_avg > @sexual_suggestive_threshold
end

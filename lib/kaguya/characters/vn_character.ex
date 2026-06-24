defmodule Kaguya.Characters.VNCharacter do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Characters.Character

  @primary_key false

  schema "vn_characters" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :character, Character, primary_key: true

    field :role, Ecto.Enum, values: [:main, :primary, :side, :appears]
    field :spoiler_level, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_character, attrs) do
    vn_character
    |> cast(attrs, [:visual_novel_id, :character_id, :role, :spoiler_level])
    |> validate_required([:visual_novel_id, :character_id, :role])
    |> validate_inclusion(:spoiler_level, 0..2)
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:character)
  end
end

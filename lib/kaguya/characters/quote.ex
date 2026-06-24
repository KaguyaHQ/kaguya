defmodule Kaguya.Characters.Quote do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Characters.Character

  schema "vn_quotes" do
    belongs_to :visual_novel, VisualNovel
    belongs_to :character, Character
    belongs_to :creator, Kaguya.Users.User, foreign_key: :created_by

    field :quote, :string
    field :score, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :favorites_count, :integer, default: 0
    field :vndb_id, :string

    field :liked_by_me, :boolean, virtual: true, default: false
    field :favorited_by_me, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_quote, attrs) do
    vn_quote
    |> cast(attrs, [:visual_novel_id, :character_id, :quote, :score, :vndb_id, :created_by])
    |> validate_required([:visual_novel_id, :quote])
    |> validate_length(:quote, min: 2, max: 2000)
    |> unique_constraint(:vndb_id)
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:character)
  end
end

defmodule Kaguya.Lists.ListCharacterItem do
  @moduledoc """
  Membership row for character lists (`lists.item_type == "character"`).
  Mirrors `Kaguya.Lists.ListItem`, keyed by character instead of VN.
  """
  use Ecto.Schema

  alias Kaguya.Characters.Character
  alias Kaguya.Lists.{List, ListTier}

  @primary_key false
  @foreign_key_type :binary_id

  schema "list_character_items" do
    belongs_to :list, List, primary_key: true
    belongs_to :character, Character, primary_key: true
    belongs_to :tier, ListTier
    field :position, :integer
    field :tier_position, :integer

    timestamps(type: :utc_datetime)
  end
end

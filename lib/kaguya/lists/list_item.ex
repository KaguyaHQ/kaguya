defmodule Kaguya.Lists.ListItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.Lists.{List, ListTier}
  alias Kaguya.VisualNovels.VisualNovel

  @primary_key false
  @foreign_key_type :binary_id

  schema "list_items" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :list, List, primary_key: true
    belongs_to :tier, ListTier
    field :position, :integer
    field :tier_position, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(list_item, attrs) do
    list_item
    |> cast(attrs, [:visual_novel_id, :list_id, :position, :tier_id, :tier_position])
    |> validate_required([:visual_novel_id, :list_id, :position])
    |> validate_number(:tier_position, greater_than: 0)
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:list)
    |> assoc_constraint(:tier)
  end
end

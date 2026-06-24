defmodule Kaguya.Lists.ListTier do
  use Kaguya.Schema

  alias Kaguya.Lists.List

  schema "list_tiers" do
    field :label, :string
    field :color, :string
    field :position, :integer

    belongs_to :list, List

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [:list_id, :label, :color, :position])
    |> validate_required([:list_id, :label, :color, :position])
    |> validate_length(:label, min: 1, max: 24)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:list)
    |> unique_constraint([:list_id, :position], name: :list_tiers_list_id_position_unique)
  end
end

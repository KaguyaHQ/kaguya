defmodule Kaguya.Lists.List do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Lists.{ListItem, ListTier}
  alias Kaguya.Utils

  @activity_fields [:name, :description, :is_ranked, :is_public, :display_mode]
  @item_types ["vn", "character"]

  schema "lists" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :is_ranked, :boolean, default: false
    field :display_mode, :string, default: "grid"
    field :item_type, :string, default: "vn"
    field :is_public, :boolean, default: true
    field :vns_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :comments_count, :integer, default: 0
    field :trending_score, :float, default: 0.0
    field :last_activity_at, :utc_datetime
    field :hidden_at, :utc_datetime

    field :contains_vn, :boolean, virtual: true, default: false

    belongs_to :user, User
    has_many :tiers, ListTier

    many_to_many :visual_novels, VisualNovel, join_through: ListItem

    timestamps(type: :utc_datetime)
  end

  def item_types, do: @item_types

  @doc """
  Changeset for a new list. `item_type` is set here rather than cast, because
  it can't change once the list has items.
  """
  def create_changeset(list, attrs, item_type) do
    list
    |> change(item_type: item_type)
    |> changeset(attrs)
  end

  @doc false
  def changeset(list, attrs) do
    list
    |> cast(attrs, [:user_id, :name, :description, :is_ranked, :display_mode, :is_public])
    |> validate_required([:user_id, :name])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:display_mode, ["grid", "tier"])
    |> validate_inclusion(:item_type, @item_types)
    # Slugs are unique per owner, matching /@username/list/:slug URLs.
    |> Utils.put_unique_slug(:name)
    |> unique_constraint([:user_id, :slug])
    |> unique_constraint([:user_id, :name],
      error_key: :name,
      message: "is already used by another of your lists"
    )
    |> maybe_touch_last_activity()
  end

  defp maybe_touch_last_activity(changeset) do
    if new_record?(changeset) or activity_changed?(changeset) do
      put_change(changeset, :last_activity_at, current_time())
    else
      changeset
    end
  end

  defp new_record?(%{data: %{id: nil}}), do: true
  defp new_record?(_), do: false

  defp activity_changed?(changeset) do
    Enum.any?(@activity_fields, &Map.has_key?(changeset.changes, &1))
  end

  defp current_time do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end

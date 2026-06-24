defmodule Kaguya.Revisions.Change do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type :binary_id

  @entity_types [:visual_novel, :character, :producer, :release, :series]
  @actions [:create, :edit, :revert, :hide, :unhide, :lock, :unlock]
  @sources [:user, :vndb_sync, :system]

  schema "changes" do
    field :entity_type, Ecto.Enum, values: @entity_types
    field :entity_id, :binary_id
    field :revision_number, :integer
    field :action, Ecto.Enum, values: @actions
    field :changed_fields, {:array, :string}, default: []
    field :summary, :string
    field :source, Ecto.Enum, values: @sources, default: :user

    belongs_to :user, Kaguya.Users.User

    # Virtual — populated by get_revision/1 from _hist tables
    field :snapshot, :map, virtual: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :revision_number,
      :action,
      :changed_fields,
      :summary,
      :source,
      :user_id
    ])
    |> validate_required([:entity_type, :entity_id, :revision_number, :action, :summary])
    |> validate_length(:summary, min: 2, max: 5000)
    |> validate_number(:revision_number, greater_than: 0)
    |> unique_constraint([:entity_type, :entity_id, :revision_number])
  end
end

defmodule Kaguya.Activities.UserActivity do
  use Kaguya.Schema

  alias Kaguya.Users.User

  @actions [
    :reviewed,
    :rated,
    :status_changed,
    :liked_review,
    :liked_list,
    :liked_screenshot,
    :liked_cover,
    :created_list,
    :followed,
    :commented,
    :recommended_similar,
    :imported_vndb,
    :created_post,
    :voted_tag,
    :added_quote,
    :liked_quote,
    :edited_entity,
    :reverted_entity,
    :created_entity
  ]

  schema "user_activities" do
    belongs_to :user, User

    field :action, Ecto.Enum, values: @actions
    field :entity_type, :string
    field :entity_id, :binary_id
    field :metadata, :map, default: %{}

    # Virtual fields populated by Activities.preload_associations/1
    field :review, :map, virtual: true
    field :list, :map, virtual: true
    field :followed_user, :map, virtual: true
    field :followed_producer, :map, virtual: true
    field :actor, :map, virtual: true
    field :entity_ref, :map, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:user_id, :action, :entity_type, :entity_id, :metadata])
    |> validate_required([:user_id, :action, :entity_type, :entity_id])
    |> assoc_constraint(:user)
  end
end

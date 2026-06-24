defmodule Kaguya.VisualNovels.SavedBrowseFilter do
  use Kaguya.Schema

  alias Kaguya.Users.User

  @sort_options [
    :average_rating_desc,
    :average_rating_asc,
    :total_ratings_desc,
    :total_ratings_asc,
    :release_date_desc,
    :release_date_asc
  ]

  schema "saved_browse_filters" do
    field :name, :string
    field :filters, :map, default: %{}
    field :sort_by, Ecto.Enum, values: @sort_options
    field :is_default, :boolean, default: false

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(filter, attrs) do
    filter
    |> cast(attrs, [:user_id, :name, :filters, :sort_by, :is_default])
    |> validate_required([:user_id, :name, :filters])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint([:user_id, :name])
    |> assoc_constraint(:user)
  end
end

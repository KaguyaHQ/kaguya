defmodule Kaguya.Shelves.Shelf do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Shelves.ShelfItem
  alias Kaguya.Utils

  schema "shelves" do
    field :name, :string
    field :slug, :string
    field :vns_count, :integer, default: 0

    belongs_to :user, User

    many_to_many :visual_novels, VisualNovel,
      join_through: ShelfItem,
      join_keys: [shelf_id: :id, visual_novel_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(shelf, attrs) do
    shelf
    |> cast(attrs, [:user_id, :name])
    |> validate_required([:user_id, :name])
    |> validate_length(:name, max: 100)
    |> Utils.put_unique_slug(:name)
    |> unique_constraint([:user_id, :slug])
    |> unique_constraint([:user_id, :name])
  end
end

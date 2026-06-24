defmodule Kaguya.Shelves.ShelfItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Shelves.Shelf

  @primary_key false
  @foreign_key_type :binary_id

  schema "shelf_items" do
    belongs_to :visual_novel, VisualNovel, primary_key: true
    belongs_to :shelf, Shelf, primary_key: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(shelf_item, attrs) do
    shelf_item
    |> cast(attrs, [:visual_novel_id, :shelf_id])
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:shelf)
  end
end

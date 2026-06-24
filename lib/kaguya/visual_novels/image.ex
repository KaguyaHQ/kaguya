defmodule Kaguya.VisualNovels.Image do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "vn_images" do
    belongs_to :visual_novel, VisualNovel
    belongs_to :uploader, User, foreign_key: :uploaded_by

    field :vndb_cv_id, :string
    field :width, :integer
    field :height, :integer
    field :likes_count, :integer, default: 0
    field :vndb_votes, :integer, default: 0
    field :language, :string
    field :release_date, :date
    field :is_image_nsfw, :boolean, default: false
    field :is_image_suggestive, :boolean, default: false

    # Virtual field for generated image URLs.
    field :liked_by_me, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_image, attrs) do
    vn_image
    |> cast(attrs, [
      :id,
      :visual_novel_id,
      :vndb_cv_id,
      :width,
      :height,
      :uploaded_by,
      :is_image_nsfw,
      :is_image_suggestive,
      :language,
      :release_date
    ])
    |> validate_required([:visual_novel_id])
    |> unique_constraint([:visual_novel_id, :vndb_cv_id])
    |> assoc_constraint(:visual_novel)
  end
end

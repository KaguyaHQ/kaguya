defmodule Kaguya.Screenshots.Screenshot do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Releases.Release
  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "vn_screenshots" do
    belongs_to :visual_novel, VisualNovel
    belongs_to :release, Release, foreign_key: :release_id
    belongs_to :uploader, User, foreign_key: :uploaded_by

    field :vndb_sf_id, :string
    field :width, :integer
    field :height, :integer
    field :likes_count, :integer, default: 0
    field :is_nsfw, :boolean, default: false
    field :is_brutal, :boolean, default: false
    field :s3_key, :string

    # Virtual field for generated image URLs.
    field :liked_by_me, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(screenshot, attrs) do
    screenshot
    |> cast(attrs, [
      :id,
      :visual_novel_id,
      :vndb_sf_id,
      :width,
      :height,
      :is_nsfw,
      :is_brutal,
      :release_id,
      :uploaded_by,
      :s3_key
    ])
    |> validate_required([:visual_novel_id])
    |> unique_constraint(:vndb_sf_id)
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:release)
  end
end

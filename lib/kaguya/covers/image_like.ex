defmodule Kaguya.Covers.ImageLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.Image

  @primary_key false
  @foreign_key_type :binary_id
  schema "vn_image_likes" do
    belongs_to :user, User, primary_key: true
    belongs_to :vn_image, Image, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :vn_image_id])
    |> validate_required([:user_id, :vn_image_id])
    |> unique_constraint([:user_id, :vn_image_id], name: :vn_image_likes_pkey)
  end
end

defmodule Kaguya.Screenshots.ScreenshotLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Screenshots.Screenshot

  @primary_key false
  @foreign_key_type :binary_id
  schema "vn_screenshot_likes" do
    belongs_to :user, User, primary_key: true
    belongs_to :vn_screenshot, Screenshot, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :vn_screenshot_id])
    |> validate_required([:user_id, :vn_screenshot_id])
    |> unique_constraint([:user_id, :vn_screenshot_id], name: :vn_screenshot_likes_pkey)
  end
end

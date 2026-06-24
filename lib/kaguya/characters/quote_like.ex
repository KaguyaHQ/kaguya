defmodule Kaguya.Characters.QuoteLike do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Characters.Quote

  @primary_key false
  @foreign_key_type :binary_id
  schema "vn_quote_likes" do
    belongs_to :user, User, primary_key: true
    belongs_to :vn_quote, Quote, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_id, :vn_quote_id])
    |> validate_required([:user_id, :vn_quote_id])
    |> unique_constraint([:user_id, :vn_quote_id], name: :vn_quote_likes_pkey)
  end
end

defmodule Kaguya.Characters.QuoteFavorite do
  @moduledoc """
  Join table row representing "user U has VN quote Q pinned to their
  profile favorites at position P". Mirrors `CharacterFavorite`.

  Writes happen via:
    * `Kaguya.Users.update_user/2` — replaces the whole list (used by the
      Favorites editor / reorder UI).
    * `Kaguya.Users.add_favorite_quote/2` and
      `Kaguya.Users.remove_favorite_quote/2` — single-row toggle used by
      the inline bookmark icon on quote cards.

  Both paths keep the `vn_quotes.favorites_count` denormalized counter in
  sync inside the same transaction.
  """

  use Ecto.Schema

  alias Kaguya.Users.User
  alias Kaguya.Characters.Quote

  @primary_key false
  @foreign_key_type :binary_id

  schema "quote_favorites" do
    belongs_to :user, User, primary_key: true, type: :binary_id
    belongs_to :vn_quote, Quote, primary_key: true, type: :binary_id

    field :position, :integer

    # Single timestamp: a favorite row either exists or doesn't. Position
    # changes update the row's `position` column; the original
    # `inserted_at` is preserved across reorders.
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

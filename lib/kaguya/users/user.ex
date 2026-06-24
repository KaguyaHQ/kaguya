defmodule Kaguya.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.Users.{SocialLinks, UserIdentity}

  @roles ~w(user moderator admin)a
  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :email, :string
    field :authenticated_at, :utc_datetime, virtual: true
    field :avatar_id, :binary_id
    field :banner_id, :binary_id
    field :bio, :string
    field :role, Ecto.Enum, values: @roles, default: :user

    embeds_one :social_links, SocialLinks, on_replace: :update
    has_many :identities, UserIdentity

    field :vn_ratings_dist, {:array, :integer},
      source: :ratings_dist,
      default: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    field :vn_ratings_count, :integer, source: :ratings_count, default: 0
    field :vn_reviews_count, :integer, source: :reviews_count, default: 0
    field :vn_average_rating, :float, source: :average_rating, default: 0.0
    field :favorite_visual_novels, {:array, :binary_id}, default: []
    # favorite_characters moved out of the user row into the
    # `character_favorites` join table. `Kaguya.Users.update_user/2`
    # pops :favorite_characters off the attrs map and routes it to the
    # join table; the changeset below never sees it.
    field :show_nsfw_images, :boolean, default: false
    field :show_nukige, :boolean, default: true
    field :show_adjacent, :boolean, default: true
    field :show_nsfw_screenshots, :boolean, default: false
    field :show_brutal_screenshots, :boolean, default: false
    field :ratings_suppressed, :boolean, default: false
    field :edit_count, :integer, default: 0

    # Restriction flags (default true — turn off to restrict)
    field :can_edit, :boolean, default: true
    field :can_discuss, :boolean, default: true
    field :can_review, :boolean, default: true
    field :can_list, :boolean, default: true

    # Mod capability flags (default false — turn on to elevate)
    field :mod_db, :boolean, default: false
    field :mod_discussions, :boolean, default: false
    field :mod_reviews, :boolean, default: false
    field :mod_lists, :boolean, default: false
    field :mod_users, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    # `:favorite_characters` is intentionally NOT cast — it lives in the
    # `character_favorites` join table now. `Kaguya.Users.update_user/2`
    # pops it from `attrs` before this changeset ever runs.
    user
    |> cast(attrs, [
      :id,
      :username,
      :display_name,
      :email,
      :avatar_id,
      :banner_id,
      :bio,
      :favorite_visual_novels,
      :vn_ratings_dist,
      :vn_ratings_count,
      :vn_average_rating,
      :vn_reviews_count,
      :show_nsfw_images,
      :show_nukige,
      :show_adjacent,
      :show_nsfw_screenshots,
      :show_brutal_screenshots
    ])
    |> strip_nils(:favorite_visual_novels)
    |> validate_favorites_limit(:favorite_visual_novels)
    |> cast_embed(:social_links, with: &SocialLinks.changeset/2)
    |> sanitize_display_name()
    |> validate_length(:username, min: 3, max: 30)
    |> validate_length(:display_name, min: 1, max: 36)
    |> validate_visible_display_name()
    |> validate_length(:bio, max: 500)
    |> validate_format(:email, ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/,
      message: "is not a valid email"
    )
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
      message: "can only contain letters, numbers, and underscores"
    )
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end

  def create_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> validate_required([:email])
  end

  # Invisible characters: Unicode separators, format chars, braille blank, hangul filler
  @invisible_leading Regex.compile!("\\A[\\p{Z}\\p{Cf}\\x{2800}\\x{3164}]+", "u")
  @invisible_trailing Regex.compile!("[\\p{Z}\\p{Cf}\\x{2800}\\x{3164}]+\\z", "u")
  @invisible_interior Regex.compile!("[\\p{Z}\\p{Cf}\\x{2800}\\x{3164}]+", "u")

  defp sanitize_display_name(changeset) do
    update_change(changeset, :display_name, fn name ->
      name
      |> String.replace(@invisible_leading, "")
      |> String.replace(@invisible_trailing, "")
      |> String.replace(@invisible_interior, " ")
    end)
  end

  defp validate_visible_display_name(changeset) do
    validate_change(changeset, :display_name, fn :display_name, name ->
      if String.match?(name, ~r/[^\p{Z}\p{Cf}\p{Cc}\x{2800}\x{3164}]/u) do
        []
      else
        [display_name: "must contain at least one visible character"]
      end
    end)
  end

  # Kaguya is free — there are no paid tiers. Favorites are capped only as an
  # abuse/perf guard, with a single generous flat limit for everyone.
  @favorites_limit 100
  @quote_favorites_limit 100

  def favorites_limit(%__MODULE__{}), do: @favorites_limit

  def quote_favorites_limit(%__MODULE__{}), do: @quote_favorites_limit

  defp validate_favorites_limit(changeset, field) do
    validate_length(changeset, field, max: @favorites_limit)
  end

  @type t :: %__MODULE__{}

  defp strip_nils(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      list -> put_change(changeset, field, Enum.reject(list, &is_nil/1))
    end
  end
end

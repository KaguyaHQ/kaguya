defmodule Kaguya.Discussions.Post do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Discussions.Comment
  alias Kaguya.Discussions.Category

  @category_types Category.category_types()

  @short_id_alphabet ~c"23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
  @short_id_length 8

  schema "posts" do
    belongs_to :user, User
    belongs_to :last_comment_user, User

    has_many :comments, Comment

    field :title, :string
    field :slug, :string
    field :short_id, :string
    field :content, :string
    field :category_type, Ecto.Enum, values: @category_types
    field :entity_id, :binary_id
    field :comments_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :last_comment_at, :utc_datetime
    field :is_pinned, :boolean, default: false
    field :is_locked, :boolean, default: false
    field :is_edited, :boolean, default: false
    field :hidden_at, :utc_datetime
    field :hidden_reason, :string
    field :hidden_mod_note, :string
    field :deleted_at, :utc_datetime
    field :deleted_by_type, Ecto.Enum, values: [:user, :admin]

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :content, :user_id, :category_type, :entity_id, :is_edited])
    |> validate_required([:title, :user_id, :category_type])
    |> validate_length(:title, max: 200)
    |> validate_length(:content, max: 20_000)
    |> validate_inclusion(:category_type, @category_types)
    |> validate_entity_id()
    |> maybe_put_short_id()
    |> maybe_regenerate_slug()
    |> assoc_constraint(:user)
    |> unique_constraint(:short_id)
  end

  @doc """
  Generates an 8-character base62-ish short id. Used in URLs as the canonical
  identifier (the slug is decorative). Collision-resistant up to billions of posts.
  """
  def generate_short_id do
    alphabet = @short_id_alphabet
    size = length(alphabet)

    1..@short_id_length
    |> Enum.map(fn _ -> Enum.at(alphabet, :rand.uniform(size) - 1) end)
    |> List.to_string()
  end

  defp validate_entity_id(changeset) do
    category_type = get_field(changeset, :category_type)
    entity_id = get_field(changeset, :entity_id)

    cond do
      Category.entity_category?(category_type) and is_nil(entity_id) ->
        add_error(changeset, :entity_id, "is required for #{category_type} categories")

      category_type != nil and not Category.entity_category?(category_type) and
          not is_nil(entity_id) ->
        add_error(changeset, :entity_id, "must be nil for #{category_type} categories")

      true ->
        changeset
    end
  end

  defp maybe_put_short_id(changeset) do
    if get_field(changeset, :short_id) in [nil, ""] do
      put_change(changeset, :short_id, generate_short_id())
    else
      changeset
    end
  end

  # Slug tracks the title. URLs resolve by short_id, so a stale slug doesn't
  # break links — the frontend redirects to the canonical slug. Regenerate
  # whenever the title changes.
  defp maybe_regenerate_slug(changeset) do
    title_change = get_change(changeset, :title)
    current_slug = get_field(changeset, :slug)

    cond do
      title_change != nil ->
        put_change(changeset, :slug, Kaguya.Utils.slugify_title(title_change))

      current_slug in [nil, ""] ->
        title = get_field(changeset, :title)

        if title,
          do: put_change(changeset, :slug, Kaguya.Utils.slugify_title(title)),
          else: changeset

      true ->
        changeset
    end
  end
end

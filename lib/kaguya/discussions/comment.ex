defmodule Kaguya.Discussions.Comment do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Discussions.Post

  @short_id_alphabet ~c"23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
  @short_id_length 8

  schema "post_comments" do
    field :content, :string
    field :short_id, :string
    field :likes_count, :integer, default: 0
    field :is_pinned, :boolean, default: false
    field :is_edited, :boolean, default: false
    field :hidden_at, :utc_datetime
    field :hidden_reason, :string
    field :hidden_mod_note, :string
    field :pinned_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime
    field :deleted_by_type, Ecto.Enum, values: [:user, :admin]

    belongs_to :post, Post
    belongs_to :user, User
    belongs_to :parent_comment, __MODULE__

    has_many :child_comments, __MODULE__, foreign_key: :parent_comment_id

    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :post_id,
      :user_id,
      :parent_comment_id,
      :content,
      :is_pinned,
      :pinned_at,
      :is_edited
    ])
    |> validate_required([:content])
    |> validate_length(:content, max: 20_000)
    |> maybe_put_short_id()
    |> assoc_constraint(:post)
    |> assoc_constraint(:user)
    |> assoc_constraint(:parent_comment)
    |> unique_constraint(:short_id)
  end

  @doc """
  Generates an 8-character short id matching `Post.generate_short_id/0` so
  comment URLs read the same as post URLs in the Reddit-style scheme.
  """
  def generate_short_id do
    alphabet = @short_id_alphabet
    size = length(alphabet)

    1..@short_id_length
    |> Enum.map(fn _ -> Enum.at(alphabet, :rand.uniform(size) - 1) end)
    |> List.to_string()
  end

  defp maybe_put_short_id(changeset) do
    if get_field(changeset, :short_id) in [nil, ""] do
      put_change(changeset, :short_id, generate_short_id())
    else
      changeset
    end
  end
end

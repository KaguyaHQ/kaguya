defmodule Kaguya.Lists.ListComment do
  use Kaguya.Schema

  alias Kaguya.Lists.List
  alias Kaguya.Users.User

  schema "list_comments" do
    field :content, :string
    field :likes_count, :integer, default: 0
    field :is_edited, :boolean, default: false
    field :hidden_at, :utc_datetime

    belongs_to :list, List
    belongs_to :user, User
    belongs_to :parent_comment, __MODULE__

    has_many :child_comments, __MODULE__, foreign_key: :parent_comment_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vn_list_comment, attrs) do
    vn_list_comment
    |> cast(attrs, [
      :list_id,
      :user_id,
      :parent_comment_id,
      :content,
      :is_edited
    ])
    |> validate_required([:content])
    |> assoc_constraint(:list)
    |> assoc_constraint(:user)
    |> assoc_constraint(:parent_comment)
  end
end

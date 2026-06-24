defmodule Kaguya.Reviews.Review do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Users.User

  schema "reviews" do
    belongs_to :visual_novel, VisualNovel
    belongs_to :user, User

    field :content, :string
    field :likes_count, :integer, default: 0
    field :trending_score, :float, default: 0.0
    field :comments_count, :integer, default: 0
    field :is_edited, :boolean, default: false
    field :is_spoiler, :boolean, default: false
    field :source, :string
    field :hidden_at, :utc_datetime
    field :is_locked, :boolean, default: false

    field :rating, :float, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_review, attrs) do
    vn_review
    |> cast(attrs, [
      :visual_novel_id,
      :user_id,
      :content,
      :likes_count,
      :trending_score,
      :comments_count,
      :is_edited,
      :is_spoiler
    ])
    |> validate_required([:visual_novel_id, :user_id])
    |> validate_content()
    |> unique_constraint([:user_id, :visual_novel_id])
    |> assoc_constraint(:visual_novel)
    |> assoc_constraint(:user)
  end

  @min_content_length 40

  defp validate_content(changeset) do
    content = get_field(changeset, :content)

    cond do
      is_nil(content) or content == "" ->
        add_error(changeset, :content, "review content is required")

      String.length(content) < @min_content_length ->
        add_error(changeset, :content, "must be at least #{@min_content_length} characters")

      true ->
        changeset
    end
  end
end

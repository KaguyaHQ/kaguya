defmodule Kaguya.Shelves.ReadingStatus do
  use Kaguya.Schema

  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Users.User

  schema "reading_statuses" do
    field :status, Ecto.Enum,
      values: [
        :read,
        :did_not_finish,
        :on_hold,
        :want_to_read,
        :currently_reading,
        :not_interested
      ]

    field :date_started, :date
    field :date_finished, :date
    field :library_added_at, :utc_datetime
    field :note, :string
    field :source, :string

    belongs_to :user, User
    belongs_to :visual_novel, VisualNovel

    timestamps(type: :utc_datetime)
  end

  def changeset(vn_reading_status, attrs) do
    vn_reading_status
    |> cast(attrs, [
      :user_id,
      :visual_novel_id,
      :status,
      :date_started,
      :date_finished,
      :library_added_at,
      :note
    ])
    |> validate_required([:user_id, :visual_novel_id, :status])
    |> validate_length(:note, max: 280)
    |> unique_constraint([:user_id, :visual_novel_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:visual_novel)
  end
end

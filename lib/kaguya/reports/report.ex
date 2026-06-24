defmodule Kaguya.Reports.Report do
  use Kaguya.Schema

  alias Kaguya.Users.User

  @statuses [:new, :in_progress, :resolved, :dismissed]
  @categories ~w(spam harassment spoilers off_topic incorrect_info inappropriate other)
  @entity_types ~w(visual_novel character producer release series review
                   review_comment list_comment post_comment
                   post list user other)

  schema "reports" do
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :category, :string, default: "other"
    field :entity_type, :string
    field :entity_id, :binary_id
    field :entity_name, :string
    field :reason, :string
    field :message, :string
    field :resolved_at, :utc_datetime
    field :mod_notes, :string
    field :resolution_note, :string

    belongs_to :reporter, User, foreign_key: :reporter_id
    belongs_to :resolver, User, foreign_key: :resolved_by

    timestamps(type: :utc_datetime)
  end

  def entity_types, do: @entity_types

  def categories, do: @categories

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :entity_name,
      :category,
      :reason,
      :message,
      :reporter_id
    ])
    |> validate_required([:entity_type, :category, :reason, :reporter_id])
    |> validate_inclusion(:entity_type, @entity_types)
    |> validate_inclusion(:category, @categories)
    |> validate_length(:reason, max: 200)
    |> validate_length(:message, max: 5000)
    |> assoc_constraint(:reporter)
    |> unique_constraint([:reporter_id, :entity_type, :entity_id],
      name: :reports_no_duplicate_open,
      message: "You already have an open report for this"
    )
  end

  def resolve_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolved_by, :resolved_at, :mod_notes, :resolution_note])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:mod_notes, max: 5000)
    |> validate_length(:resolution_note, max: 5000)
    |> validate_resolution_note_for_terminal_status()
  end

  defp validate_resolution_note_for_terminal_status(changeset) do
    status = get_field(changeset, :status)
    resolution_note = get_field(changeset, :resolution_note)

    if status in [:resolved, :dismissed] and String.trim(to_string(resolution_note)) == "" do
      add_error(changeset, :resolution_note, "can't be blank")
    else
      changeset
    end
  end
end

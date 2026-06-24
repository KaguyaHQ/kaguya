defmodule Kaguya.VisualNovels.Version do
  @moduledoc """
  A patch entry on a visual novel — answers "what's in v0.11.1?" with
  changelog + content metrics. Sibling to `Kaguya.Releases.Release`,
  which is distribution-level (platform/language/edition).

  Status flips drive moderation:

    * `published` — visible on the VN page.
    * `pending` — in the mod review queue (Patreon-watcher rows land here).
    * `rejected` — kept for audit, hidden everywhere else.
  """

  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @sources ~w(patreon_watcher manual)
  @statuses ~w(pending published rejected)
  @update_types ~w(content bugfix rework)
  @release_types ~w(early public)

  schema "vn_versions" do
    belongs_to :visual_novel, VisualNovel

    field :source, :string
    field :source_id, :string
    field :source_url, :string

    field :version_number, :string
    field :release_date, :utc_datetime
    field :release_type, :string
    field :update_type, :string

    field :changelog, :string
    field :renders_count, :integer
    field :animations_count, :integer
    field :sfx_count, :integer
    field :music_tracks_count, :integer

    field :status, :string, default: "published"
    belongs_to :reviewed_by, User, foreign_key: :reviewed_by_user_id
    field :reviewed_at, :utc_datetime
    field :review_notes, :string

    timestamps(type: :utc_datetime)
  end

  @cast_fields ~w(visual_novel_id source source_id source_url version_number release_date
                  release_type update_type changelog renders_count
                  animations_count sfx_count music_tracks_count status
                  reviewed_by_user_id reviewed_at review_notes)a

  def changeset(version, attrs) do
    version
    |> cast(attrs, @cast_fields)
    |> validate_required([:visual_novel_id, :source, :version_number, :status])
    |> validate_length(:version_number, max: 64)
    |> validate_length(:changelog, max: 100_000)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:update_type, @update_types)
    |> validate_inclusion(:release_type, @release_types)
    |> assoc_constraint(:visual_novel)
    |> unique_constraint([:source, :source_id], name: :vn_versions_source_id_idx)
  end

  @doc """
  Changeset for mod edits — only the fields a moderator may change in
  the review UI. Status, reviewer, reviewed_at, review_notes are set by
  approve/reject helpers in the context, not by this changeset.
  """
  @mod_edit_fields ~w(version_number release_date release_type update_type
                      changelog renders_count animations_count sfx_count
                      music_tracks_count)a

  def mod_edit_changeset(version, attrs) do
    version
    |> cast(attrs, @mod_edit_fields)
    |> validate_required([:version_number])
    |> validate_length(:version_number, max: 64)
    |> validate_length(:changelog, max: 100_000)
    |> validate_inclusion(:update_type, @update_types)
    |> validate_inclusion(:release_type, @release_types)
  end

  @doc "Allowed values for the source enum."
  def sources, do: @sources

  @doc "Allowed values for the status enum."
  def statuses, do: @statuses

  @doc "Allowed values for the update_type enum (when not nil)."
  def update_types, do: @update_types

  @doc "Allowed values for the release_type enum (when not nil)."
  def release_types, do: @release_types
end

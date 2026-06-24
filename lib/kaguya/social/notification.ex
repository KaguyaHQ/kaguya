defmodule Kaguya.Social.Notification do
  use Kaguya.Schema

  alias Kaguya.Users.User
  alias Kaguya.Social.Notification.Metadata

  @notification_actions [
    :like,
    :follow,
    :new_comment,
    :reply,
    :mention,
    :system,
    :content_removed,
    :report_reviewed
  ]

  @notification_entities [
    :user,
    :review,
    :comment,
    :list,
    :vn_list,
    :post,
    :report
  ]

  schema "notifications" do
    field :action, Ecto.Enum, values: @notification_actions
    field :entity_type, Ecto.Enum, values: @notification_entities
    field :entity_id, :binary_id
    field :read, :boolean, default: false
    field :idempotency_key, :string

    embeds_one :metadata, Metadata, on_replace: :update

    belongs_to :user, User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          action: atom(),
          entity_type: atom(),
          entity_id: Ecto.UUID.t() | nil,
          read: boolean(),
          idempotency_key: String.t() | nil,
          metadata: Metadata.t() | nil,
          user_id: Ecto.UUID.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:user_id, :action, :entity_type, :entity_id, :read, :idempotency_key])
    |> validate_required([:user_id, :action, :entity_type])
    |> cast_embed(:metadata, required: true)
    |> unique_constraint(:idempotency_key,
      name: :notifications_user_action_idempotency_key_index
    )
  end
end

defmodule Kaguya.Social.Notification.ActorSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :binary_id
    field :username, :string
    field :avatar_url, :string
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          avatar_url: String.t() | nil
        }

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:id, :username, :avatar_url])
    |> validate_required([:id, :username])
  end
end

defmodule Kaguya.Social.Notification.Metadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :actors_count, :integer
    embeds_many :actor_snapshots, Kaguya.Social.Notification.ActorSnapshot, on_replace: :delete

    field :vn_review_path, :string
    field :vn_image_url, :string
    field :vn_title, :string
    field :text_preview, :string

    field :list_slug, :string
    field :list_name, :string
    field :list_cover_urls, {:array, :string}
    field :list_creator_username, :string

    # For comment notifications, indicates what type of entity the comment belongs to
    field :parent_entity_type, :string

    # For post notifications
    field :post_title, :string
    field :post_slug, :string
    field :post_short_id, :string
    field :post_category_type, :string

    # For report review notifications
    field :report_status, :string
    field :report_entity_type, :string
    field :report_entity_name, :string
    field :report_entity_path, :string
  end

  @type t :: %__MODULE__{
          actors_count: integer() | nil,
          actor_snapshots: [Kaguya.Social.Notification.ActorSnapshot.t()],
          vn_review_path: String.t() | nil,
          vn_image_url: String.t() | nil,
          vn_title: String.t() | nil,
          text_preview: String.t() | nil,
          list_slug: String.t() | nil,
          list_name: String.t() | nil,
          list_cover_urls: [String.t()] | nil,
          list_creator_username: String.t() | nil,
          parent_entity_type: String.t() | nil,
          post_title: String.t() | nil,
          post_slug: String.t() | nil,
          post_short_id: String.t() | nil,
          post_category_type: String.t() | nil,
          report_status: String.t() | nil,
          report_entity_type: String.t() | nil,
          report_entity_name: String.t() | nil,
          report_entity_path: String.t() | nil
        }

  def changeset(meta, attrs) do
    meta
    |> cast(attrs, [
      :actors_count,
      :vn_review_path,
      :vn_image_url,
      :vn_title,
      :text_preview,
      :list_slug,
      :list_name,
      :list_cover_urls,
      :list_creator_username,
      :parent_entity_type,
      :post_title,
      :post_slug,
      :post_short_id,
      :post_category_type,
      :report_status,
      :report_entity_type,
      :report_entity_name,
      :report_entity_path
    ])
    # Not all notifications have a specific actor we want to disclose.
    # Example: moderation removals should not reveal a moderator identity.
    |> cast_embed(:actor_snapshots, required: false)
  end
end

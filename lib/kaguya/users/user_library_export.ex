defmodule Kaguya.Users.UserLibraryExport do
  use Kaguya.Schema

  alias Kaguya.Users.User

  @status_values [:queued, :processing, :completed, :failed]
  @expires_in_days 3

  schema "user_library_exports" do
    field :status, Ecto.Enum, values: @status_values, default: :queued
    field :object_key, :string
    field :row_count, :integer, default: 0
    field :byte_size, :integer
    field :error, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def expires_at(%__MODULE__{inserted_at: inserted_at}) do
    DateTime.add(inserted_at, @expires_in_days * 24 * 3600, :second)
  end

  def changeset(export, attrs) do
    export
    |> cast(attrs, [:id, :user_id, :status, :object_key, :row_count, :byte_size, :error])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, @status_values)
    |> assoc_constraint(:user)
    |> unique_constraint(:user_id, name: :user_library_exports_one_active_per_user)
  end
end

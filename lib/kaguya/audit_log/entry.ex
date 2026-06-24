defmodule Kaguya.AuditLog.Entry do
  use Kaguya.Schema

  alias Kaguya.Users.User

  schema "audit_log" do
    belongs_to :user, User
    field :action, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :details, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :action, :target_type, :target_id, :details])
    |> validate_required([:user_id, :action, :target_type])
    |> assoc_constraint(:user)
  end
end

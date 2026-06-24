defmodule Kaguya.Users.VndbImport do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "vndb_imports" do
    belongs_to :user, User

    field :status, :string, default: "pending"
    field :result, :map
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, [:id, :user_id, :status, :result, :error_message])
    |> validate_required([:id, :user_id])
    |> validate_inclusion(:status, ~w(pending processing completed failed))
    |> unique_constraint(:id,
      name: :vndb_imports_pkey,
      message: "This file has already been submitted for processing."
    )
    |> assoc_constraint(:user)
  end
end

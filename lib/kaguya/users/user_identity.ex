defmodule Kaguya.Users.UserIdentity do
  use Ecto.Schema

  import Ecto.Changeset

  alias Kaguya.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string
    field :email, :string
    field :email_verified, :boolean, default: false
    field :name, :string
    field :avatar_url, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def google_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :email, :email_verified, :name, :avatar_url])
    |> validate_required([:provider, :provider_uid])
    |> validate_inclusion(:provider, ["google"])
    |> validate_format(:email, ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/,
      message: "is not a valid email"
    )
    |> unique_constraint(:provider_uid, name: :user_identities_provider_provider_uid_index)
    |> unique_constraint(:provider, name: :user_identities_user_id_provider_index)
  end
end

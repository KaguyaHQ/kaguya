defmodule Kaguya.Releases.ReleaseExtlink do
  use Kaguya.Schema

  alias Kaguya.Releases.Release

  schema "vn_release_extlinks" do
    belongs_to :vn_release, Release

    field :site, :string
    field :label, :string
    field :url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(extlink, attrs) do
    extlink
    |> cast(attrs, [:vn_release_id, :site, :label, :url])
    |> validate_required([:vn_release_id, :site, :url])
    |> assoc_constraint(:vn_release)
    |> unique_constraint([:vn_release_id, :site, :url])
  end
end

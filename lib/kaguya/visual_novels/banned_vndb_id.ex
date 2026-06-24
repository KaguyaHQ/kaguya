defmodule Kaguya.VisualNovels.BannedVndbId do
  use Ecto.Schema

  @primary_key {:vndb_id, :string, autogenerate: false}
  schema "banned_vndb_ids" do
    field :title, :string
    field :reason, :string
    field :banned_at, :utc_datetime
  end
end

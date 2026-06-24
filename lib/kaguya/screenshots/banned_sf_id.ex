defmodule Kaguya.Screenshots.BannedSfId do
  @moduledoc """
  Image-level blocklist — sf_ids that should never be uploaded even if their
  parent VN isn't banned. Currently seeded from WD14 moderation classifier.
  """
  use Ecto.Schema

  @primary_key {:vndb_sf_id, :string, autogenerate: false}
  schema "banned_sf_ids" do
    field :reason, :string, default: "wd14_moderation"
    field :inserted_at, :utc_datetime
  end
end

defmodule Kaguya.Repo do
  use Ecto.Repo,
    otp_app: :kaguya,
    adapter: Ecto.Adapters.Postgres
end

defmodule Kaguya do
  @moduledoc """
  Kaguya keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
end

# When using Repo.insert/2, do not rely on the returned `:ok` or `{:ok, struct}` tuple
# to determine if the row was actually inserted.
# Always fetch the actual row from the database to be sure irrespective of conflict
# Ecto auto generates id and repo.insert returns that even if no row was inserted by postgres
# Jose says that fields are stale and thus unavoidable getting another time from db

defmodule Kaguya.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type :binary_id
    end
  end
end

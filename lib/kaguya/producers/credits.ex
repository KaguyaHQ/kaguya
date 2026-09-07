defmodule Kaguya.Producers.Credits do
  @moduledoc "Producer selection for release credits."

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Producers.Producer

  def roles,
    do: [
      {"Developer", "developer"},
      {"Publisher", "publisher"},
      {"Developer and publisher", "developer_publisher"}
    ]

  def search(query) when is_binary(query) do
    query = String.trim(query)

    if String.length(query) in 2..100 do
      pattern =
        "%" <>
          (query
           |> String.replace("\\", "\\\\")
           |> String.replace("%", "\\%")
           |> String.replace("_", "\\_")) <> "%"

      from(p in Producer,
        where: is_nil(p.hidden_at) and ilike(p.name, ^pattern),
        order_by: [asc: p.name, asc: p.id],
        limit: 10,
        select: %{id: p.id, name: p.name, vndb_id: p.vndb_id}
      )
      |> Repo.all()
    else
      []
    end
  end
end

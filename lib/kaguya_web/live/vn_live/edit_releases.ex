defmodule KaguyaWeb.VNLive.Edit.ReleaseForm do
  @moduledoc false
  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Producers.Producer
  alias Kaguya.Releases.Release

  def new do
    %{
      "key" => UUIDv7.generate(),
      "id" => nil,
      "title" => "",
      "release_date" => "",
      "producers" => [],
      "base_revision" => 0,
      "revision_id" => nil,
      "original" => nil,
      "locked" => false
    }
  end

  def load(vn_id, user) do
    releases =
      Repo.all(
        from(r in Release,
          where: r.visual_novel_id == ^vn_id and is_nil(r.hidden_at),
          order_by: [asc: r.release_date, asc: r.id]
        )
      )

    refs = Enum.flat_map(releases, &(&1.producers || []))

    ids =
      Enum.flat_map(refs, fn p ->
        case Ecto.UUID.cast(p["producer_id"]) do
          {:ok, id} -> [id]
          _ -> []
        end
      end)

    vndb_ids = Enum.map(refs, & &1["vndb_id"])
    producers = Repo.all(from(p in Producer, where: p.id in ^ids or p.vndb_id in ^vndb_ids))
    by_id = Map.new(producers, &{&1.id, &1})
    by_vndb = producers |> Enum.reject(&is_nil(&1.vndb_id)) |> Map.new(&{&1.vndb_id, &1})
    release_ids = Enum.map(releases, & &1.id)

    revisions =
      Repo.all(
        from(c in Kaguya.Revisions.Change,
          where: c.entity_type == :release and c.entity_id in ^release_ids,
          distinct: c.entity_id,
          order_by: [asc: c.entity_id, desc: c.revision_number],
          select: {c.entity_id, {c.revision_number, c.id}}
        )
      )
      |> Map.new()

    Enum.map(releases, fn r ->
      rows =
        Enum.map(r.producers || [], fn credit ->
          producer = by_id[credit["producer_id"]] || by_vndb[credit["vndb_id"]]

          %{
            "key" => UUIDv7.generate(),
            "name" =>
              if(producer && is_nil(producer.hidden_at),
                do: producer.name,
                else: "Unavailable producer"
              ),
            "role" => role(credit),
            "data" => credit
          }
        end)

      attrs = %{title: r.title, release_date: r.release_date, producers: r.producers || []}

      %{
        "key" => r.id,
        "id" => r.id,
        "title" => r.title,
        "release_date" => if(r.release_date, do: Date.to_iso8601(r.release_date), else: ""),
        "producers" => rows,
        "revision_id" => elem(Map.get(revisions, r.id, {0, nil}), 1),
        "base_revision" => elem(Map.get(revisions, r.id, {0, nil}), 0),
        "original" => attrs,
        "locked" => r.is_locked and not Kaguya.Authorization.can_moderate_db?(user)
      }
    end)
  end

  def normalize(nil, current), do: current

  def normalize(params, current) when is_map(params) do
    Enum.map(current, fn release ->
      attrs = Map.get(params, release["key"], %{})

      if release["locked"] do
        release
      else
        rows =
          Enum.map(release["producers"], fn credit ->
            Map.put(
              credit,
              "role",
              get_in(attrs, ["producers", credit["key"], "role"]) || credit["role"]
            )
          end)

        release
        |> Map.put("title", String.trim(Map.get(attrs, "title", release["title"])))
        |> Map.put(
          "release_date",
          String.trim(Map.get(attrs, "release_date", release["release_date"]))
        )
        |> Map.put("producers", rows)
      end
    end)
  end

  def normalize(_, current), do: current

  def add_producer(release, producer) do
    if Enum.any?(
         release["producers"],
         &(&1["data"]["producer_id"] == producer.id or
             (producer[:vndb_id] && &1["data"]["vndb_id"] == producer[:vndb_id]))
       ) do
      release
    else
      row = %{
        "key" => UUIDv7.generate(),
        "name" => producer.name,
        "role" => "developer",
        "data" => %{
          "producer_id" => producer.id,
          "name" => producer.name,
          "developer" => true,
          "publisher" => false
        }
      }

      Map.update!(release, "producers", &(&1 ++ [row]))
    end
  end

  def dirty?(releases),
    do: Enum.any?(releases, &(&1["original"] == nil or attrs(&1) != &1["original"]))

  def edits(releases) do
    Enum.flat_map(releases, fn r ->
      current = attrs(r)

      changes =
        if r["original"],
          do: Map.new(Enum.reject(current, fn {k, v} -> r["original"][k] == v end)),
          else: current

      if changes == %{},
        do: [],
        else: [%{id: r["id"], base_revision: r["base_revision"], attrs: changes}]
    end)
  end

  defp attrs(r) do
    %{
      title: r["title"],
      release_date: date(r["release_date"]),
      producers: Enum.map(r["producers"], &credit_attrs/1)
    }
  end

  defp credit_attrs(row) do
    if role(row["data"]) == row["role"] do
      row["data"]
    else
      row["data"]
      |> Map.put("developer", row["role"] in ["developer", "developer_publisher"])
      |> Map.put("publisher", row["role"] in ["publisher", "developer_publisher"])
      |> then(fn data ->
        if row["role"] in ["developer", "publisher", "developer_publisher"],
          do: Map.delete(data, "invalid_role"),
          else: Map.put(data, "invalid_role", true)
      end)
    end
  end

  defp role(p) do
    case {p["developer"] == true, p["publisher"] == true} do
      {true, true} -> "developer_publisher"
      {true, false} -> "developer"
      _ -> "publisher"
    end
  end

  defp date(""), do: nil

  defp date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> value
    end
  end
end

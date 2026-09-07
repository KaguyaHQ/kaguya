defmodule Kaguya.Releases.Credits do
  @moduledoc "Derives VN credits from the releases stored in Kaguya, including user edits."
  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Releases.Release
  alias Kaguya.Producers.{Producer, VNProducer}

  def recompute(vn_ids) do
    vn_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(500)
    |> Enum.each(&recompute_batch/1)

    :ok
  end

  defp recompute_batch(ids) do
    {:ok, _} =
      Repo.transaction(fn ->
        # Match contribution locking, in deterministic order. Locks last through
        # any enclosing revision transaction.
        Repo.query!(
          "SELECT pg_advisory_xact_lock(hashtext('visual_novel:' || id)) FROM unnest($1::text[]) AS ids(id) ORDER BY id",
          [ids]
        )

        releases =
          Repo.all(
            from(r in Release,
              where: r.visual_novel_id in ^ids and is_nil(r.hidden_at),
              select: {r.visual_novel_id, r.producers, r.release_date}
            )
          )

        refs = Enum.flat_map(releases, fn {_, credits, _} -> credits || [] end)

        producer_ids =
          Enum.flat_map(refs, fn p ->
            case Ecto.UUID.cast(p["producer_id"] || p[:producer_id]) do
              {:ok, id} -> [id]
              _ -> []
            end
          end)

        vndb_ids = Enum.map(refs, & &1["vndb_id"])

        producers =
          Repo.all(
            from(p in Producer,
              where: p.id in ^producer_ids or p.vndb_id in ^vndb_ids,
              select: {p.id, p.vndb_id}
            )
          )

        by_id = MapSet.new(producers, &elem(&1, 0))

        by_vndb =
          producers
          |> Enum.reject(fn {_, vndb} -> is_nil(vndb) end)
          |> Map.new(fn {id, vndb} -> {vndb, id} end)

        credits =
          Enum.reduce(releases, %{}, fn {vn_id, credits, date}, acc ->
            Enum.reduce(credits || [], acc, fn p, acc ->
              id = p["producer_id"] || p[:producer_id] || by_vndb[p["vndb_id"]]

              if MapSet.member?(by_id, id) do
                dev = (p["developer"] || p[:developer]) == true
                pub = (p["publisher"] || p[:publisher]) == true

                Map.update(acc, {vn_id, id}, {dev, pub, date}, fn {old_dev, old_pub, old_date} ->
                  {dev or old_dev, pub or old_pub, earliest(date, old_date)}
                end)
              else
                acc
              end
            end)
          end)

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        rows =
          Enum.map(credits, fn {{vn_id, producer_id}, {dev, pub, date}} ->
            role =
              cond do
                dev and pub -> "developer_publisher"
                dev -> "developer"
                true -> "publisher"
              end

            %{
              visual_novel_id: vn_id,
              producer_id: producer_id,
              role: role,
              earliest_release_date: date,
              inserted_at: now,
              updated_at: now
            }
          end)

        Repo.delete_all(from(p in VNProducer, where: p.visual_novel_id in ^ids))
        rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all(VNProducer, &1))
      end)

    :ok
  end

  defp earliest(nil, date), do: date
  defp earliest(date, nil), do: date

  defp earliest(first, second),
    do: if(Date.compare(first, second) == :lt, do: first, else: second)
end

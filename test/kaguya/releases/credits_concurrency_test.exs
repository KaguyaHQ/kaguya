defmodule Kaguya.Releases.CreditsConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.{Repo, Revisions}
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.Release
  alias Kaguya.VisualNovels.{VisualNovel, Contributions}

  setup do
    # Separate connections must see committed fixtures to exercise real locks.
    # Use unique IDs and explicitly remove only these fixtures after each test.
    vn_id = UUIDv7.generate()
    user_id = UUIDv7.generate()
    release_ids = [UUIDv7.generate(), UUIDv7.generate()]
    producer_ids = [UUIDv7.generate(), UUIDv7.generate()]

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        entities = [vn_id | release_ids]
        Repo.delete_all(from(c in Kaguya.Revisions.Change, where: c.entity_id in ^entities))
        Repo.delete_all(from(v in VisualNovel, where: v.id == ^vn_id))
        Repo.delete_all(from(p in Producer, where: p.id in ^producer_ids))
        Repo.delete_all(from(u in Kaguya.Users.User, where: u.id == ^user_id))
      end)
    end)

    fixtures =
      Sandbox.unboxed_run(Repo, fn ->
        user = Kaguya.Test.UserFixtures.insert_user!(id: user_id)

        vn =
          Repo.insert!(%VisualNovel{
            id: vn_id,
            title: "Concurrent credits",
            slug: "concurrent-#{vn_id}"
          })

        releases =
          Enum.map(
            release_ids,
            &Repo.insert!(%Release{id: &1, visual_novel_id: vn.id, title: "Edition #{&1}"})
          )

        producers =
          Enum.map(
            producer_ids,
            &Repo.insert!(%Producer{id: &1, name: "Studio #{&1}", slug: "studio-#{&1}"})
          )

        %{user: user, vn: vn, releases: releases, producers: producers}
      end)

    supervisor = start_supervised!({Task.Supervisor, []})

    blocker =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    Map.merge(fixtures, %{supervisor: supervisor, blocker: blocker})
  end

  test "simultaneous edits to different releases retain both derived credits", ctx do
    [first, second] = ctx.releases
    [a, b] = ctx.producers
    results = race(ctx, [edit(first, a), edit(second, b)])
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.get!(Release, first.id).producers == [credit(a)]
      assert Repo.get!(Release, second.id).producers == [credit(b)]
      assert derived_ids(ctx.vn.id) == MapSet.new([a.id, b.id])
      assert Revisions.latest_revision_number(:release, first.id) == 2
      assert Revisions.latest_revision_number(:release, second.id) == 2
    end)
  end

  test "simultaneous edits to the same release reject the stale writer", ctx do
    [release | _] = ctx.releases
    [a, b] = ctx.producers
    results = race(ctx, [edit(release, a), edit(release, b)])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :edit_conflict})) == 1

    Sandbox.unboxed_run(Repo, fn ->
      [winner] = Repo.get!(Release, release.id).producers
      assert winner["producer_id"] in [a.id, b.id]
      assert derived_ids(ctx.vn.id) == MapSet.new([winner["producer_id"]])
      assert Revisions.latest_revision_number(:release, release.id) == 2
      assert Revisions.latest_revision_number(:visual_novel, ctx.vn.id) == 0
    end)
  end

  defp race(ctx, edits) do
    lock_key = "visual_novel:#{ctx.vn.id}"
    Postgrex.query!(ctx.blocker, "SELECT pg_advisory_lock(hashtext($1))", [lock_key])
    %{rows: [[blocker_pid]]} = Postgrex.query!(ctx.blocker, "SELECT pg_backend_pid()", [])
    parent = self()

    tasks =
      Enum.map(edits, fn edit ->
        Task.Supervisor.async_nolink(ctx.supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:writer_ready, self(), pid})

            Contributions.update(
              ctx.vn.id,
              %{},
              [edit],
              "Concurrent producer correction",
              ctx.user,
              0
            )
          end)
        end)
      end)

    try do
      pids =
        Enum.map(tasks, fn task ->
          writer = task.pid
          assert_receive {:writer_ready, ^writer, pid}, 5_000
          pid
        end)

      assert length(Enum.uniq(pids)) == 2
      await_blocked(ctx.blocker, blocker_pid, pids, System.monotonic_time(:millisecond) + 5_000)
      Postgrex.query!(ctx.blocker, "SELECT pg_advisory_unlock(hashtext($1))", [lock_key])
      Enum.map(tasks, &Task.await(&1, 10_000))
    after
      Postgrex.query!(ctx.blocker, "SELECT pg_advisory_unlock(hashtext($1))", [lock_key])
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  # Observe the database's actual wait graph, rather than sleeping or relying
  # on task start order. A missing parent lock makes this fail before release.
  defp await_blocked(conn, blocker, pids, deadline) do
    %{rows: [[count]]} =
      Postgrex.query!(
        conn,
        "SELECT count(*) FROM unnest($1::integer[]) AS workers(pid) WHERE $2 = ANY(pg_blocking_pids(pid))",
        [pids, blocker]
      )

    if count != length(pids) do
      assert System.monotonic_time(:millisecond) < deadline,
             "writers never both blocked on the VN lock"

      await_blocked(conn, blocker, pids, deadline)
    end
  end

  defp edit(release, producer),
    do: %{id: release.id, base_revision: 0, attrs: %{producers: [credit(producer)]}}

  defp credit(p),
    do: %{"producer_id" => p.id, "name" => p.name, "developer" => true, "publisher" => false}

  defp derived_ids(vn_id),
    do:
      Repo.all(from(p in VNProducer, where: p.visual_novel_id == ^vn_id, select: p.producer_id))
      |> MapSet.new()
end

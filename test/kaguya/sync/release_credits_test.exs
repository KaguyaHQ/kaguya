defmodule Kaguya.Sync.ReleaseCreditsTest do
  use KaguyaWeb.ConnCase, async: false
  import Ecto.Query
  alias Kaguya.{Repo, Revisions}
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.Release
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Sync.DumpSync.Releases, as: ReleaseSync

  test "a later dump preserves corrected credits and includes newly imported and local releases" do
    # A real PostgreSQL connection with a tiny, connection-local VNDB dump.
    # The destination uses the usual SQL sandbox; neither database needs a migration.
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    create_dump_tables(source)
    user = Kaguya.Test.UserFixtures.insert_user!()

    vn =
      Repo.insert!(%VisualNovel{
        title: "Sync credits VN",
        slug: "sync-credits-vn",
        vndb_id: "v90000001"
      })

    [old, corrected, imported, local] =
      for n <- 1..4 do
        Repo.insert!(%Producer{
          name: "Sync studio #{n}",
          slug: "sync-studio-#{n}",
          vndb_id: "p9000000#{n}"
        })
      end

    for producer <- [old, corrected, imported, local] do
      Postgrex.query!(source, "INSERT INTO producers VALUES ($1, $2, NULL)", [
        producer.vndb_id,
        producer.name
      ])
    end

    Postgrex.query!(source, "INSERT INTO vn_titles VALUES ($1, $2, NULL)", [vn.vndb_id, vn.title])
    add_dump_release(source, "r90000001", vn.vndb_id, old.vndb_id)

    ctx = %{
      vndb: source,
      dry_run: false,
      vn_mapping: %{vn.vndb_id => vn.id},
      producer_mapping: Map.new([old, corrected, imported, local], &{&1.vndb_id, &1.id}),
      target_vndb_ids: [vn.vndb_id]
    }

    assert {:ok, _} = ReleaseSync.run(ctx)
    release = Repo.get_by!(Release, vndb_id: "r90000001", visual_novel_id: vn.id)
    assert credit_ids(vn) == MapSet.new([old.id])

    assert {:ok, correction} =
             Revisions.submit_edit(
               :release,
               release.id,
               %{producers: [credit(corrected)]},
               "Correct the developer",
               user, base_revision: 1)

    # No VN revision protects this entry: this specifically exercises release protection.
    assert Revisions.latest_revision_number(:visual_novel, vn.id) == 0

    assert {:ok, _} =
             Revisions.create_entity(
               :release,
               %{visual_novel_id: vn.id, title: "Local edition", producers: [credit(local)]},
               "Add local edition",
               user
             )

    add_dump_release(source, "r90000002", vn.vndb_id, imported.vndb_id)

    assert {:ok, _} = ReleaseSync.run(ctx)
    assert Repo.get!(Release, release.id).producers == [credit(corrected)]
    assert Repo.get_by!(Release, vndb_id: "r90000002", visual_novel_id: vn.id)
    assert credit_ids(vn) == MapSet.new([corrected.id, imported.id, local.id])
    assert Revisions.latest_revision_number(:release, release.id) == correction.revision_number
    # Re-running the same dump must not restore the old credit or duplicate revisions.
    assert {:ok, _} = ReleaseSync.run(ctx)
    assert credit_ids(vn) == MapSet.new([corrected.id, imported.id, local.id])
    assert Revisions.latest_revision_number(:release, release.id) == correction.revision_number
  end

  defp credit_ids(vn),
    do:
      Repo.all(from(p in VNProducer, where: p.visual_novel_id == ^vn.id, select: p.producer_id))
      |> MapSet.new()

  defp credit(p),
    do: %{"producer_id" => p.id, "name" => p.name, "developer" => true, "publisher" => false}

  defp create_dump_tables(source) do
    for definition <- [
          "engines (id text, name text)",
          "producers (id text, name text, latin text)",
          "vn_titles (id text, title text, latin text)",
          "releases_vn (id text, vid text, rtype text)",
          "releases_supersedes (id text, rid text)",
          "releases (id text, olang text, released integer, voiced integer, minage integer, has_ero boolean, patch boolean, freeware boolean, uncensored boolean, official boolean, engine text, notes text, reso_x integer, reso_y integer)",
          "releases_titles (id text, lang text, mtl boolean, title text, latin text)",
          "releases_platforms (id text, platform text)",
          "releases_extlinks (id text, link integer)",
          "extlinks (id integer, site text, value text)",
          "releases_media (id text, medium text, qty integer)",
          "releases_producers (id text, pid text, developer boolean, publisher boolean)"
        ] do
      Postgrex.query!(source, "CREATE TEMP TABLE " <> definition, [])
    end
  end

  defp add_dump_release(source, id, vn_id, producer_id) do
    Postgrex.query!(
      source,
      "INSERT INTO releases VALUES ($1, 'en', 20200101, 0, 0, false, false, false, false, true, NULL, '', 0, 0)",
      [id]
    )

    Postgrex.query!(source, "INSERT INTO releases_vn VALUES ($1, $2, 'complete')", [id, vn_id])

    Postgrex.query!(
      source,
      "INSERT INTO releases_titles VALUES ($1, 'en', false, 'Original edition', NULL)",
      [id]
    )

    Postgrex.query!(source, "INSERT INTO releases_producers VALUES ($1, $2, true, false)", [
      id,
      producer_id
    ])
  end
end

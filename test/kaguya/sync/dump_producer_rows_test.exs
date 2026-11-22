defmodule Kaguya.Sync.DumpProducerRowsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Producers.{Producer, ProducerExternalLink}
  alias Kaguya.Revisions.Change
  alias Kaguya.Sync.DumpSync.{Producers, Report}
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    for definition <- [
          "producers (id text, name text, latin text, type text, lang text, description text)",
          "releases_producers (id text, pid text)",
          "releases_vn (id text, vid text)",
          "producers_extlinks (id text, link integer)",
          "extlinks (id integer, site text, value text)",
          "wikidata (id integer, enwiki text, jawiki text, twitter text[])"
        ] do
      Postgrex.query!(source, "CREATE TEMP TABLE " <> definition, [])
    end

    Report.start()
    on_exit(&Report.stop/0)
    {:ok, source: source}
  end

  test "producer batches preserve curated fields and links while backfilling missing sites", %{
    source: source
  } do
    vn =
      Repo.insert!(%VisualNovel{title: "Producer VN", slug: "producer-vn", vndb_id: "v89970001"})

    protected =
      Repo.insert!(%Producer{
        name: "Curated studio",
        slug: "curated-studio",
        vndb_id: "p89970001"
      })

    existing =
      Repo.insert!(%Producer{
        name: "Old studio name",
        slug: "existing-studio",
        vndb_id: "p89970002"
      })

    Repo.insert!(%Change{
      entity_type: :producer,
      entity_id: protected.id,
      revision_number: 1,
      action: :edit,
      source: :user,
      summary: "Protect studio name"
    })

    Repo.insert!(%ProducerExternalLink{
      producer_id: protected.id,
      site: "twitter",
      value: "curated_handle"
    })

    for {id, name} <- [
          {protected.vndb_id, "Dump studio name"},
          {existing.vndb_id, "Updated studio name"},
          {"p89970003", "New studio"},
          {"p89970004", "Unmapped studio"}
        ] do
      Postgrex.query!(source, "INSERT INTO producers VALUES ($1, $2, NULL, 'co', 'en', '')", [
        id,
        name
      ])
    end

    for id <- [protected.vndb_id, existing.vndb_id, "p89970003"] do
      Postgrex.query!(source, "INSERT INTO releases_producers VALUES ('r1', $1)", [id])
    end

    Postgrex.query!(source, "INSERT INTO releases_vn VALUES ('r1', $1)", [vn.vndb_id])

    Postgrex.query!(
      source,
      "INSERT INTO extlinks VALUES (1, 'twitter', 'dump_handle'), (2, 'wp', 'Manual_article'), (3, 'wikidata', '123'), (4, 'twitter', 'unmapped')",
      []
    )

    Postgrex.query!(
      source,
      "INSERT INTO producers_extlinks VALUES ($1, 1), ($1, 1), ($1, 2), ($1, 3), ('p89970004', 4)",
      [protected.vndb_id]
    )

    Postgrex.query!(
      source,
      "INSERT INTO wikidata VALUES (123, 'Cached_article', 'Japanese_article', ARRAY['cached_handle'])",
      []
    )

    ctx = %{vndb: source, dry_run: false, vn_mapping: %{vn.vndb_id => vn.id}}
    assert {:ok, _} = Producers.run(ctx)
    assert Repo.get!(Producer, protected.id).name == "Curated studio"

    assert %{name: "Updated studio name", slug: "existing-studio"} =
             Repo.get!(Producer, existing.id)

    assert %{slug: "new-studio"} = Repo.get_by!(Producer, vndb_id: "p89970003")
    refute Repo.get_by(Producer, vndb_id: "p89970004")

    links = fn ->
      Repo.all(
        from(link in ProducerExternalLink,
          where: link.producer_id == ^protected.id,
          order_by: link.site,
          select: {link.site, link.value}
        )
      )
    end

    expected_links = [
      {"enwiki", "Manual_article"},
      {"jawiki", "Japanese_article"},
      {"twitter", "curated_handle"},
      {"wikidata", "123"}
    ]

    assert links.() == expected_links
    assert [{:producers, %{new: 1, updated: 2}}] = :ets.lookup(:dump_sync_report, :producers)
    assert {:ok, _} = Producers.run(ctx)
    assert links.() == expected_links
    assert Repo.aggregate(Producer, :count) == 3
    assert [{:producers, %{new: 0, updated: 3}}] = :ets.lookup(:dump_sync_report, :producers)
  end

  test "a fully skipped producer batch still advances to the next batch", %{source: source} do
    vn =
      Repo.insert!(%VisualNovel{
        title: "Later batch VN",
        slug: "later-batch-vn",
        vndb_id: "v89970002"
      })

    Postgrex.query!(
      source,
      """
      INSERT INTO producers
      SELECT 'p' || lpad(n::text, 5, '0'), 'Batch Studio ' || n, NULL, 'co', 'en', ''
      FROM generate_series(1, 5001) AS n
      """,
      []
    )

    Postgrex.query!(source, "INSERT INTO releases_producers VALUES ('r1', 'p05001')", [])
    Postgrex.query!(source, "INSERT INTO releases_vn VALUES ('r1', $1)", [vn.vndb_id])

    assert {:ok, 1} =
             Producers.run(%{vndb: source, dry_run: false, vn_mapping: %{vn.vndb_id => vn.id}})

    assert Repo.aggregate(Producer, :count) == 1

    assert %{name: "Batch Studio 5001", slug: "batch-studio-5001"} =
             Repo.get_by!(Producer, vndb_id: "p05001")

    assert [{:producers, %{new: 1, updated: 0}}] = :ets.lookup(:dump_sync_report, :producers)
  end
end

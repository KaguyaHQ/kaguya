defmodule Kaguya.Sync.DumpVnRowsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Sync.DumpSync.{Report, VNs}
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle, VnExternalLink}

  setup do
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    for definition <- [
          "vn (id text, olang text, c_image text, image text, c_average integer, c_votecount integer, description text, devstatus integer, length integer, c_length integer, alias text)",
          "vn_titles (id text, lang text, official boolean, title text, latin text)",
          "images (id text, c_sexual_avg integer, c_violence_avg integer, c_votecount integer)",
          "tags_vn (vid text, tag text, ignore boolean, vote integer)",
          "releases_vn (id text, vid text)",
          "releases (id text, released integer, minage integer, has_ero boolean)",
          "vn_extlinks (id text, link integer)",
          "extlinks (id integer, site text, value text)",
          "wikidata (id integer, enwiki text, jawiki text)"
        ] do
      Postgrex.query!(source, "CREATE TEMP TABLE " <> definition, [])
    end

    Report.start()
    on_exit(&Report.stop/0)
    {:ok, source: source}
  end

  for mode <- [:full, :targeted] do
    @mode mode
    test "#{mode} import protects curated content and refreshes references", %{source: source} do
      protected =
        Repo.insert!(%VisualNovel{
          title: "Curated",
          slug: "curated-vn",
          vndb_id: "v89950001",
          vndb_vote_count: 1
        })

      Repo.insert!(%Change{
        entity_type: :visual_novel,
        entity_id: protected.id,
        revision_number: 1,
        action: :edit,
        source: :user,
        summary: "Protect VN"
      })

      Repo.insert!(%VNTitle{
        visual_novel_id: protected.id,
        lang: "en",
        title: "Curated title",
        official: true
      })

      for id <- ["v89950001", "v89950002", "v89950003"] do
        Postgrex.query!(
          source,
          "INSERT INTO vn (id, olang, c_average, c_votecount, description) VALUES ($1, 'en', 750, 42, 'Dump description')",
          [id]
        )

        Postgrex.query!(source, "INSERT INTO vn_titles VALUES ($1, 'en', true, $2, NULL)", [
          id,
          "Dump " <> id
        ])
      end

      Postgrex.query!(
        source,
        "INSERT INTO releases_vn VALUES ('r1', 'v89950002'), ('r2', 'v89950002')",
        []
      )

      Postgrex.query!(
        source,
        "INSERT INTO releases VALUES ('r1', 20200101, 18, true), ('r2', 20210101, 12, false)",
        []
      )

      Postgrex.query!(
        source,
        "INSERT INTO extlinks VALUES (1, 'wp', 'Manual'), (2, 'wikidata', '42')",
        []
      )

      Postgrex.query!(
        source,
        "INSERT INTO vn_extlinks VALUES ('v89950002', 1), ('v89950002', 2), ('v-unmapped', 1)",
        []
      )

      Postgrex.query!(source, "INSERT INTO wikidata VALUES (42, 'Cached', 'Japanese')", [])

      ids = ["v89950001", "v89950002", "v89950003"]

      ctx = %{
        vndb: source,
        dry_run: false,
        vn_mapping: %{protected.vndb_id => protected.id},
        banned_ids: MapSet.new(["v89950003"]),
        category_map: %{}
      }

      ctx = if @mode == :targeted, do: Map.put(ctx, :target_vndb_ids, ids), else: ctx
      assert {:ok, _} = VNs.run(ctx)
      assert %{title: "Curated", vndb_vote_count: 42} = Repo.get!(VisualNovel, protected.id)

      assert Repo.get_by!(VNTitle, visual_novel_id: protected.id, lang: "en").title ==
               "Curated title"

      new_vn = Repo.get_by!(VisualNovel, vndb_id: "v89950002")
      assert %{title: "Dump v89950002", has_ero: true} = new_vn
      refute Repo.get_by(VisualNovel, vndb_id: "v89950003")

      assert Repo.get_by!(VNTitle, visual_novel_id: new_vn.id, lang: "en").title ==
               "Dump v89950002"

      if @mode == :full do
        links =
          Repo.all(
            from l in VnExternalLink, where: l.vn_id == ^new_vn.id, select: {l.site, l.value}
          )
          |> MapSet.new()

        assert links ==
                 MapSet.new([{"enwiki", "Manual"}, {"jawiki", "Japanese"}, {"wikidata", "42"}])
      end
    end
  end
end

defmodule Kaguya.Sync.DumpRelationRowsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Sync.DumpSync.{Relations, Report}
  alias Kaguya.VisualNovels.{Relation, VisualNovel}

  setup do
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    Postgrex.query!(
      source,
      "CREATE TEMP TABLE vn_relations (id text, vid text, relation text, official boolean)",
      []
    )

    Report.start()
    on_exit(&Report.stop/0)
    {:ok, source: source}
  end

  for mode <- [:full, :targeted] do
    @mode mode
    test "#{mode} relation import updates known pairs and preserves protected sources", %{
      source: source
    } do
      [first, protected, third] =
        for n <- 1..3 do
          Repo.insert!(%VisualNovel{
            title: "Relation VN #{n}",
            slug: "relation-vn-#{n}",
            vndb_id: "v8998000#{n}"
          })
        end

      Repo.insert!(%Change{
        entity_type: :visual_novel,
        entity_id: protected.id,
        revision_number: 1,
        action: :edit,
        source: :user,
        summary: "Protect curated relations"
      })

      Repo.insert!(%Relation{
        visual_novel_id: first.id,
        related_vn_id: protected.id,
        relation_type: "side_story"
      })

      Repo.insert!(%Relation{
        visual_novel_id: protected.id,
        related_vn_id: first.id,
        relation_type: "alternative"
      })

      for {id, vid, type, official} <- [
            {first.vndb_id, protected.vndb_id, "seq", false},
            {first.vndb_id, third.vndb_id, "side", true},
            {protected.vndb_id, first.vndb_id, "preq", true},
            {first.vndb_id, "v-unmapped", "seq", true},
            {"v-unmapped", first.vndb_id, "preq", true}
          ] do
        Postgrex.query!(source, "INSERT INTO vn_relations VALUES ($1, $2, $3, $4)", [
          id,
          vid,
          type,
          official
        ])
      end

      ctx = %{
        vndb: source,
        dry_run: false,
        vn_mapping: Map.new([first, protected, third], &{&1.vndb_id, &1.id})
      }

      ctx = if @mode == :targeted, do: Map.put(ctx, :target_vndb_ids, [first.vndb_id]), else: ctx

      assert {:ok, 2} = Relations.run(ctx)

      assert MapSet.new(
               Repo.all(
                 from(r in Relation,
                   select: {r.visual_novel_id, r.related_vn_id, r.relation_type, r.is_official}
                 )
               )
             ) ==
               MapSet.new([
                 {first.id, protected.id, "sequel", false},
                 {first.id, third.id, "side_story", true},
                 {protected.id, first.id, "alternative", true}
               ])

      assert [{:relations, %{new: 1, updated: 1}}] = :ets.lookup(:dump_sync_report, :relations)
      assert {:ok, 2} = Relations.run(ctx)
      assert Repo.aggregate(Relation, :count) == 3
      assert [{:relations, %{new: 0, updated: 2}}] = :ets.lookup(:dump_sync_report, :relations)
    end
  end
end

defmodule Kaguya.Sync.DumpCharacterRowsTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Characters.{Character, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Sync.DumpSync.{Characters, Report}
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    for definition <- [
          "chars (id text, image text, sex text, gender text, spoil_sex text, spoil_gender text, bloodt text, height integer, weight integer, birthday integer, s_bust integer, s_waist integer, s_hip integer, cup_size text, age integer, description text)",
          "chars_names (id text, lang text, name text, latin text)",
          "chars_vns (id text, vid text, role text, spoil integer)",
          "images (id text, c_sexual_avg integer, c_violence_avg integer, c_votecount integer)"
        ] do
      Postgrex.query!(source, "CREATE TEMP TABLE " <> definition, [])
    end

    Report.start()
    on_exit(&Report.stop/0)
    {:ok, source: source}
  end

  for mode <- [:full, :targeted] do
    @mode mode
    test "#{mode} import keeps highest role and preserves edited characters", %{source: source} do
      vn =
        Repo.insert!(%VisualNovel{
          title: "Character VN",
          slug: "dump-character-vn",
          vndb_id: "v89960001"
        })

      chars =
        for n <- 1..4 do
          Repo.insert!(%Character{
            name: "Curated #{n}",
            slug: "dump-character-#{n}",
            vndb_id: "c8996000#{n}"
          })
        end

      [first, second, third, protected] = chars

      Repo.insert!(%Change{
        entity_type: :character,
        entity_id: protected.id,
        revision_number: 1,
        action: :edit,
        source: :user,
        summary: "Protect character"
      })

      Repo.insert!(%VNCharacter{
        character_id: protected.id,
        visual_novel_id: vn.id,
        role: :side,
        spoiler_level: 2
      })

      for char <- chars do
        Postgrex.query!(source, "INSERT INTO chars (id) VALUES ($1)", [char.vndb_id])

        Postgrex.query!(source, "INSERT INTO chars_names VALUES ($1, 'en', 'Dump name', NULL)", [
          char.vndb_id
        ])
      end

      for {char, role, spoil} <- [
            {first, "appears", 0},
            {first, "side", 0},
            {first, "primary", 1},
            {first, "main", 2},
            {second, "appears", 0},
            {second, "side", 0},
            {second, "primary", 1},
            {third, "appears", 0},
            {third, "side", 2},
            {protected, "main", 0}
          ] do
        Postgrex.query!(source, "INSERT INTO chars_vns VALUES ($1, $2, $3, $4)", [
          char.vndb_id,
          vn.vndb_id,
          role,
          spoil
        ])
      end

      Postgrex.query!(source, "INSERT INTO chars_vns VALUES ($1, 'v-unmapped', 'main', 0)", [
        first.vndb_id
      ])

      ctx = %{vndb: source, dry_run: false, vn_mapping: %{vn.vndb_id => vn.id}}
      ctx = if @mode == :targeted, do: Map.put(ctx, :target_vndb_ids, [vn.vndb_id]), else: ctx
      assert {:ok, _} = Characters.run(ctx)

      roles =
        Repo.all(
          from j in VNCharacter,
            select: {j.character_id, j.visual_novel_id, j.role, j.spoiler_level}
        )
        |> MapSet.new()

      assert roles ==
               MapSet.new([
                 {first.id, vn.id, :main, 2},
                 {second.id, vn.id, :primary, 1},
                 {third.id, vn.id, :side, 2},
                 {protected.id, vn.id, :side, 2}
               ])

      assert Repo.get!(Character, protected.id).name == "Curated 4"
      assert {:ok, _} = Characters.run(ctx)
      assert Repo.aggregate(VNCharacter, :count) == 4
    end
  end
end

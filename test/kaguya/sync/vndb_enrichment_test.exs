defmodule Kaguya.Sync.VndbEnrichmentTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Characters.VNCharacter
  alias Kaguya.Sync.VndbEnrichment
  alias Kaguya.VisualNovels.{Relation, VisualNovel}
  alias Kaguya.Releases.ReleaseExtlink

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "character links ignore unknown VNs and update an existing link" do
    vn =
      Repo.insert!(%VisualNovel{
        title: "Character VN",
        slug: "character-enrichment",
        vndb_id: "v89990006"
      })

    char = %{
      "id" => "c89990001",
      "name" => "Enrichment Character",
      "vns" => [
        %{"id" => vn.vndb_id, "role" => "main", "spoiler" => 1},
        %{"id" => "v89990007", "role" => "side"}
      ]
    }

    assert {1, ["c89990001"]} = VndbEnrichment.import_characters([char], %{vn.vndb_id => vn.id})
    assert [%VNCharacter{visual_novel_id: vn_id, spoiler_level: 1}] = Repo.all(VNCharacter)
    assert vn_id == vn.id

    updated = put_in(char, ["vns"], [%{"id" => vn.vndb_id, "role" => "side", "spoiler" => 2}])

    assert {1, ["c89990001"]} =
             VndbEnrichment.import_characters([updated], %{vn.vndb_id => vn.id})

    assert [%VNCharacter{spoiler_level: 2}] = Repo.all(VNCharacter)
  end

  test "relations resolve known database VNs and ignore missing references" do
    source =
      Repo.insert!(%VisualNovel{title: "Source", slug: "source-enrichment", vndb_id: "v89990001"})

    related =
      Repo.insert!(%VisualNovel{
        title: "Related",
        slug: "related-enrichment",
        vndb_id: "v89990002"
      })

    data = [
      %{
        "id" => source.vndb_id,
        "relations" => [
          %{"id" => related.vndb_id, "relation" => "seq", "relation_official" => true},
          %{"id" => "v89990003", "relation" => "seq"}
        ]
      },
      %{"id" => "v89990004", "relations" => nil}
    ]

    assert 1 == VndbEnrichment.import_relations(data, %{source.vndb_id => source.id})

    assert [%Relation{visual_novel_id: source_id, related_vn_id: related_id, is_official: true}] =
             Repo.all(Relation)

    assert source_id == source.id
    assert related_id == related.id
  end

  test "release links skip incomplete entries and deduplicate synthetic SteamDB links" do
    vn =
      Repo.insert!(%VisualNovel{
        title: "Release VN",
        slug: "release-enrichment",
        vndb_id: "v89990005"
      })

    release = %{
      "id" => "r89990001",
      "title" => "Release VN",
      "vns" => [%{"id" => vn.vndb_id}],
      "extlinks" => [
        %{"name" => "steam", "url" => "https://store.steampowered.com/app/12345/game"},
        %{"name" => "steam", "url" => "https://store.steampowered.com/app/12345/game"},
        %{"name" => "incomplete"},
        %{"name" => "steam", "url" => "https://store.steampowered.com/no-app"},
        %{"label" => "website", "url" => "https://example.com"},
        %{"url" => "https://example.com/no-site"}
      ]
    }

    VndbEnrichment.import_releases([release], [vn.vndb_id], %{vn.vndb_id => vn.id})

    assert Enum.sort(Enum.map(Repo.all(ReleaseExtlink), &{&1.site, &1.url})) == [
             {"steam", "https://store.steampowered.com/app/12345/game"},
             {"steam", "https://store.steampowered.com/no-app"},
             {"steamdb", "https://steamdb.info/app/12345"},
             {"website", "https://example.com"}
           ]
  end
end

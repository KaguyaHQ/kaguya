# VNDB API Import — Integration Script
#
# Standalone script (not an ExUnit test). Runs against dev DB
# (needs initial dump data for tags, producers, characters).
# Cleans up all imported test data on completion (success or failure).
#
# Run:  PORT=4099 mix run test/kaguya/sync/vndb_import.exs

import Ecto.Query

alias Kaguya.Repo
alias Kaguya.Sync.VndbApiImport
alias Kaguya.VisualNovels.{VisualNovel, VNTag, Relation}
alias Kaguya.Characters.{Character, VNCharacter}
alias Kaguya.Producers.{Producer, VNProducer}

# ── Test Infrastructure ────────────────────────────────────────────────────

defmodule ImportTest do
  @all_test_vndb_ids [
    "v61344",
    "v61349",
    "v61386",
    "v61532",
    "v61380",
    "v61378",
    "v61371",
    "v62097",
    "v61602"
  ]

  @dump_cutoff ~U[2026-02-01 00:00:00Z]

  def run do
    preflight_check!()

    cleanup()
    start = System.monotonic_time(:millisecond)
    {passed, failed, errors} = run_all_tests()
    elapsed = System.monotonic_time(:millisecond) - start
    cleanup()

    IO.puts("\n#{"=" |> String.duplicate(60)}")

    if errors != [] do
      IO.puts("ERRORS:")

      for {name, err} <- Enum.reverse(errors) do
        IO.puts("  #{name}: #{err}")
      end

      IO.puts("")
    end

    total = passed + failed
    color = if failed == 0, do: "\e[32m", else: "\e[31m"

    IO.puts(
      "#{color}#{passed}/#{total} passed, #{failed} failed\e[0m (#{Float.round(elapsed / 1000, 1)}s)"
    )
  end

  def preflight_check! do
    import Ecto.Query
    alias Kaguya.VisualNovels.VisualNovel

    existing =
      Kaguya.Repo.all(
        from v in VisualNovel,
          where: v.vndb_id in @all_test_vndb_ids,
          select: v.vndb_id
      )

    if existing != [] do
      IO.puts("\e[31mABORT: The following test VN IDs already exist in the database:\e[0m")
      for id <- Enum.sort(existing), do: IO.puts("  - #{id}")
      IO.puts("\nThese VNs would be deleted during cleanup.")
      IO.puts("Update @all_test_vndb_ids with VN IDs that are NOT in the DB (post-dump IDs).")
      System.halt(1)
    end
  end

  def cleanup do
    import Ecto.Query
    alias Kaguya.Repo
    alias Kaguya.VisualNovels.VisualNovel
    alias Kaguya.Characters.Character
    alias Kaguya.Producers.Producer

    # Delete test VNs (CASCADE handles junctions)
    {vc, _} = Repo.delete_all(from v in VisualNovel, where: v.vndb_id in @all_test_vndb_ids)

    # Delete producers created during test (not from dump)
    {pc, _} =
      Repo.delete_all(
        from p in Producer,
          where:
            p.inserted_at >= ^@dump_cutoff and
              p.vndb_id in ^["p27782"]
      )

    # Delete characters created during test (not from dump)
    # Be careful: only delete chars that were created after dump AND have vndb_ids
    # that map to chars we'd create in these tests
    test_char_vndb_ids =
      Repo.all(
        from c in Character,
          where: c.inserted_at >= ^@dump_cutoff and not is_nil(c.vndb_id),
          select: c.vndb_id
      )

    {cc, _} =
      if test_char_vndb_ids != [] do
        Repo.delete_all(from c in Character, where: c.vndb_id in ^test_char_vndb_ids)
      else
        {0, nil}
      end

    if vc + pc + cc > 0 do
      IO.puts("[cleanup] Deleted #{vc} VNs, #{pc} producers, #{cc} characters")
    end
  end

  def run_all_tests do
    tests = [
      {"error: invalid vndb_id", &test_invalid_vndb_id/0},
      {"error: not found", &test_not_found/0},
      {"error: existing VN returns without re-import", &test_existing_vn/0},
      {"v61344: JA title + has_ero + min_age + relation + existing producer", &test_v61344/0},
      {"v61349: NSFW + has_ero + JA latin title + length_minutes", &test_v61349/0},
      {"v61386: 26 tags + 8 new characters (all roles) + spoiler atoms", &test_v61386/0},
      {"v61532: long length + Chinese + 0 devs + 5 chars", &test_v61532/0},
      {"v61380: suggestive + 2 existing producers + relation + tags", &test_v61380/0},
      {"v61378: Russian + 0 devs + length_minutes + 22 tags + relation", &test_v61378/0},
      {"v61371: 2 existing producers with slugs + tags", &test_v61371/0},
      {"v62097: existing chars from series + existing producer + relation", &test_v62097/0},
      {"v61602: new producer auto-created + tags", &test_v61602/0},
      {"idempotency: re-import returns same VN", &test_idempotency/0}
    ]

    Enum.reduce(tests, {0, 0, []}, fn {name, test_fn}, {p, f, errs} ->
      IO.write("  #{name} ... ")

      try do
        test_fn.()
        IO.puts("\e[32mPASS\e[0m")
        {p + 1, f, errs}
      rescue
        e ->
          msg = Exception.message(e)
          IO.puts("\e[31mFAIL\e[0m")
          IO.puts("    #{msg}")
          {p, f + 1, [{name, msg} | errs]}
      end
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def import_and_load(vndb_id) do
    import Ecto.Query
    alias Kaguya.Repo
    alias Kaguya.VisualNovels.{VisualNovel, VNTag, Relation}
    alias Kaguya.Characters.VNCharacter
    alias Kaguya.Producers.VNProducer

    {:ok, vn} = Kaguya.Sync.VndbApiImport.import_vn(vndb_id)

    %{
      vn: Repo.one!(from v in VisualNovel, where: v.id == ^vn.id),
      tags: Repo.all(from t in VNTag, where: t.visual_novel_id == ^vn.id),
      characters:
        Repo.all(from c in VNCharacter, where: c.visual_novel_id == ^vn.id, preload: [:character]),
      relations: Repo.all(from r in Relation, where: r.visual_novel_id == ^vn.id),
      producers:
        Repo.all(from p in VNProducer, where: p.visual_novel_id == ^vn.id, preload: [:producer])
    }
  end

  def related_vndb_id(data, relation_type) do
    import Ecto.Query
    rel = Enum.find(data.relations, &(&1.relation_type == relation_type))

    if rel,
      do:
        Kaguya.Repo.one(
          from v in Kaguya.VisualNovels.VisualNovel,
            where: v.id == ^rel.related_vn_id,
            select: v.vndb_id
        )
  end

  def assert!(condition, message) do
    unless condition, do: raise(message)
  end

  def from_dump?(record), do: DateTime.compare(record.inserted_at, @dump_cutoff) == :lt

  # ── Error Tests ──────────────────────────────────────────────────────────

  def test_invalid_vndb_id do
    assert!(
      {:error, :invalid_vndb_id} == VndbApiImport.import_vn("abc123"),
      "abc123 should be invalid"
    )

    assert!({:error, :invalid_vndb_id} == VndbApiImport.import_vn("17"), "17 should be invalid")
    assert!({:error, :invalid_vndb_id} == VndbApiImport.import_vn(""), "empty should be invalid")

    assert!(
      {:error, :invalid_vndb_id} == VndbApiImport.import_vn("https://google.com/v17"),
      "non-vndb URL should be invalid"
    )
  end

  def test_not_found do
    assert!(
      {:error, :not_found} == VndbApiImport.import_vn("v61345"),
      "v61345 should be not_found"
    )
  end

  def test_existing_vn do
    # Test with plain ID
    {:ok, vn} = VndbApiImport.import_vn("v17")
    assert!(vn.vndb_id == "v17", "Should return v17")

    assert!(
      from_dump?(vn),
      "v17 should be from dump, not re-imported (inserted_at=#{vn.inserted_at})"
    )

    # Test with full URL
    {:ok, vn2} = VndbApiImport.import_vn("https://vndb.org/v17")
    assert!(vn2.id == vn.id, "URL import should return same VN as ID import")

    # Test with URL without scheme
    {:ok, vn3} = VndbApiImport.import_vn("vndb.org/v17")
    assert!(vn3.id == vn.id, "Schemeless URL should also work")
  end

  # ── v61344 ───────────────────────────────────────────────────────────────

  def test_v61344 do
    data = import_and_load("v61344")
    vn = data.vn

    assert!(vn.title == "Yarasete! Teacher Returns 4", "Title mismatch: #{vn.title}")
    assert!(vn.original_language == "ja", "Language mismatch: #{vn.original_language}")
    assert!(vn.has_ero == true, "has_ero should be true")
    assert!(vn.min_age == 18, "min_age should be 18, got #{inspect(vn.min_age)}")
    assert!(vn.slug != nil and vn.slug != "", "Slug missing")

    # Relation to existing v54203
    assert!(length(data.relations) == 1, "Expected 1 relation, got #{length(data.relations)}")
    assert!(related_vndb_id(data, "prequel") == "v54203", "Should relate to v54203 as prequel")

    # Existing producer TRYSET
    assert!(length(data.producers) == 1, "Expected 1 producer, got #{length(data.producers)}")
    prod = hd(data.producers)

    assert!(
      prod.producer.name == "TRYSET",
      "Producer should be TRYSET, got #{prod.producer.name}"
    )

    assert!(
      from_dump?(prod.producer),
      "TRYSET should be from dump (inserted=#{prod.producer.inserted_at})"
    )
  end

  # ── v61349 ───────────────────────────────────────────────────────────────

  def test_v61349 do
    data = import_and_load("v61349")
    vn = data.vn

    assert!(vn.is_image_nsfw == true, "Should be NSFW")
    assert!(vn.is_image_suggestive == false, "Should not be suggestive (it's NSFW)")
    assert!(vn.has_ero == true, "has_ero should be true")
    assert!(vn.min_age == 18, "min_age should be 18")
    assert!(vn.title == "shinyuu×jyunai=", "Title mismatch: #{vn.title}")
    assert!(vn.length_category == "short", "Length should be short, got #{vn.length_category}")
    assert!(vn.length_minutes == 135, "Minutes should be 135, got #{vn.length_minutes}")
    assert!(vn.vndb_rating != nil, "vndb_rating should be present")
  end

  # ── v61386 ───────────────────────────────────────────────────────────────

  def test_v61386 do
    data = import_and_load("v61386")

    # Tags
    assert!(length(data.tags) == 26, "Expected 26 tags, got #{length(data.tags)}")

    for tag <- data.tags do
      assert!(tag.vndb_avg_score != nil and tag.vndb_avg_score > 0, "Tag missing vndb_avg_score")

      assert!(
        tag.spoiler_level in [:none, :minor, :major],
        "Tag spoiler_level should be atom, got #{inspect(tag.spoiler_level)}"
      )
    end

    # Characters
    assert!(length(data.characters) == 8, "Expected 8 characters, got #{length(data.characters)}")
    roles = data.characters |> Enum.map(& &1.role) |> Enum.uniq() |> Enum.sort()

    assert!(
      roles == [:appears, :main, :primary, :side],
      "Expected all 4 roles, got #{inspect(roles)}"
    )

    for cj <- data.characters do
      assert!(cj.character.name != nil and cj.character.name != "", "Character missing name")
      assert!(cj.character.slug != nil and cj.character.slug != "", "Character missing slug")
      assert!(!from_dump?(cj.character), "#{cj.character.name} should be new, not from dump")
    end
  end

  # ── v61532 ───────────────────────────────────────────────────────────────

  def test_v61532 do
    data = import_and_load("v61532")
    vn = data.vn

    assert!(vn.length_category == "long", "Length should be long, got #{vn.length_category}")

    assert!(
      vn.original_language == "zh-Hans",
      "Language should be zh-Hans, got #{vn.original_language}"
    )

    assert!(data.producers == [], "Should have 0 producers")
    assert!(length(data.characters) == 5, "Expected 5 characters, got #{length(data.characters)}")
    assert!(vn.vndb_rating != nil, "vndb_rating should be present")
  end

  # ── v61380 ───────────────────────────────────────────────────────────────

  def test_v61380 do
    data = import_and_load("v61380")
    vn = data.vn

    assert!(vn.is_image_suggestive == true, "Should be suggestive")
    assert!(vn.is_image_nsfw == false, "Should NOT be NSFW")

    # 2 existing producers
    assert!(length(data.producers) == 2, "Expected 2 producers, got #{length(data.producers)}")
    names = data.producers |> Enum.map(& &1.producer.name) |> Enum.sort()
    assert!(names == ["EdgesSystem", "Floramisu"], "Producers mismatch: #{inspect(names)}")

    for pj <- data.producers do
      assert!(from_dump?(pj.producer), "#{pj.producer.name} should be from dump")
    end

    # Relation
    assert!(length(data.relations) == 1, "Expected 1 relation, got #{length(data.relations)}")
    assert!(related_vndb_id(data, "same_setting") == "v54217", "Should relate to v54217")

    # Tags
    assert!(length(data.tags) == 17, "Expected 17 tags, got #{length(data.tags)}")
  end

  # ── v61378 ───────────────────────────────────────────────────────────────

  def test_v61378 do
    data = import_and_load("v61378")
    vn = data.vn

    assert!(vn.original_language == "ru", "Language should be ru")
    assert!(vn.length_minutes == 60, "Minutes should be 60, got #{vn.length_minutes}")
    assert!(data.producers == [], "Should have 0 producers")
    assert!(length(data.tags) == 22, "Expected 22 tags, got #{length(data.tags)}")

    assert!(length(data.relations) == 1, "Expected 1 relation, got #{length(data.relations)}")

    assert!(
      related_vndb_id(data, "alternative") == "v21418",
      "Should relate to v21418 (Tiny Bunny)"
    )
  end

  # ── v61371 ───────────────────────────────────────────────────────────────

  def test_v61371 do
    data = import_and_load("v61371")

    assert!(length(data.producers) == 2, "Expected 2 producers, got #{length(data.producers)}")
    names = data.producers |> Enum.map(& &1.producer.name) |> Enum.sort()
    assert!(names == ["Air Gong", "Cutie Collective"], "Producers mismatch: #{inspect(names)}")

    for pj <- data.producers do
      assert!(
        pj.producer.slug not in [nil, "", "placeholder"],
        "#{pj.producer.name} missing slug"
      )

      assert!(from_dump?(pj.producer), "#{pj.producer.name} should be from dump")
    end

    assert!(length(data.tags) == 7, "Expected 7 tags, got #{length(data.tags)}")
  end

  # ── v62097 ───────────────────────────────────────────────────────────────

  def test_v62097 do
    data = import_and_load("v62097")

    # Existing characters from Sakura Succubus series
    expected_existing = [
      "Cosmos Moretti",
      "Hazel Williams",
      "Ogasawara Hiroki",
      "Wakatsuki Marina",
      "Yamamoto Hifumi"
    ]

    char_names = data.characters |> Enum.map(& &1.character.name) |> Enum.sort()

    for name <- expected_existing do
      assert!(
        name in char_names,
        "Expected existing character #{name}, got #{inspect(char_names)}"
      )
    end

    existing_chars = Enum.filter(data.characters, &(&1.character.name in expected_existing))

    for cj <- existing_chars do
      assert!(
        from_dump?(cj.character),
        "#{cj.character.name} (#{cj.character.vndb_id}) should be from dump, inserted=#{cj.character.inserted_at}"
      )
    end

    # Existing producer
    assert!(length(data.producers) == 1, "Expected 1 producer")
    assert!(hd(data.producers).producer.name == "Winged Cloud", "Producer should be Winged Cloud")
    assert!(from_dump?(hd(data.producers).producer), "Winged Cloud should be from dump")

    # Relation
    assert!(length(data.relations) == 1, "Expected 1 relation")
    assert!(related_vndb_id(data, "prequel") == "v52214", "Should relate to v52214")

    # Tags
    assert!(length(data.tags) == 7, "Expected 7 tags, got #{length(data.tags)}")
  end

  # ── v61602 ───────────────────────────────────────────────────────────────

  def test_v61602 do
    data = import_and_load("v61602")

    assert!(length(data.producers) == 1, "Expected 1 producer")
    pj = hd(data.producers)

    assert!(
      pj.producer.name == "Tokyo Frequency",
      "Producer should be Tokyo Frequency, got #{pj.producer.name}"
    )

    assert!(pj.producer.vndb_id == "p27782", "Producer vndb_id should be p27782")

    assert!(
      pj.producer.slug not in [nil, "", "placeholder"],
      "Producer missing slug (got #{pj.producer.slug})"
    )

    assert!(!from_dump?(pj.producer), "Tokyo Frequency should be NEW, not from dump")

    assert!(length(data.tags) == 7, "Expected 7 tags, got #{length(data.tags)}")
  end

  # ── Idempotency ──────────────────────────────────────────────────────────

  def test_idempotency do
    # v61344 should already be imported from earlier test
    {:ok, vn1} = VndbApiImport.import_vn("v61344")
    {:ok, vn2} = VndbApiImport.import_vn("v61344")
    assert!(vn1.id == vn2.id, "Should return same VN")
    assert!(vn1.inserted_at == vn2.inserted_at, "Should not re-insert")
  end
end

IO.puts("\n=== VNDB Import Integration Tests ===\n")
ImportTest.run()

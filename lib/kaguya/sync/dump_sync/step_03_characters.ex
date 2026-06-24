defmodule Kaguya.Sync.DumpSync.Characters do
  @moduledoc """
  Syncs characters and VN-character junctions from VNDB dump.

  Step 3: Characters + VN-character associations.
  New characters are inserted with real slugs (on_conflict: :nothing).
  Existing characters are updated with only @char_replace_fields (slug is never touched).

  Supporting data (names, image flags) is loaded per-batch to keep memory bounded.
  """

  require Logger

  alias Kaguya.Sync.DumpSync
  alias Kaguya.Sync.DumpSync.Report
  alias Kaguya.Sync.VndbFieldMapper
  alias Kaguya.Utils.SlugUtils
  alias Kaguya.Characters.{Character, VNCharacter}

  @batch_size 5000

  @char_content_fields [
    :name,
    :description,
    :sex,
    :spoiler_sex,
    :gender,
    :spoiler_gender,
    :blood_type,
    :height,
    :weight,
    :age,
    :birthday,
    :bust,
    :waist,
    :hip,
    :cup_size,
    :is_image_nsfw,
    :is_image_suggestive
  ]

  @char_reference_fields [:vndb_image_id, :temp_image_url, :updated_at]
  @char_replace_fields @char_content_fields ++ @char_reference_fields

  alias Kaguya.Sync.DumpSync.SyncProtection

  def run(%{vndb: vndb, dry_run: dry_run, vn_mapping: vn_mapping} = ctx) do
    target_ids = ctx[:target_vndb_ids]

    protected_uuids = SyncProtection.user_edited_ids(:character)
    protected_vndb_ids = SyncProtection.user_edited_vndb_ids(:character, Character)

    if MapSet.size(protected_vndb_ids) > 0,
      do:
        Logger.info(
          "#{MapSet.size(protected_vndb_ids)} user-edited characters protected from content overwrite"
        )

    if target_ids do
      process_targeted_characters(
        vndb,
        target_ids,
        vn_mapping,
        protected_vndb_ids,
        protected_uuids
      )
    else
      Logger.info("Loading characters from VNDB dump...")

      total = count_chars(vndb)
      Logger.info("Total characters in dump: #{total}")

      # Pre-compute which characters have at least one VN in Kaguya.
      # Characters linked only to banned/non-imported VNs are skipped entirely
      # to avoid inserting orphans that the removals step would immediately delete.
      importable_char_ids = load_importable_char_ids(vndb, vn_mapping)
      skipped = total - MapSet.size(importable_char_ids)

      Logger.info(
        "Importable characters: #{MapSet.size(importable_char_ids)} (#{skipped} skipped — no importable VN links)"
      )

      if dry_run do
        vn_char_count = count_char_vns(vndb)

        Logger.info(
          "[DRY RUN] Would process #{MapSet.size(importable_char_ids)} characters and #{vn_char_count} VN-character junctions"
        )

        Logger.info(
          "[DRY RUN] Would skip #{skipped} characters (linked only to banned/non-imported VNs)"
        )

        {:ok, total}
      else
        # Process characters in batches (names + image flags loaded per-batch)
        existing_char_vndb_ids = load_existing_char_vndb_ids()

        {char_count, new_total, updated_total, new_ids} =
          do_char_batches(
            vndb,
            existing_char_vndb_ids,
            importable_char_ids,
            protected_vndb_ids,
            0,
            0,
            0,
            0,
            []
          )

        Report.record(:characters, new_total, updated_total, new_ids)

        # Now process VN-character junctions
        junction_count = process_vn_characters(vndb, vn_mapping, protected_uuids)
        Report.record(:vn_characters, junction_count, 0)

        Logger.info(
          "Character sync complete: #{char_count} characters (#{new_total} new, #{updated_total} updated), #{skipped} skipped (no importable VNs), #{junction_count} VN-character junctions"
        )

        {:ok, char_count + junction_count}
      end
    end
  end

  # ── Targeted Character Import ──────────────────────────────────────────────

  defp process_targeted_characters(vndb, target_ids, _vn_mapping, protected_ids, protected_uuids) do
    # Reload vn_mapping to include VNs just inserted in step 01
    # (entity steps share the initial mapping; targeted import needs the fresh one)
    vn_mapping = DumpSync.load_vn_mapping()
    Logger.info("Importing characters for #{length(target_ids)} targeted VN(s)...")
    phs = DumpSync.placeholders(target_ids)

    # Find characters linked to target VNs
    char_dump_ids =
      DumpSync.query_vndb_raw!(
        vndb,
        "SELECT DISTINCT id FROM chars_vns WHERE vid IN (#{phs})",
        target_ids
      )
      |> Enum.map(fn [id] -> id end)

    if char_dump_ids == [] do
      Logger.info("No characters found for targeted VNs")
      {:ok, 0}
    else
      now = DumpSync.now()
      char_phs = DumpSync.placeholders(char_dump_ids)
      existing_char_vndb_ids = load_existing_char_vndb_ids()

      chars =
        DumpSync.query_vndb!(
          vndb,
          """
          SELECT id, image, sex::text, gender::text, spoil_sex::text, spoil_gender::text,
                 bloodt::text, height, weight, birthday, s_bust, s_waist, s_hip,
                 cup_size::text, age, description
          FROM chars WHERE id IN (#{char_phs})
          """,
          char_dump_ids
        )

      names_map = load_names_for(vndb, char_dump_ids)
      char_image_ids = chars |> Enum.map(& &1.image) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      image_flags_map = load_image_flags_for(vndb, char_image_ids)

      {existing_chars, new_chars} =
        Enum.split_with(chars, fn c -> MapSet.member?(existing_char_vndb_ids, char_vndb_id(c)) end)

      new_slug_map = generate_char_slugs(new_chars, names_map)

      new_rows =
        Enum.map(new_chars, &build_char_row(&1, names_map, image_flags_map, new_slug_map, now))

      new_count =
        DumpSync.chunked_insert(Character, new_rows,
          on_conflict: :nothing,
          conflict_target: [:vndb_id]
        )

      write_create_revisions_for_new_chars(new_chars, new_rows)

      existing_rows =
        Enum.map(existing_chars, &build_char_row(&1, names_map, image_flags_map, %{}, now))

      existing_count =
        SyncProtection.protected_upsert(Character, existing_rows, protected_ids, & &1.vndb_id,
          full_replace_fields: @char_replace_fields,
          reference_replace_fields: @char_reference_fields,
          conflict_target: [:vndb_id]
        )

      Report.record(
        :characters,
        new_count,
        existing_count,
        Enum.map(new_chars, fn c ->
          names = Map.get(names_map, c.id, [])

          %{
            id: char_vndb_id(c),
            name: resolve_char_name(c, names),
            slug: Map.get(new_slug_map, char_vndb_id(c), "—")
          }
        end)
      )

      # Targeted VN-character junctions
      char_mapping = DumpSync.load_char_mapping()

      junction_count =
        process_targeted_junctions(
          vndb,
          target_ids,
          vn_mapping,
          char_mapping,
          protected_uuids,
          now
        )

      Report.record(:vn_characters, junction_count, 0)

      Logger.info(
        "Targeted character import: #{new_count} new, #{existing_count} updated, #{junction_count} junctions"
      )

      {:ok, new_count + existing_count + junction_count}
    end
  end

  defp process_targeted_junctions(
         vndb,
         target_ids,
         vn_mapping,
         char_mapping,
         protected_uuids,
         now
       ) do
    phs = DumpSync.placeholders(target_ids)

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, vid, role::text, spoil FROM chars_vns WHERE vid IN (#{phs})
        """,
        target_ids
      )

    valid_rows =
      Enum.flat_map(rows, fn r ->
        with char_uuid when not is_nil(char_uuid) <- Map.get(char_mapping, r.id),
             false <- MapSet.member?(protected_uuids, char_uuid),
             vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, r.vid) do
          [%{char_uuid: char_uuid, vn_uuid: vn_uuid, role: r.role, spoil: r.spoil}]
        else
          _ -> []
        end
      end)
      |> Enum.group_by(fn r -> {r.char_uuid, r.vn_uuid} end)
      |> Enum.map(fn {_key, dupes} -> Enum.min_by(dupes, fn r -> role_priority(r.role) end) end)

    insert_rows =
      Enum.map(valid_rows, fn r ->
        %{
          visual_novel_id: r.vn_uuid,
          character_id: r.char_uuid,
          role: VndbFieldMapper.map_character_role(r.role),
          spoiler_level: r.spoil || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    DumpSync.chunked_insert(VNCharacter, insert_rows,
      on_conflict: {:replace, [:role, :spoiler_level, :updated_at]},
      conflict_target: [:visual_novel_id, :character_id]
    )
  end

  # ── Character Entity Sync ───────────────────────────────────────────────────

  defp do_char_batches(
         vndb,
         existing_ids,
         importable_ids,
         protected_ids,
         offset,
         acc,
         new_acc,
         updated_acc,
         ids_acc
       ) do
    chars =
      DumpSync.query_vndb!(vndb, """
      SELECT id, image, sex::text, gender::text, spoil_sex::text, spoil_gender::text,
             bloodt::text, height, weight, birthday, s_bust, s_waist, s_hip,
             cup_size::text, age, description
      FROM chars
      ORDER BY id
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if chars == [] do
      {acc, new_acc, updated_acc, ids_acc}
    else
      # Filter to characters that have at least one importable VN link
      chars = Enum.filter(chars, fn c -> MapSet.member?(importable_ids, c.id) end)

      if chars == [] do
        do_char_batches(
          vndb,
          existing_ids,
          importable_ids,
          protected_ids,
          offset + @batch_size,
          acc,
          new_acc,
          updated_acc,
          ids_acc
        )
      else
        Logger.info(
          "Processing character batch at offset #{offset} (#{length(chars)} importable)..."
        )

        now = DumpSync.now()

        # Load supporting data for just this batch
        char_ids = Enum.map(chars, & &1.id)
        names_map = load_names_for(vndb, char_ids)

        image_ids = chars |> Enum.map(& &1.image) |> Enum.reject(&is_nil/1) |> Enum.uniq()
        image_flags_map = load_image_flags_for(vndb, image_ids)

        {existing_chars, new_chars} =
          Enum.split_with(chars, fn c -> MapSet.member?(existing_ids, char_vndb_id(c)) end)

        # Insert new characters with real slugs
        new_slug_map = generate_char_slugs(new_chars, names_map)

        new_rows =
          Enum.map(new_chars, &build_char_row(&1, names_map, image_flags_map, new_slug_map, now))

        new_count =
          DumpSync.chunked_insert(Character, new_rows,
            on_conflict: :nothing,
            conflict_target: [:vndb_id]
          )

        write_create_revisions_for_new_chars(new_chars, new_rows)

        # Update existing characters — protected entities only get reference fields
        existing_rows =
          Enum.map(existing_chars, &build_char_row(&1, names_map, image_flags_map, %{}, now))

        existing_count =
          SyncProtection.protected_upsert(Character, existing_rows, protected_ids, & &1.vndb_id,
            full_replace_fields: @char_replace_fields,
            reference_replace_fields: @char_reference_fields,
            conflict_target: [:vndb_id]
          )

        batch_new_ids =
          Enum.map(new_chars, fn c ->
            vndb_id = char_vndb_id(c)
            names = Map.get(names_map, c.id, [])
            name = resolve_char_name(c, names)
            slug = Map.get(new_slug_map, vndb_id, "—")
            %{id: vndb_id, name: name, slug: slug}
          end)

        do_char_batches(
          vndb,
          existing_ids,
          importable_ids,
          protected_ids,
          offset + @batch_size,
          acc + new_count + existing_count,
          new_acc + new_count,
          updated_acc + existing_count,
          ids_acc ++ batch_new_ids
        )
      end
    end
  end

  # Writes a :create revision for each character actually inserted (not
  # a conflict). Looks up which intended UUIDs are now in the DB so rerun
  # doesn't double-write.
  defp write_create_revisions_for_new_chars([], _new_rows), do: :ok

  defp write_create_revisions_for_new_chars(new_chars, new_rows) do
    import Ecto.Query

    intended_map = Map.new(new_rows, fn r -> {r.vndb_id, r.id} end)
    intended_vndb_ids = Enum.map(new_chars, &char_vndb_id/1)

    actual =
      from(c in Character,
        where: c.vndb_id in ^intended_vndb_ids,
        select: {c.vndb_id, c.id}
      )
      |> Kaguya.Repo.all()
      |> Map.new()

    entries =
      Enum.flat_map(new_chars, fn c ->
        vndb_id = char_vndb_id(c)
        intended_uuid = Map.get(intended_map, vndb_id)
        actual_uuid = Map.get(actual, vndb_id)

        if intended_uuid && intended_uuid == actual_uuid do
          [
            %{
              entity_type: :character,
              entity_id: actual_uuid,
              action: :create,
              source: :vndb_sync,
              changed_fields: [],
              summary: "Imported from VNDB dump"
            }
          ]
        else
          []
        end
      end)

    # Extra idempotency: skip any character that already has a :create
    # revision (e.g. a character manually added via the API before this
    # sync noticed it). Prior edit/revert rows are tolerated — we only
    # want to avoid a duplicate create.
    entries =
      if entries == [] do
        entries
      else
        existing =
          from(c in Kaguya.Revisions.Change,
            where:
              c.entity_type == :character and c.action == :create and
                c.entity_id in ^Enum.map(entries, & &1.entity_id),
            select: c.entity_id
          )
          |> Kaguya.Repo.all()
          |> MapSet.new()

        Enum.reject(entries, fn e -> MapSet.member?(existing, e.entity_id) end)
      end

    case Kaguya.Revisions.bulk_create_system_changes(entries) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to write character create revisions: #{inspect(reason)}")
        :ok
    end
  end

  defp build_char_row(c, names_map, image_flags_map, new_slug_map, now) do
    vndb_id = char_vndb_id(c)
    names = Map.get(names_map, c.id, [])
    name = resolve_char_name(c, names)
    desc = VndbFieldMapper.clean_description(c.description)

    {is_nsfw, is_suggestive} = get_char_image_flags(c.image, image_flags_map)
    temp_url = build_char_image_url(c.image)

    # New chars: real slug from new_slug_map, inserted via on_conflict: :nothing.
    # Existing chars: called with empty slug_map, so falls back to UUID placeholder.
    # Placeholder satisfies NOT NULL but is discarded — existing path uses
    # on_conflict: {:replace, @char_replace_fields} which excludes :slug.
    slug = Map.get(new_slug_map, vndb_id) || UUIDv7.generate()

    %{
      id: UUIDv7.generate(),
      vndb_id: vndb_id,
      name: name,
      description: desc,
      slug: slug,
      sex: map_dump_sex(c.sex),
      spoiler_sex: map_dump_sex(c.spoil_sex),
      gender: map_dump_gender(c.gender),
      spoiler_gender: map_dump_gender(c.spoil_gender),
      blood_type: map_dump_blood(c.bloodt),
      height: VndbFieldMapper.nullify_zero(c.height),
      weight: VndbFieldMapper.nullify_zero(c.weight),
      age: VndbFieldMapper.nullify_zero(c.age),
      birthday: VndbFieldMapper.nullify_zero(c.birthday),
      bust: VndbFieldMapper.nullify_zero(c.s_bust),
      waist: VndbFieldMapper.nullify_zero(c.s_waist),
      hip: VndbFieldMapper.nullify_zero(c.s_hip),
      cup_size: VndbFieldMapper.nullify_empty(c.cup_size),
      vndb_image_id: c.image,
      temp_image_url: temp_url,
      is_image_nsfw: is_nsfw,
      is_image_suggestive: is_suggestive,
      inserted_at: now,
      updated_at: now
    }
  end

  # ── VN-Character Junctions ──────────────────────────────────────────────────

  defp process_vn_characters(vndb, vn_mapping, protected_char_uuids) do
    char_mapping = DumpSync.load_char_mapping()
    now = DumpSync.now()

    do_vn_char_batches(vndb, vn_mapping, char_mapping, protected_char_uuids, now, 0, 0)
  end

  defp do_vn_char_batches(vndb, vn_mapping, char_mapping, protected_char_uuids, now, offset, acc) do
    rows =
      DumpSync.query_vndb!(vndb, """
      SELECT id, vid, role::text, spoil
      FROM chars_vns
      ORDER BY id, vid
      LIMIT #{@batch_size} OFFSET #{offset}
      """)

    if rows == [] do
      acc
    else
      valid_rows =
        Enum.flat_map(rows, fn r ->
          with char_uuid when not is_nil(char_uuid) <- Map.get(char_mapping, r.id),
               false <- MapSet.member?(protected_char_uuids, char_uuid),
               vn_uuid when not is_nil(vn_uuid) <- Map.get(vn_mapping, r.vid) do
            [%{char_uuid: char_uuid, vn_uuid: vn_uuid, role: r.role, spoil: r.spoil}]
          else
            _ -> []
          end
        end)

      # Deduplicate: VNDB dump has ~2,600 duplicate (id, vid) pairs with different roles.
      # Keep the highest-priority role per (character, VN) pair: main > primary > side > appears.
      deduped =
        valid_rows
        |> Enum.group_by(fn r -> {r.char_uuid, r.vn_uuid} end)
        |> Enum.map(fn {_key, dupes} ->
          Enum.min_by(dupes, fn r -> role_priority(r.role) end)
        end)

      insert_rows =
        Enum.map(deduped, fn r ->
          %{
            visual_novel_id: r.vn_uuid,
            character_id: r.char_uuid,
            role: VndbFieldMapper.map_character_role(r.role),
            spoiler_level: r.spoil || 0,
            inserted_at: now,
            updated_at: now
          }
        end)

      count =
        DumpSync.chunked_insert(VNCharacter, insert_rows,
          on_conflict: {:replace, [:role, :spoiler_level, :updated_at]},
          conflict_target: [:visual_novel_id, :character_id]
        )

      do_vn_char_batches(
        vndb,
        vn_mapping,
        char_mapping,
        protected_char_uuids,
        now,
        offset + @batch_size,
        acc + count
      )
    end
  end

  # ── Per-Batch Data Loading ─────────────────────────────────────────────────

  defp load_names_for(_vndb, []), do: %{}

  defp load_names_for(vndb, char_ids) do
    placeholders = Enum.map_join(1..length(char_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, lang::text, name, latin
        FROM chars_names
        WHERE id IN (#{placeholders})
        """,
        char_ids
      )

    Enum.group_by(rows, & &1.id)
  end

  defp load_image_flags_for(_vndb, []), do: %{}

  defp load_image_flags_for(vndb, image_ids) do
    placeholders = Enum.map_join(1..length(image_ids), ", ", &"$#{&1}")

    rows =
      DumpSync.query_vndb!(
        vndb,
        """
        SELECT id, c_sexual_avg, c_violence_avg, c_votecount
        FROM images
        WHERE id IN (#{placeholders})
        """,
        image_ids
      )

    Map.new(rows, fn r -> {r.id, r} end)
  end

  defp count_chars(vndb) do
    [[count]] = DumpSync.query_vndb_raw!(vndb, "SELECT COUNT(*) FROM chars")
    count
  end

  defp count_char_vns(vndb) do
    [[count]] = DumpSync.query_vndb_raw!(vndb, "SELECT COUNT(*) FROM chars_vns")
    count
  end

  defp load_existing_char_vndb_ids do
    import Ecto.Query

    from(c in Character, where: not is_nil(c.vndb_id), select: c.vndb_id)
    |> Kaguya.Repo.all()
    |> MapSet.new()
  end

  # Returns the set of character IDs (raw dump format) that have at least one
  # VN link to an importable (non-banned, existing) VN.
  defp load_importable_char_ids(vndb, vn_mapping) do
    DumpSync.query_vndb_raw!(vndb, "SELECT DISTINCT id, vid FROM chars_vns")
    |> Enum.reduce(MapSet.new(), fn [char_id, vid], acc ->
      if Map.has_key?(vn_mapping, vid) do
        MapSet.put(acc, char_id)
      else
        acc
      end
    end)
  end

  # ── Name Resolution ─────────────────────────────────────────────────────────

  # Matches the original import priority: en name → any latin (JA first) → any name (JA first).
  # The original SQL used ORDER BY CASE WHEN lang='ja' THEN 0 ELSE 1 END to prefer JA.
  defp resolve_char_name(c, names) do
    en_name = Enum.find(names, fn n -> n.lang == "en" end)

    # Any latin, preferring Japanese (matches original's name_latin subquery)
    latin_name =
      Enum.find(names, fn n -> n.lang == "ja" and non_blank?(n.latin) end) ||
        Enum.find(names, fn n -> non_blank?(n.latin) end)

    # Any name, preferring Japanese (matches original's name_fallback subquery)
    fallback_name =
      Enum.find(names, fn n -> n.lang == "ja" end) ||
        List.first(names)

    name =
      cond do
        en_name && non_blank?(en_name.name) -> en_name.name
        latin_name -> latin_name.latin
        fallback_name && non_blank?(fallback_name.name) -> fallback_name.name
        true -> "Character #{c.id}"
      end

    VndbFieldMapper.sanitize_utf8(name)
  end

  defp generate_char_slugs([], _names_map), do: %{}

  defp generate_char_slugs(chars, names_map) do
    slug_items =
      Enum.map(chars, fn c ->
        names = Map.get(names_map, c.id, [])
        name = resolve_char_name(c, names)
        %{title: name, char: c}
      end)

    slugged =
      SlugUtils.build_unique_slugs(slug_items, Character, :slug, & &1.title)

    Map.new(slugged, fn s -> {char_vndb_id(s.char), s._slug} end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp char_vndb_id(%{id: id}) when is_integer(id), do: "c#{id}"
  defp char_vndb_id(%{id: <<"c", _::binary>> = id}), do: id
  defp char_vndb_id(%{id: id}), do: "c#{id}"

  defp map_dump_sex("m"), do: :male
  defp map_dump_sex("f"), do: :female
  defp map_dump_sex("b"), do: :both
  defp map_dump_sex("n"), do: :unknown
  defp map_dump_sex(_), do: nil

  defp map_dump_gender("m"), do: :male
  defp map_dump_gender("f"), do: :female
  defp map_dump_gender("o"), do: :other
  defp map_dump_gender("a"), do: :ambiguous
  defp map_dump_gender(_), do: nil

  defp map_dump_blood("a"), do: :a
  defp map_dump_blood("b"), do: :b
  defp map_dump_blood("ab"), do: :ab
  defp map_dump_blood("o"), do: :o
  defp map_dump_blood(_), do: nil

  defp get_char_image_flags(nil, _map), do: {false, false}

  defp get_char_image_flags(image_id, image_flags_map) do
    case Map.get(image_flags_map, image_id) do
      nil ->
        {false, false}

      img ->
        sexual = (img.c_sexual_avg || 0) / 100.0
        votecount = img.c_votecount || 0
        VndbFieldMapper.compute_image_flags(sexual, votecount)
    end
  end

  defp build_char_image_url(nil), do: nil

  defp build_char_image_url(image_id) when is_binary(image_id) do
    case Regex.run(~r/^ch(\d+)$/, image_id) do
      [_, num_str] ->
        num = String.to_integer(num_str)
        suffix = rem(num, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
        "https://s.vndb.org/ch/#{suffix}/#{num}.jpg"

      _ ->
        nil
    end
  end

  defp non_blank?(nil), do: false
  defp non_blank?(""), do: false
  defp non_blank?(s) when is_binary(s), do: String.trim(s) != ""
  defp non_blank?(_), do: false

  # Role priority for deduplication: lower = more important
  defp role_priority("main"), do: 0
  defp role_priority("primary"), do: 1
  defp role_priority("side"), do: 2
  defp role_priority(_), do: 3
end

defmodule Kaguya.Sync.VndbFieldMapper do
  @moduledoc """
  Centralizes field mapping logic for VNDB API v2 responses → Kaguya schemas.

  Originally extracted from the one-shot VNDB import scripts (since removed;
  their logic now lives in `mix kaguya.dump_sync`) so both the weekly sync
  and on-demand import use identical transformations.
  """

  alias Kaguya.Tags.TagRelevance

  # ── VN Title Resolution ────────────────────────────────────────────────────

  @doc """
  7-level title priority from VNDB API `titles` array.

  Priority (first match wins):
    1. Official English title
    2. Official Japanese latin title (romanized)
    3. Official Japanese title (native)
    4. Official other-language title when latin IS NULL
    5. Official other-language latin title
    6. Non-official latin title
    7. Non-official title

  Each entry in `titles`: %{"lang" => "en", "title" => "...", "latin" => "...",
  "official" => true, "main" => true}
  """
  def resolve_title(titles, _olang) when is_list(titles) do
    candidates =
      Enum.flat_map(titles, fn t ->
        lang = t["lang"]
        title = t["title"]
        latin = t["latin"]
        official = t["official"] == true

        cond do
          # Priority 1: Official English title
          official and lang == "en" and non_blank?(title) ->
            [{1, title}]

          # Priority 2 & 3: Official Japanese
          official and lang == "ja" ->
            entries = []
            entries = if non_blank?(latin), do: [{2, latin} | entries], else: entries
            entries = if non_blank?(title), do: [{3, title} | entries], else: entries
            entries

          # Priority 4 & 5: Official other-language
          official ->
            if is_nil(latin) or latin == "" do
              if non_blank?(title), do: [{4, title}], else: []
            else
              if non_blank?(latin), do: [{5, latin}], else: []
            end

          # Priority 6 & 7: Non-official
          true ->
            entries = []
            entries = if non_blank?(latin), do: [{6, latin} | entries], else: entries
            entries = if non_blank?(title), do: [{7, title} | entries], else: entries
            entries
        end
      end)

    case Enum.sort_by(candidates, &elem(&1, 0)) do
      [{_priority, title} | _] -> title
      [] -> nil
    end
  end

  def resolve_title(_, _), do: nil

  @doc """
  Extract the Japanese latin (romanized) title for the `latin_title` column.
  Used for Meilisearch prefix matching.

  When the Japanese entry has a `latin` field, use it directly.
  Otherwise, if the Japanese title itself is already in Latin script
  (e.g. "BUNNYBLACK2", "STEINS;GATE"), use that as a fallback —
  VNDB leaves `latin` null when the title needs no romanization.
  """
  def resolve_latin_title(titles) when is_list(titles) do
    titles
    |> Enum.find_value(fn t ->
      if t["lang"] == "ja" do
        cond do
          non_blank?(t["latin"]) -> t["latin"]
          non_blank?(t["title"]) and latin_script?(t["title"]) -> t["title"]
          true -> nil
        end
      end
    end)
  end

  def resolve_latin_title(_), do: nil

  # ── VN Field Mappings ──────────────────────────────────────────────────────

  def map_development_status(0), do: "finished"
  def map_development_status(1), do: "in_development"
  def map_development_status(2), do: "abandoned"
  def map_development_status(_), do: nil

  def map_length_category(1), do: "short"
  def map_length_category(2), do: "short"
  def map_length_category(3), do: "medium"
  def map_length_category(4), do: "long"
  def map_length_category(5), do: "very_long"
  def map_length_category(_), do: nil

  @doc """
  Derive length_category from length_minutes when the categorical field is nil.
  Uses the same thresholds as the backfill task.
  """
  def length_category_from_minutes(nil), do: nil
  def length_category_from_minutes(0), do: nil
  def length_category_from_minutes(mins) when mins < 600, do: "short"
  def length_category_from_minutes(mins) when mins < 1800, do: "medium"
  def length_category_from_minutes(mins) when mins < 3000, do: "long"
  def length_category_from_minutes(_), do: "very_long"

  @doc """
  Parse VNDB API release date string.
  API returns "YYYY-MM-DD", "YYYY-MM", "YYYY", "TBA", or null.
  We only keep fully specified dates.
  """
  def parse_api_release_date(nil), do: nil
  def parse_api_release_date("TBA"), do: nil

  def parse_api_release_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  def parse_api_release_date(_), do: nil

  @doc """
  Compute is_image_nsfw and is_image_suggestive from VNDB API image data.
  API `image.sexual` is 0-2 float, `image.votecount` is integer.

  Thresholds (matching initial import):
  - NSFW: sexual > 1.3 AND votecount >= 3
  - Suggestive: sexual > 0.5 AND ≤ 1.3 AND votecount >= 3

  The suggestive lower bound is intentionally above VNDB's own "safe" cutoff
  of 0.4 — borderline covers like Saya no Uta (sexual ≈ 0.47) come back as
  safe so the frontend doesn't blur them.
  """
  def compute_image_flags(nil, _votecount), do: {false, false}
  def compute_image_flags(_sexual, nil), do: {false, false}

  def compute_image_flags(sexual, votecount) when is_number(sexual) and is_number(votecount) do
    if votecount >= 3 do
      is_nsfw = sexual > 1.3
      is_suggestive = sexual > 0.5 and not is_nsfw
      {is_nsfw, is_suggestive}
    else
      {false, false}
    end
  end

  def compute_image_flags(_, _), do: {false, false}

  @doc """
  Convert VNDB API `average` field (1-100 raw average) to our Decimal (0-10 scale).
  We use `average` (raw), NOT `rating` (Bayesian weighted), matching the initial import
  which uses `c_average / 100`.
  """
  def convert_api_rating(nil), do: nil

  def convert_api_rating(average) when is_number(average) do
    Decimal.from_float(average / 10.0)
  end

  def convert_api_rating(_), do: nil

  @doc """
  Clean VNDB description text for storage.

  Strips VNDB-internal `[url]` tags and source attribution brackets, then
  converts remaining BBCode formatting to Markdown via `VndbToMarkdown`.

  Pipeline:
  1. Sanitize UTF-8
  2. Strip `[url=...]text[/url]` → keep link text (VNDB-internal links not useful)
  3. Strip source attribution brackets (e.g. `[From itch.io]`)
  4. Convert remaining BBCode (`[b]`, `[i]`, `[spoiler]`, etc.) → Markdown
  """
  def clean_description(nil), do: nil

  def clean_description(desc) when is_binary(desc) do
    desc
    |> sanitize_utf8()
    |> do_clean_description()
  end

  def clean_description(_), do: nil

  defp do_clean_description(nil), do: nil

  defp do_clean_description(desc) do
    desc
    # Strip URL BBCode tags (keep link text)
    |> String.replace(~r/\[url=[^\]]*\]/i, "")
    |> String.replace(~r/\[\/url\]/i, "")
    # Strip source attribution brackets
    |> String.replace(
      ~r/\n*\[\s*(?:F[r]?[io]?m[: ]?|Fri?om|Edit|Translat|Based |Taken|Source|Translation of|Summary|Synopsis|Adapt|Adopt|Courtesy|Via |Description |Condensed|Modified|Loo?sely |Short[yl ]|Lightly|Rough|Machine|Heavily|Partially|Slightly|Poorly|Freely|Rewritten|Rephrased|Paraphrased|Summarized|MTL|Excerpt|More from |Mostly|Quoted|Slight |Derived|Written|Mirror|Official |Shortened|Form |First |Very |Simplified|Combined|Copied|Guesslat|Drawn|Slogan|Website |Self |Following|Quick |Modif|By |Japanese |Unknown |Info |Introduction |Plot |Unofficial |Vague |DLsite|DLSite|DeepSeek)(?:[^\]\n]*\]|[^\]\n]*\Z)/mi,
      ""
    )
    |> String.trim()
    # Convert remaining BBCode formatting to Markdown
    |> VndbToMarkdown.convert()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  @doc """
  Clean VNDB release notes for storage.

  Unlike descriptions, release notes have no attribution brackets and their
  `[url]` tags link to external sites — so we convert them to Markdown links
  rather than stripping them.

  After BBCode→Markdown conversion, expands VNDB-relative links
  (e.g. `(/r12345)` → `(https://vndb.org/r12345)`) and linkifies bare
  release IDs (e.g. `r12345` → `[r12345](https://vndb.org/r12345)`).
  """
  def clean_release_notes(nil), do: nil

  def clean_release_notes(notes) when is_binary(notes) do
    notes
    |> sanitize_utf8()
    |> VndbToMarkdown.convert()
    |> expand_vndb_relative_links()
    |> linkify_bare_release_ids()
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  def clean_release_notes(_), do: nil

  # Expand VNDB-relative paths in Markdown links to full URLs
  # Covers all VNDB entity types: v(n), r(elease), c(har), p(roducer), s(taff),
  # g(tag), t(rait), i(mage)
  # e.g. [text](/r12345) → [text](https://vndb.org/r12345)
  defp expand_vndb_relative_links(text) do
    String.replace(text, ~r/\]\(\/([vrpcsgti]\d+)\)/, "](https://vndb.org/\\1)")
  end

  # Linkify bare release IDs not already inside a Markdown link
  # e.g. r12345 → [r12345](https://vndb.org/r12345)
  defp linkify_bare_release_ids(text) do
    String.replace(text, ~r/(?<!\(https:\/\/vndb\.org\/)(r\d{2,})/, "[\\1](https://vndb.org/\\1)")
  end

  # ── Character Mappings ─────────────────────────────────────────────────────

  @doc """
  VNDB API `sex` field is an array: [non_spoiler, spoiler_value].
  Each value is "m", "f", "b", or nil.
  Returns {sex_atom, spoiler_sex_atom}.
  """
  def parse_api_sex_field(nil), do: {nil, nil}
  def parse_api_sex_field([]), do: {nil, nil}

  def parse_api_sex_field([non_spoiler | rest]) do
    spoiler = List.first(rest)
    {map_sex(non_spoiler), map_sex(spoiler)}
  end

  def parse_api_sex_field(_), do: {nil, nil}

  def map_sex("m"), do: :male
  def map_sex("f"), do: :female
  def map_sex("b"), do: :both
  def map_sex("n"), do: :unknown
  def map_sex(_), do: nil

  @doc """
  VNDB API `gender` field is an array: [non_spoiler, spoiler_value].
  Each value is "m", "f", "o", "a", or nil.
  Returns {gender_atom, spoiler_gender_atom}.
  """
  def parse_api_gender_field(nil), do: {nil, nil}
  def parse_api_gender_field([]), do: {nil, nil}

  def parse_api_gender_field([non_spoiler | rest]) do
    spoiler = List.first(rest)
    {map_gender(non_spoiler), map_gender(spoiler)}
  end

  def parse_api_gender_field(_), do: {nil, nil}

  def map_gender("m"), do: :male
  def map_gender("f"), do: :female
  def map_gender("o"), do: :other
  def map_gender("a"), do: :ambiguous
  def map_gender(_), do: nil

  def map_blood_type("a"), do: :a
  def map_blood_type("b"), do: :b
  def map_blood_type("ab"), do: :ab
  def map_blood_type("o"), do: :o
  def map_blood_type(_), do: nil

  def map_character_role("main"), do: :main
  def map_character_role("primary"), do: :primary
  def map_character_role("side"), do: :side
  def map_character_role(_), do: :appears

  def nullify_zero(0), do: nil
  def nullify_zero(val), do: val

  # ── Tag Mappings ───────────────────────────────────────────────────────────

  @doc """
  Filter out weak/irrelevant tags. VNDB tag rating is -3 to 3 scale.
  Tags with rating < 1.0 are considered weak. Matches import_vndb_tags.exs threshold.
  """
  def relevant_tag?(rating) when is_number(rating), do: rating >= 1.0
  def relevant_tag?(_), do: false

  def map_spoiler_level(0), do: :none
  def map_spoiler_level(1), do: :minor
  def map_spoiler_level(2), do: :major
  def map_spoiler_level(_), do: :none

  def map_tag_category("cont"), do: :content
  def map_tag_category("ero"), do: :sexual
  def map_tag_category("tech"), do: :technical
  def map_tag_category(_), do: :content

  @doc """
  Compute tag relevance score. Delegates to existing TagRelevance module.
  """
  def compute_tag_relevance(avg_vote, vote_count) do
    TagRelevance.vndb_relevance(avg_vote, vote_count, 10.0)
  end

  # ── Relation Mappings ──────────────────────────────────────────────────────

  def map_relation_type("seq"), do: "sequel"
  def map_relation_type("preq"), do: "prequel"
  def map_relation_type("fan"), do: "fandisc"
  def map_relation_type("orig"), do: "original"
  def map_relation_type("side"), do: "side_story"
  def map_relation_type("par"), do: "parent_story"
  def map_relation_type("set"), do: "same_setting"
  def map_relation_type("alt"), do: "alternative"
  def map_relation_type("char"), do: "shares_characters"
  def map_relation_type("ser"), do: "same_series"
  def map_relation_type(other), do: other

  # ── Producer Mappings ──────────────────────────────────────────────────────

  def map_producer_type("co"), do: "company"
  def map_producer_type("in"), do: "individual"
  def map_producer_type("ng"), do: "amateur"
  def map_producer_type(other), do: other

  # ── Shared Utilities ───────────────────────────────────────────────────────

  @doc """
  Sanitize strings for invalid UTF-8 sequences.
  Attempts latin1→utf8 conversion, falls back to stripping non-ASCII.
  """
  def sanitize_utf8(nil), do: nil

  def sanitize_utf8(str) when is_binary(str) do
    if String.valid?(str) do
      str
    else
      case :unicode.characters_to_binary(str, :latin1, :utf8) do
        binary when is_binary(binary) ->
          binary

        _ ->
          str
          |> :binary.bin_to_list()
          |> Enum.filter(fn byte -> byte <= 127 end)
          |> :binary.list_to_bin()
      end
    end
  end

  def sanitize_utf8(_), do: nil

  @doc """
  Force string to ASCII (drop non-ASCII bytes). Used for tag slugs.
  """
  def force_ascii(nil), do: nil

  def force_ascii(text) when is_binary(text) do
    for <<byte <- text>>, byte < 128, into: "", do: <<byte>>
  end

  # ── API Data Extraction ──────────────────────────────────────────────────

  @doc "Extract image flags from a VN API response map."
  def image_flags_from_vn(%{"image" => %{"sexual" => s, "votecount" => vc}}),
    do: compute_image_flags(s, vc)

  def image_flags_from_vn(_), do: {false, false}

  @doc "Extract image flags from an image sub-object."
  def image_flags_from_image(%{"sexual" => s, "votecount" => vc}),
    do: compute_image_flags(s, vc)

  def image_flags_from_image(_), do: {false, false}

  @doc "Extract image URL from a VN API response."
  def image_url_from_vn(%{"image" => %{"url" => url}}) when is_binary(url), do: url
  def image_url_from_vn(_), do: nil

  @doc "Extract image URL from an image sub-object."
  def image_url_from_image(%{"url" => url}) when is_binary(url), do: url
  def image_url_from_image(_), do: nil

  @doc "Parse VNDB birthday [month, day] → day integer."
  def parse_birthday([_month, day]) when is_integer(day), do: day
  def parse_birthday(_), do: nil

  @doc "Nullify empty strings."
  def nullify_empty(""), do: nil
  def nullify_empty(nil), do: nil
  def nullify_empty(val), do: val

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp non_blank?(nil), do: false
  defp non_blank?(""), do: false
  defp non_blank?(s) when is_binary(s), do: String.trim(s) != ""
  defp non_blank?(_), do: false

  @doc """
  Returns true when the string is composed entirely of Latin letters, digits,
  punctuation, symbols, and whitespace (including fullwidth variants).
  Used to detect Japanese titles that are already romanized (e.g. "BUNNYBLACK2").
  """
  def latin_script?(text) when is_binary(text) do
    String.match?(text, ~r/^[\p{Latin}\p{Nd}\p{P}\p{Z}\p{S}]+$/u)
  end

  @doc """
  Parse aliases and keep only Latin-script entries.

  Handles both formats:
  - Newline-separated string (VNDB dump `vn.alias` column)
  - List of strings (VNDB API v2 `aliases` field)
  """
  def parse_latin_aliases(nil), do: []
  def parse_latin_aliases(""), do: []

  def parse_latin_aliases(alias_text) when is_binary(alias_text) do
    alias_text
    |> String.split("\n", trim: true)
    |> filter_latin_aliases()
  end

  def parse_latin_aliases(aliases) when is_list(aliases) do
    filter_latin_aliases(aliases)
  end

  def parse_latin_aliases(_), do: []

  defp filter_latin_aliases(aliases) do
    aliases
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&latin_script?/1)
    |> Enum.map(&sanitize_utf8/1)
    |> Enum.reject(&is_nil/1)
  end
end

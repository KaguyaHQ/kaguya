defmodule Kaguya.SearchIndex do
  @moduledoc """
  Handles incremental add-or-update of documents in Meilisearch.
  """

  alias Req
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Characters.Character
  alias Kaguya.Producers.Producer

  # read once at compile time
  @enabled Application.compile_env!(:kaguya, :enable_meili_indexing)

  # ───────────────
  # PUBLIC – UPSERT
  # ───────────────

  @doc "Add or update one *or* many VisualNovel structs (MUST be pre-loaded with producers)."
  def index_visual_novels(%VisualNovel{} = vn), do: index_visual_novels([vn])
  def index_visual_novels([]), do: :ok

  def index_visual_novels(vns) when is_list(vns),
    do: do_index("visual_novels", vns, &transform_visual_novel/1)

  @doc "Add or update one *or* many Character structs."
  def index_characters(%Character{} = c), do: index_characters([c])
  def index_characters([]), do: :ok

  def index_characters(characters) when is_list(characters),
    do: do_index("characters", characters, &transform_character/1)

  @doc "Add or update one *or* many Producer structs."
  def index_producers(%Producer{} = p), do: index_producers([p])
  def index_producers([]), do: :ok

  def index_producers(producers) when is_list(producers),
    do: do_index("producers", producers, &transform_producer/1)

  # ───────────────
  # PUBLIC – SETTINGS
  # ───────────────

  @doc "Apply searchable attributes and ranking rules for the visual_novels index."
  def configure_visual_novels_index do
    if @enabled do
      Req.patch!(meili_client(),
        url: "/indexes/visual_novels/settings",
        json: %{
          searchableAttributes: [
            "prefix_1",
            "prefix_2",
            "prefix_3",
            "prefix_4",
            "title",
            "original_titles",
            "aliases",
            "producers"
          ],
          rankingRules: [
            "words",
            "typo",
            "attribute",
            "proximity",
            "vndb_vote_count:desc",
            "exactness"
          ],
          filterableAttributes: ["title_category"]
        }
      )
    end

    :ok
  end

  @doc "Apply searchable attributes and ranking rules for the producers index."
  def configure_producers_index do
    if @enabled do
      Req.patch!(meili_client(),
        url: "/indexes/producers/settings",
        json: %{
          searchableAttributes: ["name"],
          rankingRules: [
            "words",
            "typo",
            "proximity",
            "exactness"
          ]
        }
      )
    end

    :ok
  end

  # ───────────────
  # PUBLIC – DELETE
  # ───────────────

  def remove_visual_novel(id), do: delete_document("visual_novels", id)
  def remove_visual_novels([]), do: :ok
  def remove_visual_novels(ids) when is_list(ids), do: delete_documents("visual_novels", ids)

  def remove_character(id), do: delete_document("characters", id)
  def remove_characters([]), do: :ok
  def remove_characters(ids) when is_list(ids), do: delete_documents("characters", ids)

  def remove_producer(id), do: delete_document("producers", id)
  def remove_producers([]), do: :ok
  def remove_producers(ids) when is_list(ids), do: delete_documents("producers", ids)

  @doc """
  Sends a list of documents to Meilisearch's add-or-update route.
  If a document doesn't exist yet, it's added. If it does exist,
  only the provided fields are updated.

  https://www.meilisearch.com/docs/reference/api/documents#add-or-update-documents
  """
  def add_or_update_documents(index_name, documents) when is_list(documents) do
    client = meili_client()
    # PUT /indexes/:index_uid/documents => Add or Update documents
    Req.put!(client, url: "/indexes/#{index_name}/documents", json: documents)
    :ok
  end

  # ───────────────
  # INTERNAL
  # ───────────────

  defp do_index(index_name, structs, transform_fun) do
    if @enabled do
      docs = Enum.map(structs, transform_fun)
      Req.put!(meili_client(), url: "/indexes/#{index_name}/documents", json: docs)
    end

    :ok
  end

  defp delete_document(index_name, id) do
    if @enabled do
      Req.delete!(meili_client(), url: "/indexes/#{index_name}/documents/#{id}")
    end

    :ok
  end

  defp delete_documents(index_name, ids) do
    if @enabled do
      Req.post!(meili_client(),
        url: "/indexes/#{index_name}/documents/delete-batch",
        json: ids
      )
    end

    :ok
  end

  # -------------------
  # Transform Functions
  # -------------------

  # -------------------
  # Prefix Helpers
  # -------------------

  # Decorative symbols that act as word dividers in VN titles (e.g. Mama×Holic, Puru☆Puru).
  # We generate TWO prefix variants and merge both into the prefix lists:
  #   1. Original (strip all non-alnum) — preserves concatenated forms like "purupuru", "bugbug"
  #   2. Split (replace decorative symbols with space first) — adds word-boundary forms like "puru puru"
  # Other punctuation (. : ' -) is always stripped to preserve useful concatenation
  # for acronyms (D.C.), Re:-prefixes (Re:Zero), and romanizations (Jun'ai).
  @decorative_dividers ~r/[×☆★♥♡♪○●◆◇■□△▽▲▼]/u

  defp prefix_fields(raw_title) do
    base =
      raw_title
      |> strip_leading_article()
      |> String.downcase()

    # Original: strip all non-alnum (keeps "purupuru", "mamaholic", etc.)
    stripped = base |> String.replace(~r/[^\p{L}\p{Nd}\s]/u, "")
    # Split: replace decorative dividers with space first, then strip the rest
    split =
      base
      |> String.replace(@decorative_dividers, " ")
      |> String.replace(~r/[^\p{L}\p{Nd}\s]/u, "")

    stripped_words = String.split(stripped, ~r/\s+/u, trim: true)
    split_words = String.split(split, ~r/\s+/u, trim: true)

    # Only emit the split variant if it actually differs (has a decorative divider)
    word_lists =
      if stripped_words == split_words, do: [stripped_words], else: [stripped_words, split_words]

    {
      word_lists |> Enum.map(&Enum.at(&1, 0)) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      word_lists |> Enum.map(&prefix_join(&1, 2)) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      word_lists |> Enum.map(&prefix_join(&1, 3)) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      word_lists |> Enum.map(&prefix_join(&1, 4)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    }
  end

  defp prefix_join(words, n) do
    if length(words) >= n, do: words |> Enum.take(n) |> Enum.join(" "), else: nil
  end

  defp strip_leading_article(title) do
    Regex.replace(~r/^(?:the|a|an)\s+/i, title, "")
  end

  defp transform_visual_novel(vn) do
    nsfw = Map.get(vn, :is_image_nsfw) || false
    suggestive = Map.get(vn, :is_image_suggestive) || false
    cover_needs_blur = nsfw || suggestive

    # 1) Aggregate developer names only. Publisher-only VNs intentionally get
    # no producer line in search, matching the VN page.
    names =
      vn
      |> producer_names(["developer", "developer_publisher"])
      |> Enum.uniq()

    producers_string = Enum.join(names, ", ")

    # 2) Collect all searchable titles: main title + all latin romanizations from vn_titles
    vn_titles = Map.get(vn, :vn_titles) || []

    alt_latins =
      vn_titles
      |> Enum.map(& &1.latin)
      |> Enum.reject(&(is_nil(&1) or &1 == vn.title))
      |> Enum.uniq()

    all_titles = [vn.title | alt_latins]

    # 2b) Collect original Japanese titles for native-script search
    original_titles =
      vn_titles
      |> Enum.filter(&(&1.lang == "ja"))
      |> Enum.map(& &1.title)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # 2c) For titles containing ×, add a normalized variant with "x" so that
    # searching "mama x holic" matches all 3 tokens (× is a Meilisearch separator,
    # so the raw title only yields ["mama", "holic"] — the "x" token goes unmatched).
    cross_aliases =
      all_titles
      |> Enum.filter(&String.contains?(&1, "×"))
      |> Enum.map(&String.replace(&1, "×", " x "))
      |> Enum.map(&String.replace(&1, ~r/\s+/, " "))
      |> Enum.map(&String.trim/1)

    # 3) Compute merged prefixes from all title variants
    all_prefix_tuples = Enum.map(all_titles, &prefix_fields/1)

    prefix_1 = all_prefix_tuples |> Enum.map(&elem(&1, 0)) |> merge_prefix_list()
    prefix_2 = all_prefix_tuples |> Enum.map(&elem(&1, 1)) |> merge_prefix_list()
    prefix_3 = all_prefix_tuples |> Enum.map(&elem(&1, 2)) |> merge_prefix_list()
    prefix_4 = all_prefix_tuples |> Enum.map(&elem(&1, 3)) |> merge_prefix_list()

    # 4) Build doc - pre-build image URL from primary_image_id (medium 256w) or temp_image_url
    image_url =
      build_vn_image_url(vn.primary_image_id, vn.temp_image_url)

    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      vndb_vote_count: vn.vndb_vote_count || 0,
      image_url: image_url,
      cover_needs_blur: cover_needs_blur,
      has_ero: cover_needs_blur,
      primary_image_id: vn.primary_image_id,
      is_image_nsfw: nsfw,
      is_image_suggestive: suggestive,
      producers: producers_string,
      prefix_1: prefix_1,
      prefix_2: prefix_2,
      prefix_3: prefix_3,
      prefix_4: prefix_4,
      original_titles: original_titles,
      aliases: ((Map.get(vn, :aliases) || []) ++ cross_aliases) |> Enum.uniq(),
      title_category: to_string(Map.get(vn, :title_category) || :vn)
    }
  end

  defp merge_prefix_list(prefixes) do
    prefixes
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      list -> list
    end
  end

  # Returns producer names respecting role filters. If role_filter is :all,
  # falls back to plain producers when vn_producers are not preloaded.
  # For developer roles, only keeps producers from the earliest release.
  defp producer_names(vn, role_filter) do
    cond do
      Map.has_key?(vn, :vn_producers) and vn.vn_producers ->
        filtered =
          vn.vn_producers
          |> Enum.filter(fn vp ->
            case role_filter do
              :all -> true
              roles when is_list(roles) -> vp.role in roles
            end
          end)

        # For developer roles, only keep those from the earliest release
        filtered = filter_to_earliest_release(filtered, role_filter)

        filtered
        |> Enum.sort_by(fn vp ->
          role_priority =
            case vp.role do
              "developer_publisher" -> 0
              "developer" -> 1
              "publisher" -> 2
              _ -> 3
            end

          # ~D[9999-12-31] pushes nil dates to the end
          date = vp.earliest_release_date || ~D[9999-12-31]

          {role_priority, date, (vp.producer && vp.producer.name) || ""}
        end)
        |> Enum.map(& &1.producer)

      vn.producers && role_filter == :all ->
        vn.producers

      true ->
        []
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.name)
  end

  defp filter_to_earliest_release(vp_list, roles) when is_list(roles) do
    if "developer" in roles or "developer_publisher" in roles do
      min_date =
        vp_list
        |> Enum.map(& &1.earliest_release_date)
        |> Enum.reject(&is_nil/1)
        |> Enum.min(Date, fn -> nil end)

      if min_date do
        Enum.filter(vp_list, &(&1.earliest_release_date == min_date))
      else
        vp_list
      end
    else
      vp_list
    end
  end

  defp filter_to_earliest_release(vp_list, :all), do: vp_list

  defp build_vn_image_url(nil, nil), do: nil
  defp build_vn_image_url(nil, temp_url), do: temp_url

  defp build_vn_image_url(image_id, _temp),
    do: "https://images.kaguya.io/visual_novels/#{image_id}-256w.webp"

  defp transform_character(character) do
    %{
      id: character.id,
      name: character.name,
      slug: character.slug,
      primary_image_id: character.primary_image_id,
      vndb_image_id: character.vndb_image_id,
      is_image_nsfw: character.is_image_nsfw || false,
      is_image_suggestive: character.is_image_suggestive || false
    }
  end

  defp transform_producer(producer) do
    %{
      id: producer.id,
      name: producer.name,
      slug: producer.slug,
      primary_image_id: producer.primary_image_id,
      is_image_nsfw: producer.is_image_nsfw || false,
      is_image_suggestive: producer.is_image_suggestive || false
    }
  end

  # -------------
  # Meili Client
  # -------------

  defp meili_client do
    config = Application.fetch_env!(:kaguya, :meilisearch)
    meili_url = config[:base_url]
    meili_key = config[:master_key]

    Req.new(
      base_url: meili_url,
      headers: [
        {"Authorization", "Bearer #{meili_key}"},
        {"Content-Type", "application/json"}
      ]
    )
  end

  @dialyzer [
    {:nowarn_function, configure_visual_novels_index: 0},
    {:nowarn_function, configure_producers_index: 0},
    {:nowarn_function, transform_visual_novel: 1},
    {:nowarn_function, transform_character: 1},
    {:nowarn_function, transform_producer: 1},
    {:nowarn_function, prefix_fields: 1},
    {:nowarn_function, prefix_join: 2},
    {:nowarn_function, strip_leading_article: 1},
    {:nowarn_function, do_index: 3},
    {:nowarn_function, delete_document: 2},
    {:nowarn_function, delete_documents: 2}
  ]
end

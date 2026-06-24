defmodule KaguyaWeb.VNLive.Edit.Form do
  @moduledoc false

  alias Kaguya.VisualNovels

  @type map_form :: %{required(String.t()) => term()}
  @type normalized_form :: map()

  def empty_form do
    %{
      "description" => "",
      "aliases" => "",
      "development_status" => "",
      "length_category" => "",
      "original_language" => "",
      "release_date" => "",
      "min_age" => "",
      "has_ero" => false,
      "is_avn" => false,
      "title_category" => "vn",
      "primary_cover_id" => "",
      "summary" => "",
      "titles" => [empty_title()],
      "relations" => [],
      "screenshots" => [],
      "covers" => [],
      "is_hidden" => false,
      "is_locked" => false
    }
  end

  def empty_title do
    %{"lang" => "", "title" => "", "latin" => "", "official" => false}
  end

  def from_visual_novel(vn, covers, screenshots) do
    %{
      "description" => vn.description || "",
      "aliases" => Enum.join(vn.aliases || [], "\n"),
      "development_status" => vn.development_status || "",
      "length_category" => vn.length_category || "",
      "original_language" => vn.original_language || "",
      "release_date" => if(vn.release_date, do: Date.to_iso8601(vn.release_date), else: ""),
      "min_age" => if(vn.min_age, do: Integer.to_string(vn.min_age), else: ""),
      "has_ero" => vn.has_ero == true,
      "is_avn" => vn.is_avn == true,
      "title_category" => if(vn.title_category, do: to_string(vn.title_category), else: "vn"),
      "primary_cover_id" => vn.primary_image_id || "",
      "summary" => "",
      "titles" =>
        vn.vn_titles
        |> Enum.sort_by(&{&1.lang || "", &1.title || ""})
        |> Enum.map(fn title ->
          %{
            "lang" => title.lang || "",
            "title" => title.title || "",
            "latin" => title.latin || "",
            "official" => title.official == true
          }
        end)
        |> ensure_titles_present(vn),
      "relations" =>
        vn.vn_relations
        |> Enum.sort_by(fn relation ->
          {(relation.related_vn && relation.related_vn.title) || "", relation.related_vn_id || ""}
        end)
        |> Enum.map(fn relation ->
          %{
            "related_vn_id" => relation.related_vn_id,
            "related_vn_slug" => (relation.related_vn && relation.related_vn.slug) || "",
            "related_vn_title" =>
              (relation.related_vn && relation.related_vn.title) || relation.related_vn_id,
            "relation_type" => relation.relation_type || "sequel",
            "is_official" => relation.is_official != false
          }
        end),
      "screenshots" =>
        Enum.map(screenshots, fn screenshot ->
          %{
            "id" => screenshot.id,
            "thumbnail_url" => VisualNovels.build_screenshot_urls(screenshot.id)[:medium],
            "is_nsfw" => screenshot.is_nsfw == true,
            "is_brutal" => screenshot.is_brutal == true,
            "removed" => false
          }
        end),
      "covers" =>
        Enum.map(covers, fn cover ->
          %{
            "id" => cover.id,
            "thumbnail_url" => VisualNovels.build_image_urls(cover.id)[:large],
            "is_image_nsfw" => cover.is_image_nsfw == true,
            "removed" => false
          }
        end),
      "is_hidden" => not is_nil(vn.hidden_at),
      "is_locked" => vn.is_locked || false
    }
  end

  def normalize(attrs, current_form) when is_map(attrs) and is_map(current_form) do
    %{
      "description" => normalize_text(Map.get(attrs, "description", current_form["description"])),
      "aliases" => Map.get(attrs, "aliases", current_form["aliases"]) |> to_string(),
      "development_status" =>
        normalize_text(Map.get(attrs, "development_status", current_form["development_status"])),
      "length_category" =>
        normalize_text(Map.get(attrs, "length_category", current_form["length_category"])),
      "original_language" =>
        normalize_text(Map.get(attrs, "original_language", current_form["original_language"])),
      "release_date" =>
        normalize_text(Map.get(attrs, "release_date", current_form["release_date"])),
      "min_age" => normalize_text(Map.get(attrs, "min_age", current_form["min_age"])),
      "has_ero" => truthy?(Map.get(attrs, "has_ero", current_form["has_ero"])),
      "is_avn" => truthy?(Map.get(attrs, "is_avn", current_form["is_avn"])),
      "title_category" =>
        normalize_text(Map.get(attrs, "title_category", current_form["title_category"])),
      "primary_cover_id" =>
        normalize_text(Map.get(attrs, "primary_cover_id", current_form["primary_cover_id"])),
      "summary" => normalize_text(Map.get(attrs, "summary", current_form["summary"])),
      "titles" => normalize_titles(Map.get(attrs, "titles"), current_form["titles"]),
      "relations" => normalize_relations(Map.get(attrs, "relations"), current_form["relations"]),
      "screenshots" =>
        normalize_screenshots(Map.get(attrs, "screenshots"), current_form["screenshots"]),
      "covers" => normalize_covers(Map.get(attrs, "covers"), current_form["covers"]),
      "is_hidden" => truthy?(Map.get(attrs, "is_hidden", current_form["is_hidden"])),
      "is_locked" => truthy?(Map.get(attrs, "is_locked", current_form["is_locked"]))
    }
    |> normalize_primary_cover()
  end

  @spec validate(map_form()) :: {:ok, [map()], String.t()} | {:error, String.t()}
  def validate(form) when is_map(form) do
    with {:ok, titles} <- validate_titles(form["titles"]),
         {:ok, summary} <- validate_summary(Map.get(form, "summary", "")) do
      {:ok, titles, summary}
    end
  end

  def validate(_), do: {:error, "Invalid payload."}

  def normalize_upload_error(%Ecto.Changeset{} = changeset), do: format_upload_error(changeset)
  def normalize_upload_error(reason) when is_binary(reason), do: reason
  def normalize_upload_error(reason), do: inspect(reason)

  def build_changes(original_form, form) do
    current =
      form
      |> form_to_changes(parse_titles(form["titles"]))

    original =
      original_form
      |> form_to_changes(parse_titles(original_form["titles"]))

    base =
      for {key, value} <- current, value != Map.get(original, key), into: %{}, do: {key, value}

    translate_mod_flag(base, form, original_form)
  end

  @doc """
  Builds the full attribute map for creating a new visual novel from a
  normalized form. Unlike `build_changes/2` (which diffs against an
  original), this emits every create-relevant field outright.

  Covers/screenshots are intentionally omitted — `VisualNovels.create_from_edit/1`
  does not attach images; they're added afterwards via the edit screen. The
  `:title` is derived by the context from `titles`/`original_language`.
  """
  def to_create_attrs(form) do
    %{
      description: blank_nil(form["description"]),
      aliases: parse_aliases(form["aliases"]),
      development_status: blank_nil(form["development_status"]),
      length_category: blank_nil(form["length_category"]),
      original_language: blank_nil(form["original_language"]),
      release_date: parse_date(form["release_date"]),
      min_age: parse_integer(form["min_age"]),
      has_ero: form["has_ero"] == true,
      is_avn: form["is_avn"] == true,
      title_category: parse_title_category(form["title_category"]),
      titles: parse_titles(form["titles"]),
      relations: relation_changes(form["relations"])
    }
  end

  # `form_to_changes` emits `is_hidden` as a boolean alongside `is_locked` so
  # the diff above can use plain equality. The schema column is `hidden_at`
  # (a datetime or nil), so translate at the boundary. `is_locked` is already
  # boolean-shaped so it passes through.
  defp translate_mod_flag(changes, form, original_form) do
    case Map.pop(changes, :is_hidden) do
      {nil, _} ->
        changes

      {_value, rest} ->
        # If is_hidden was in the diff, the value reflects the *form*'s desired
        # state. Translate to hidden_at: a fresh timestamp on transition into
        # hidden, nil on transition out.
        hidden_at =
          if Map.get(form, "is_hidden") and not Map.get(original_form, "is_hidden") do
            DateTime.utc_now() |> DateTime.truncate(:second)
          else
            nil
          end

        Map.put(rest, :hidden_at, hidden_at)
    end
  end

  def dirty_fields(original_form, form) do
    scalar_labels =
      [
        {"titles", "titles"},
        {"description", "description"},
        {"aliases", "aliases"},
        {"development_status", "development status"},
        {"length_category", "length"},
        {"original_language", "original language"},
        {"release_date", "release date"},
        {"min_age", "minimum age"},
        {"has_ero", "has erotic content"},
        {"is_avn", "is avn"},
        {"title_category", "category"}
      ]
      |> Enum.flat_map(fn {key, label} ->
        if Map.get(form, key) != Map.get(original_form, key), do: [label], else: []
      end)

    scalar_labels
    |> maybe_add_changed_label(
      "relations",
      relation_changes(form["relations"]),
      relation_changes(original_form["relations"])
    )
    |> maybe_add_changed_label(
      "screenshots",
      screenshot_state_signature(form["screenshots"]),
      screenshot_state_signature(original_form["screenshots"])
    )
    |> maybe_add_changed_label(
      "covers",
      cover_state_signature(form["covers"]),
      cover_state_signature(original_form["covers"])
    )
    |> maybe_add_changed_label(
      "primary cover",
      primary_cover_id(form),
      primary_cover_id(original_form)
    )
    |> maybe_add_changed_label(
      "visibility",
      form["is_hidden"],
      original_form["is_hidden"]
    )
    |> maybe_add_changed_label(
      "lock",
      form["is_locked"],
      original_form["is_locked"]
    )
  end

  def visible_relations(form), do: Enum.reject(form["relations"], &(&1["removed"] == true))
  def visible_screenshots(form), do: Enum.reject(form["screenshots"], &(&1["removed"] == true))
  def visible_covers(form), do: Enum.reject(form["covers"], &(&1["removed"] == true))

  def normalize_primary_cover(form) do
    if primary_cover_id(form) == "" and visible_covers(form) != [] do
      first_visible = visible_covers(form) |> List.first() |> Map.get("id", "")
      Map.put(form, "primary_cover_id", first_visible)
    else
      form
    end
  end

  def clear_primary_cover_if_removed(form, cover_id) do
    if form["primary_cover_id"] == cover_id do
      form |> Map.put("primary_cover_id", "") |> normalize_primary_cover()
    else
      form
    end
  end

  def ensure_titles_present([]), do: [empty_title()]
  def ensure_titles_present(titles), do: titles

  def ensure_titles_present([], vn) do
    [
      %{
        "lang" => vn.original_language || "",
        "title" => vn.title || "",
        "latin" => "",
        "official" => true
      }
    ]
  end

  def ensure_titles_present(titles, _vn), do: titles

  def add_relation(relations, relation, current_vn_id) do
    cond do
      relation["related_vn_id"] in [nil, "", current_vn_id] ->
        relations

      Enum.any?(relations, &(&1["related_vn_id"] == relation["related_vn_id"])) ->
        Enum.map(relations, fn row ->
          if row["related_vn_id"] == relation["related_vn_id"],
            do: Map.put(row, "removed", false),
            else: row
        end)

      true ->
        relations ++ [Map.put(relation, "removed", false)]
    end
  end

  def drop_index(items, index) do
    case Integer.parse(to_string(index)) do
      {target, ""} -> List.delete_at(items, target)
      _ -> items
    end
  end

  defp parse_titles(nil), do: []

  defp parse_titles(titles) do
    case validate_titles(titles) do
      {:ok, parsed} -> parsed
      {:error, _} -> []
    end
  end

  defp form_to_changes(form, titles) do
    %{
      description: blank_nil(form["description"]),
      aliases: parse_aliases(form["aliases"]),
      development_status: blank_nil(form["development_status"]),
      length_category: blank_nil(form["length_category"]),
      original_language: blank_nil(form["original_language"]),
      release_date: parse_date(form["release_date"]),
      min_age: parse_integer(form["min_age"]),
      has_ero: form["has_ero"] == true,
      is_avn: form["is_avn"] == true,
      title_category: parse_title_category(form["title_category"]),
      titles: titles,
      relations: relation_changes(form["relations"]),
      screenshots: screenshot_changes(form["screenshots"]),
      covers: cover_changes(form["covers"]),
      primary_cover_id: blank_nil(primary_cover_id(form)),
      removed_screenshot_ids: removed_ids(form["screenshots"]),
      removed_cover_ids: removed_ids(form["covers"]),
      # Boolean form of the moderation flags. `translate_mod_flag/3` (called
      # from build_changes after the diff) maps `is_hidden` → `hidden_at` so
      # diffing here can use plain equality on a stable shape.
      is_hidden: form["is_hidden"] == true,
      is_locked: form["is_locked"] == true
    }
    |> reject_empty_list(:removed_screenshot_ids)
    |> reject_empty_list(:removed_cover_ids)
    |> reject_nil(:primary_cover_id)
  end

  defp validate_titles(titles) when is_list(titles) do
    parsed =
      Enum.reduce_while(titles, [], fn row, acc ->
        lang = normalize_text(row["lang"])
        title = normalize_text(row["title"])
        latin = normalize_text(row["latin"])
        official = row["official"] == true

        cond do
          lang == "" and title == "" and latin == "" ->
            {:cont, acc}

          lang == "" or title == "" ->
            {:halt, {:error, "Each title row needs both a language and a title."}}

          true ->
            {:cont,
             acc ++ [%{lang: lang, title: title, latin: blank_nil(latin), official: official}]}
        end
      end)

    case parsed do
      {:error, _} = error -> error
      [] -> {:error, "Add at least one title before saving."}
      rows -> {:ok, rows}
    end
  end

  defp validate_titles(_), do: {:error, "Each title row needs both a language and a title."}

  defp normalize_titles(nil, current_titles), do: current_titles

  defp normalize_titles(titles, _current_titles) when is_map(titles) do
    titles
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} ->
      %{
        "lang" => normalize_text(Map.get(row, "lang")),
        "title" => normalize_text(Map.get(row, "title")),
        "latin" => normalize_text(Map.get(row, "latin")),
        "official" => truthy?(Map.get(row, "official"))
      }
    end)
    |> ensure_titles_present()
  end

  defp normalize_relations(nil, current_relations), do: current_relations

  defp normalize_relations(relations, _current_relations) when is_map(relations) do
    relations
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} ->
      %{
        "related_vn_id" => normalize_text(Map.get(row, "related_vn_id")),
        "related_vn_slug" => normalize_text(Map.get(row, "related_vn_slug")),
        "related_vn_title" => normalize_text(Map.get(row, "related_vn_title")),
        "relation_type" =>
          normalize_text(Map.get(row, "relation_type")) |> default_relation_type(),
        "is_official" => truthy?(Map.get(row, "is_official")),
        "removed" => false
      }
    end)
    |> Enum.reject(&(&1["related_vn_id"] == ""))
    |> Enum.uniq_by(& &1["related_vn_id"])
  end

  defp normalize_screenshots(nil, current_screenshots), do: current_screenshots

  defp normalize_screenshots(screenshots, current_screenshots) when is_map(screenshots) do
    screenshots
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} ->
      %{
        "id" => normalize_text(Map.get(row, "id")),
        "thumbnail_url" => normalize_text(Map.get(row, "thumbnail_url")),
        "is_nsfw" => truthy?(Map.get(row, "is_nsfw")),
        "is_brutal" => truthy?(Map.get(row, "is_brutal")),
        "removed" => false
      }
    end)
    |> merge_removed_flags(current_screenshots)
  end

  defp normalize_covers(nil, current_covers), do: current_covers

  defp normalize_covers(covers, current_covers) when is_map(covers) do
    covers
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} ->
      %{
        "id" => normalize_text(Map.get(row, "id")),
        "thumbnail_url" => normalize_text(Map.get(row, "thumbnail_url")),
        "is_image_nsfw" => truthy?(Map.get(row, "is_image_nsfw")),
        "removed" => false
      }
    end)
    |> merge_removed_flags(current_covers)
  end

  defp relation_changes(relations) do
    relations
    |> Enum.reject(&(&1["removed"] == true))
    |> Enum.map(fn relation ->
      %{
        related_vn_id: relation["related_vn_id"],
        relation_type: default_relation_type(relation["relation_type"]),
        is_official: relation["is_official"] == true
      }
    end)
  end

  defp screenshot_changes(screenshots) do
    screenshots
    |> Enum.reject(&(&1["removed"] == true))
    |> Enum.map(fn screenshot ->
      %{
        screenshot_id: screenshot["id"],
        is_nsfw: screenshot["is_nsfw"] == true,
        is_brutal: screenshot["is_brutal"] == true
      }
    end)
  end

  defp cover_changes(covers) do
    covers
    |> Enum.reject(&(&1["removed"] == true))
    |> Enum.map(fn cover ->
      %{cover_id: cover["id"], is_image_nsfw: cover["is_image_nsfw"] == true}
    end)
  end

  defp removed_ids(rows) do
    rows
    |> Enum.filter(&(&1["removed"] == true))
    |> Enum.map(& &1["id"])
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp primary_cover_id(form) do
    selected = normalize_text(form["primary_cover_id"])

    if selected != "" and Enum.any?(visible_covers(form), &(&1["id"] == selected)),
      do: selected,
      else: ""
  end

  defp maybe_add_changed_label(labels, _label, current, current), do: labels
  defp maybe_add_changed_label(labels, label, _current, _original), do: labels ++ [label]

  defp screenshot_state_signature(rows) do
    Enum.map(rows, fn row ->
      {row["id"], row["is_nsfw"], row["is_brutal"], row["removed"] == true}
    end)
  end

  defp cover_state_signature(rows) do
    Enum.map(rows, fn row -> {row["id"], row["is_image_nsfw"], row["removed"] == true} end)
  end

  defp merge_removed_flags(rows, current_rows) do
    removed_ids =
      current_rows
      |> Enum.filter(&(&1["removed"] == true))
      |> MapSet.new(& &1["id"])

    active_ids = MapSet.new(rows, & &1["id"])

    visible_rows =
      Enum.map(rows, fn row ->
        Map.put(row, "removed", MapSet.member?(removed_ids, row["id"]))
      end)

    removed_rows =
      current_rows
      |> Enum.filter(&(&1["removed"] == true and not MapSet.member?(active_ids, &1["id"])))

    visible_rows ++ removed_rows
  end

  defp parse_aliases(text) do
    text
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_integer(""), do: nil
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_title_category("nukige"), do: :nukige
  defp parse_title_category("adjacent"), do: :adjacent
  defp parse_title_category(""), do: nil
  defp parse_title_category(nil), do: nil
  defp parse_title_category(_value), do: :vn

  defp default_relation_type(""), do: "sequel"
  defp default_relation_type(nil), do: "sequel"
  defp default_relation_type(value), do: value

  defp validate_summary(summary) do
    summary = normalize_text(summary)

    if String.length(summary) >= 2 do
      {:ok, summary}
    else
      {:error, "Summary must be at least 2 characters."}
    end
  end

  defp normalize_text(nil), do: ""
  defp normalize_text(value), do: value |> to_string() |> String.trim()

  defp reject_empty_list(map, key) do
    if Map.get(map, key, []) == [], do: Map.delete(map, key), else: map
  end

  defp reject_nil(map, key) do
    if Map.get(map, key) == nil, do: Map.delete(map, key), else: map
  end

  defp truthy?(value) when value in [true, "true", "on", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  defp format_upload_error(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end

defmodule KaguyaWeb.Components.Profile.RevisionDiff do
  @moduledoc """
  Inline field-level diff components for profile contribution rows.

  Scalar fields render removed/added rows, long text gets word-level highlights,
  image scalar fields use enriched snapshot URLs, and collection rows render
  compact labels.
  """

  use KaguyaWeb, :html

  @enum_labels %{
    "development_status" => %{
      "finished" => "Finished",
      "in_development" => "In development",
      "cancelled" => "Cancelled"
    },
    "length_category" => %{
      "short" => "Short (< 2 hours)",
      "medium" => "Medium (10–30 hours)",
      "long" => "Long (30–50 hours)",
      "very_long" => "Very long (50+ hours)"
    },
    "title_category" => %{
      "vn" => "Visual novel",
      "nukige" => "Nukige",
      "adjacent" => "VN-adjacent"
    },
    "sex" => %{"male" => "Male", "female" => "Female", "both" => "Both", "unknown" => "Unknown"},
    "spoiler_sex" => %{
      "male" => "Male",
      "female" => "Female",
      "both" => "Both",
      "unknown" => "Unknown"
    },
    "gender" => %{
      "male" => "Male",
      "female" => "Female",
      "other" => "Other",
      "ambiguous" => "Ambiguous"
    },
    "spoiler_gender" => %{
      "male" => "Male",
      "female" => "Female",
      "other" => "Other",
      "ambiguous" => "Ambiguous"
    },
    "blood_type" => %{"a" => "A", "b" => "B", "ab" => "AB", "o" => "O"},
    "relation_type" => %{
      "sequel" => "Sequel",
      "prequel" => "Prequel",
      "fandisc" => "Fan disc",
      "original" => "Original game",
      "side_story" => "Side story",
      "parent_story" => "Parent story",
      "same_setting" => "Same setting",
      "alternative" => "Alternative version",
      "shares_characters" => "Shares characters",
      "same_series" => "Same series"
    },
    "role" => %{
      "main" => "Main character",
      "primary" => "Primary character",
      "side" => "Side character",
      "appears" => "Appears"
    }
  }

  @field_label %{
    "primary_image_id" => "Primary cover",
    "featured_screenshot_id" => "Featured screenshot",
    "is_image_nsfw" => "Cover NSFW",
    "is_image_suggestive" => "Cover suggestive",
    "is_cover_pinned" => "Cover pinned",
    "has_ero" => "Erotic content",
    "min_age" => "Minimum age",
    "minage" => "Age rating",
    "length_category" => "Length",
    "length_minutes" => "Length (minutes)",
    "development_status" => "Development status",
    "title_category" => "Category",
    "release_date" => "Release date",
    "release_type" => "Type",
    "original_language" => "Original language",
    "display_title" => "Display title",
    "latin_title" => "Latin title",
    "primary_vn_series_id" => "Series",
    "primary_series_position" => "Series position",
    "external_links" => "External links",
    "entries" => "Entries",
    "mtl_languages" => "MTL languages",
    "reso_x" => "Resolution width",
    "reso_y" => "Resolution height",
    "spoiler_sex" => "Sex (spoiler)",
    "spoiler_gender" => "Gender (spoiler)"
  }

  @image_scalar_fields MapSet.new(~w(primary_image_id featured_screenshot_id))
  @state_fields MapSet.new(~w(hidden_at is_locked))
  @long_text_fields MapSet.new(~w(description notes))

  @scalar_fields MapSet.new(~w(
    title description aliases development_status length_category length_minutes
    original_language release_date min_age has_ero title_category primary_image_id
    is_image_nsfw is_image_suggestive is_cover_pinned featured_screenshot_id
    primary_vn_series_id primary_series_position hidden_at is_locked name sex
    spoiler_sex gender spoiler_gender blood_type height weight age birthday bust
    waist hip cup_size producer_type language display_title latin_title release_type
    patch freeware official uncensored voiced minage engine platforms languages
    mtl_languages notes reso_x reso_y media producers
  ))

  @field_order %{
    visual_novel: ~w(
      title description aliases original_language release_date length_category
      length_minutes development_status title_category min_age has_ero is_image_nsfw
      is_image_suggestive primary_vn_series_id primary_series_position is_cover_pinned
    ),
    character: ~w(
      name description sex spoiler_sex gender spoiler_gender birthday age height
      weight bust waist hip cup_size blood_type is_image_nsfw is_image_suggestive
    ),
    producer: ~w(name description producer_type language),
    release: ~w(
      title display_title latin_title original_language release_date release_type
      minage voiced engine reso_x reso_y patch freeware official uncensored has_ero
      media notes
    ),
    series: ~w(name description)
  }

  @max_lcs_cells 250_000

  attr :diff, :list, default: []
  attr :current, :map, default: nil
  attr :previous, :map, default: nil
  attr :entity_type, :any, default: nil
  attr :current_user, :map, default: nil

  def inline_diff(assigns) do
    entries =
      assigns.diff
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and present?(value_of(&1, :field))))

    state_changed =
      Enum.any?(entries, &MapSet.member?(@state_fields, to_string(value_of(&1, :field))))

    ordered_entries =
      entries
      |> Enum.reject(&MapSet.member?(@state_fields, to_string(value_of(&1, :field))))
      |> order_entries(assigns.entity_type)

    assigns =
      assigns
      |> assign(:state_changed, state_changed)
      |> assign(:ordered_entries, ordered_entries)
      |> assign(:has_changes, state_changed or ordered_entries != [])

    ~H"""
    <ul :if={@has_changes} class="space-y-2">
      <li
        :if={@state_changed}
        class="bg-surface-elevated/30 border-border-divider overflow-hidden rounded-md border"
      >
        <header class="bg-surface-elevated/60 border-border-divider text-foreground-secondary border-b px-3 py-1.5 text-xs font-medium">
          State
        </header>
        <div class="space-y-1 px-3 py-2 text-xs">
          <.scalar_change
            field="_state"
            old_val={derive_state(value_of(@previous, :hist))}
            new_val={derive_state(value_of(@current, :hist))}
          />
        </div>
      </li>

      <.field_diff
        :for={entry <- @ordered_entries}
        entry={entry}
        current={@current}
        previous={@previous}
        current_user={@current_user}
      />
    </ul>

    <p :if={!@has_changes} class="text-foreground-tertiary text-xs">
      No field-level changes captured.
    </p>
    """
  end

  attr :entry, :map, required: true
  attr :current, :map, default: nil
  attr :previous, :map, default: nil
  attr :current_user, :map, default: nil

  defp field_diff(assigns) do
    field = to_string(value_of(assigns.entry, :field))
    old = value_of(assigns.entry, :old)
    new = value_of(assigns.entry, :new)

    assigns =
      assigns
      |> assign(:field, field)
      |> assign(:old, old)
      |> assign(:new, new)
      |> assign(:label, field_label(field))
      |> assign(:image_scalar, MapSet.member?(@image_scalar_fields, field))
      |> assign(
        :long_text,
        MapSet.member?(@long_text_fields, field) and is_binary(old) and is_binary(new)
      )
      |> assign(
        :scalar,
        MapSet.member?(@scalar_fields, field) and has_any_key?(assigns.entry, [:old, :new])
      )

    ~H"""
    <li class="bg-surface-elevated/30 border-border-divider overflow-hidden rounded-md border">
      <header class="bg-surface-elevated/60 border-border-divider text-foreground-secondary border-b px-3 py-1.5 text-xs font-medium">
        {@label}
      </header>
      <div class="space-y-1 px-3 py-2 text-xs">
        <%= cond do %>
          <% @image_scalar -> %>
            <.image_scalar_change
              field={@field}
              old_url={read_image_url(@previous, @field)}
              new_url={read_image_url(@current, @field)}
              old_id={@old}
              new_id={@new}
              current_user={@current_user}
            />
          <% @long_text -> %>
            <.long_text_change old_val={@old} new_val={@new} />
          <% @scalar -> %>
            <.scalar_change field={@field} old_val={@old} new_val={@new} />
          <% true -> %>
            <.collection_change
              added={value_of(@entry, :added)}
              removed={value_of(@entry, :removed)}
              changed={value_of(@entry, :changed)}
              current_user={@current_user}
            />
        <% end %>
      </div>
    </li>
    """
  end

  attr :old_val, :string, required: true
  attr :new_val, :string, required: true

  defp long_text_change(assigns) do
    assigns = assign(assigns, :chunks, inline_text_diff(assigns.old_val, assigns.new_val))

    ~H"""
    <div class="space-y-1">
      <.diff_row tone={:removed} prefix="−">
        <.text_chunk_row chunks={@chunks} side={:old} />
      </.diff_row>
      <.diff_row tone={:added} prefix="+">
        <.text_chunk_row chunks={@chunks} side={:new} />
      </.diff_row>
    </div>
    """
  end

  attr :chunks, :list, required: true
  attr :side, :atom, required: true

  defp text_chunk_row(assigns) do
    ~H"""
    <span class="font-sans text-[13px] leading-snug whitespace-pre-wrap">
      <%= for chunk <- @chunks do %>
        <span :if={chunk.type == :equal}>{chunk.text}</span>
        <span
          :if={@side == :old and chunk.type == :removed}
          class="text-foreground-tertiary bg-red-500/15 line-through"
        >
          {chunk.text}
        </span>
        <span
          :if={@side == :new and chunk.type == :added}
          class="text-foreground-primary bg-green-500/15"
        >
          {chunk.text}
        </span>
      <% end %>
    </span>
    """
  end

  attr :field, :string, required: true
  attr :old_url, :string, default: nil
  attr :new_url, :string, default: nil
  attr :old_id, :any, default: nil
  attr :new_id, :any, default: nil
  attr :current_user, :map, default: nil

  defp image_scalar_change(assigns) do
    ~H"""
    <div class="space-y-0.5">
      <.diff_row
        :if={!is_nil(@old_id)}
        tone={:removed}
        prefix="−"
        item={if @old_url, do: %{url: @old_url}}
        current_user={@current_user}
      >
        {if @old_url, do: "", else: format_scalar_value(@field, @old_id)}
      </.diff_row>
      <.diff_row
        :if={!is_nil(@new_id)}
        tone={:added}
        prefix="+"
        item={if @new_url, do: %{url: @new_url}}
        current_user={@current_user}
      >
        {if @new_url, do: "", else: format_scalar_value(@field, @new_id)}
      </.diff_row>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :old_val, :any, default: nil
  attr :new_val, :any, default: nil

  defp scalar_change(assigns) do
    ~H"""
    <div class="space-y-0.5">
      <.diff_row :if={!is_nil(@old_val)} tone={:removed} prefix="−">
        {format_scalar_value(@field, @old_val)}
      </.diff_row>
      <.diff_row :if={!is_nil(@new_val)} tone={:added} prefix="+">
        {format_scalar_value(@field, @new_val)}
      </.diff_row>
    </div>
    """
  end

  attr :added, :any, default: []
  attr :removed, :any, default: []
  attr :changed, :any, default: []
  attr :current_user, :map, default: nil

  defp collection_change(assigns) do
    visible = &visible_to?(&1, assigns.current_user)

    assigns =
      assigns
      |> assign(:added_items, Enum.filter(list_value(assigns.added), visible))
      |> assign(:removed_items, Enum.filter(list_value(assigns.removed), visible))
      |> assign(
        :changed_items,
        Enum.filter(list_value(assigns.changed), fn entry ->
          visible.(value_of(entry, :old)) and visible.(value_of(entry, :new))
        end)
      )

    ~H"""
    <div
      :if={@added_items != [] or @removed_items != [] or @changed_items != []}
      class="space-y-1"
    >
      <.diff_row
        :for={item <- @removed_items}
        tone={:removed}
        prefix="−"
        item={item}
        current_user={@current_user}
      />
      <.diff_row
        :for={item <- @added_items}
        tone={:added}
        prefix="+"
        item={item}
        current_user={@current_user}
      />
      <div :for={entry <- @changed_items} class="space-y-0.5">
        <.diff_row
          tone={:removed}
          prefix="−"
          item={value_of(entry, :old)}
          current_user={@current_user}
        />
        <.diff_row
          tone={:added}
          prefix="+"
          item={value_of(entry, :new)}
          current_user={@current_user}
        />
      </div>
    </div>

    <p
      :if={@added_items == [] and @removed_items == [] and @changed_items == []}
      class="text-foreground-tertiary"
    >
      No changes.
    </p>
    """
  end

  attr :tone, :atom, required: true, values: [:added, :removed]
  attr :prefix, :string, required: true
  attr :item, :any, default: nil
  attr :current_user, :map, default: nil
  slot :inner_block

  defp diff_row(assigns) do
    assigns =
      assigns
      |> assign(:url, image_url_of(assigns.item))
      |> assign(:label, short_item(assigns.item))
      |> assign(:nsfw_blur?, item_needs_blur?(assigns.item))

    ~H"""
    <div class={[
      "flex items-center gap-2 rounded px-2 py-1",
      @tone == :added && "bg-green-500/10 text-green-300",
      @tone == :removed && "bg-red-500/10 text-red-300"
    ]}>
      <span
        class={[
          "font-mono select-none",
          @tone == :added && "text-green-400",
          @tone == :removed && "text-red-400"
        ]}
        aria-hidden="true"
      >
        {@prefix}
      </span>
      <span
        :if={@url}
        class="ring-border-divider/40 relative inline-block aspect-3/4 h-10 shrink-0 overflow-hidden rounded ring-1"
      >
        <img
          src={@url}
          alt=""
          class="size-full object-cover"
          loading="lazy"
          decoding="async"
          data-nsfw-blur={if @nsfw_blur?, do: "1"}
          style={if @nsfw_blur?, do: "--nsfw-blur-size: 30;"}
        />
      </span>
      <span class="min-w-0 flex-1 font-mono text-xs wrap-break-word">
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@label}
        <% end %>
      </span>
    </div>
    """
  end

  defp order_entries(entries, entity_type) do
    order =
      entity_type
      |> normalize_entity_type()
      |> then(&Map.get(@field_order, &1, []))
      |> Enum.with_index()
      |> Map.new()

    Enum.sort_by(entries, fn entry ->
      Map.get(order, to_string(value_of(entry, :field)), 10_000)
    end)
  end

  defp normalize_entity_type("VISUAL_NOVEL"), do: :visual_novel
  defp normalize_entity_type("CHARACTER"), do: :character
  defp normalize_entity_type("PRODUCER"), do: :producer
  defp normalize_entity_type("RELEASE"), do: :release
  defp normalize_entity_type("SERIES"), do: :series

  defp normalize_entity_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> nil
  end

  defp normalize_entity_type(type) when is_atom(type), do: type
  defp normalize_entity_type(_), do: nil

  defp field_label(field) do
    Map.get(@field_label, field) ||
      field
      |> String.replace("_", " ")
      |> String.capitalize()
  end

  defp format_scalar_value(_field, value) when value in [nil, ""], do: "—"
  defp format_scalar_value(_field, true), do: "Yes"
  defp format_scalar_value(_field, false), do: "No"

  defp format_scalar_value(field, value) when is_atom(value) do
    format_scalar_value(field, to_string(value))
  end

  defp format_scalar_value(field, value) when is_binary(value) do
    get_in(@enum_labels, [field, value]) || value
  end

  defp format_scalar_value(_field, %Date{} = value), do: Date.to_iso8601(value)
  defp format_scalar_value(_field, %DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_scalar_value(_field, value) when is_number(value), do: to_string(value)

  defp format_scalar_value(field, value) when is_list(value) do
    if value == [] do
      "—"
    else
      Enum.map_join(value, ", ", &format_scalar_value(field, &1))
    end
  end

  defp format_scalar_value(_field, value), do: inspect(value)

  defp read_image_url(snapshot, field) do
    snapshot
    |> value_of(:hist)
    |> value_of("#{field}_url")
    |> case do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  defp derive_state(nil), do: "Normal"

  defp derive_state(hist) do
    hidden = present?(value_of(hist, :hidden_at))
    locked = value_of(hist, :is_locked) == true

    cond do
      hidden and locked -> "Hidden + Locked"
      hidden -> "Hidden"
      locked -> "Locked"
      true -> "Normal"
    end
  end

  defp image_url_of(item) when is_map(item) do
    case value_of(item, :url) do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  defp image_url_of(_), do: nil

  defp short_item(nil), do: "—"
  defp short_item(value) when is_binary(value), do: value
  defp short_item(value) when is_number(value), do: to_string(value)
  defp short_item(value) when is_atom(value), do: to_string(value)
  defp short_item(%Date{} = value), do: Date.to_iso8601(value)

  defp short_item(%{} = item) do
    cond do
      # Title row: `[en] Title / Latin (unofficial)` — mirrors prod's `formatTitle`.
      title_object?(item) ->
        format_title_object(item)

      # Relation row: `[official] Sequel: Name` — mirrors prod's `formatRelation`.
      relation_object?(item) ->
        format_relation_object(item)

      # Cast row: `Main character: Name (spoiler 2)` — mirrors prod's `formatCast`.
      cast_object?(item) ->
        format_cast_object(item)

      # VN appearance row (on a character snapshot) — mirrors `formatAppearance`.
      appearance_object?(item) ->
        format_appearance_object(item)

      # Release producer row: `Developer: Name` — mirrors `formatReleaseProducer`.
      release_producer_object?(item) ->
        format_release_producer_object(item)

      # External link row: `Label: value` / `Site: value` — mirrors `formatExternalLink`.
      external_link_object?(item) ->
        format_external_link_object(item)

      # Series entry row: `1: VN title` — mirrors `formatSeriesEntry`.
      series_entry_object?(item) ->
        format_series_entry_object(item)

      present?(value_of(item, :producer_name)) ->
        to_string(value_of(item, :producer_name))

      present?(value_of(item, :title)) ->
        to_string(value_of(item, :title))

      present?(value_of(item, :name)) ->
        to_string(value_of(item, :name))

      present?(value_of(item, :site)) and present?(value_of(item, :value)) ->
        "#{value_of(item, :site)}: #{value_of(item, :value)}"

      image_identity?(item) ->
        image_flags(item)

      true ->
        inspect(item)
    end
  end

  defp short_item(value), do: inspect(value)

  # ── Object shape detection ─────────────────────────────────────────

  defp title_object?(item) do
    present?(value_of(item, :lang)) and present?(value_of(item, :title))
  end

  defp relation_object?(item) do
    present?(value_of(item, :related_vn_id)) or present?(value_of(item, :related_vn_title)) or
      (present?(value_of(item, :relation_type)) and not present?(value_of(item, :visual_novel_id)))
  end

  defp cast_object?(item) do
    present?(value_of(item, :character_id)) or present?(value_of(item, :character_name))
  end

  defp appearance_object?(item) do
    present?(value_of(item, :visual_novel_id)) or present?(value_of(item, :visual_novel_title))
  end

  defp release_producer_object?(item) do
    present?(value_of(item, :producer_id)) and
      (present?(value_of(item, :role)) or present?(value_of(item, :developer)) or
         present?(value_of(item, :publisher)))
  end

  defp external_link_object?(item) do
    (present?(value_of(item, :site)) or present?(value_of(item, :label))) and
      (present?(value_of(item, :value)) or present?(value_of(item, :url)))
  end

  defp series_entry_object?(item) do
    present?(value_of(item, :position)) and
      (present?(value_of(item, :visual_novel_id)) or present?(value_of(item, :visual_novel_title)))
  end

  # ── Snapshot object formatters ──

  defp format_title_object(item) do
    lang = value_of(item, :lang) || "?"
    title = value_of(item, :title)
    latin = value_of(item, :latin)
    official = value_of(item, :official)

    base = "[#{lang}] #{title}"
    base = if present?(latin), do: base <> " / " <> to_string(latin), else: base
    if official == false, do: base <> " (unofficial)", else: base
  end

  defp format_relation_object(item) do
    prefix = if value_of(item, :is_official), do: "official", else: "unofficial"
    rtype = format_scalar_value("relation_type", value_of(item, :relation_type))
    rtype = if rtype in [nil, "", "—"], do: "?", else: rtype

    name =
      value_of(item, :related_vn_title) ||
        short_id(value_of(item, :related_vn_id)) ||
        "?"

    "[#{prefix}] #{rtype}: #{name}"
  end

  defp format_cast_object(item) do
    role = format_scalar_value("role", value_of(item, :role))
    role = if role in [nil, "", "—"], do: "?", else: role

    name =
      value_of(item, :character_name) ||
        short_id(value_of(item, :character_id)) ||
        "?"

    spoiler = value_of(item, :spoiler_level)
    base = "#{role}: #{name}"
    if is_integer(spoiler) and spoiler > 0, do: base <> " (spoiler #{spoiler})", else: base
  end

  defp format_appearance_object(item) do
    name =
      value_of(item, :visual_novel_title) ||
        short_id(value_of(item, :visual_novel_id)) ||
        "?"

    role = format_scalar_value("role", value_of(item, :role))
    role = if role in [nil, "", "—"], do: "?", else: role

    spoiler = value_of(item, :spoiler_level)
    base = "#{role}: #{name}"
    if is_integer(spoiler) and spoiler > 0, do: base <> " (spoiler #{spoiler})", else: base
  end

  defp format_release_producer_object(item) do
    name =
      value_of(item, :producer_name) ||
        short_id(value_of(item, :producer_id)) ||
        "?"

    role = release_producer_role(item)
    "#{role}: #{name}"
  end

  defp release_producer_role(item) do
    case value_of(item, :role) do
      "developer_publisher" ->
        "Developer + Publisher"

      "developer" ->
        "Developer"

      "publisher" ->
        "Publisher"

      role when is_binary(role) and role != "" ->
        role

      _ ->
        flags =
          [
            if(value_of(item, :developer), do: "Developer"),
            if(value_of(item, :publisher), do: "Publisher")
          ]
          |> Enum.reject(&is_nil/1)

        case flags do
          [] -> "Unknown role"
          parts -> Enum.join(parts, " + ")
        end
    end
  end

  defp format_external_link_object(item) do
    label = value_of(item, :label) || value_of(item, :site) || "Link"
    value = value_of(item, :value) || value_of(item, :url) || ""
    "#{label}: #{value}"
  end

  defp format_series_entry_object(item) do
    name =
      value_of(item, :visual_novel_title) ||
        short_id(value_of(item, :visual_novel_id)) ||
        "?"

    case value_of(item, :position) do
      pos when is_integer(pos) -> "#{pos}: #{name}"
      _ -> name
    end
  end

  defp short_id(id) when is_binary(id) and byte_size(id) >= 8, do: binary_part(id, 0, 8)
  defp short_id(id) when is_binary(id), do: id
  defp short_id(_), do: nil

  defp image_identity?(item) do
    Enum.any?([:cover_id, :image_id, :screenshot_id], &present?(value_of(item, &1)))
  end

  # Hide screenshot rows whose moderation flags the viewer hasn't opted into.
  # Non-screenshot items always show.
  defp visible_to?(nil, _user), do: true

  defp visible_to?(item, user) when is_map(item) do
    screenshot? = present?(value_of(item, :screenshot_id))
    is_nsfw? = value_of(item, :is_nsfw) == true
    is_brutal? = value_of(item, :is_brutal) == true
    show_nsfw = Map.get(user || %{}, :show_nsfw_screenshots, false)
    show_brutal = Map.get(user || %{}, :show_brutal_screenshots, false)

    cond do
      not screenshot? -> true
      is_nsfw? and not show_nsfw -> false
      is_brutal? and not show_brutal -> false
      true -> true
    end
  end

  defp visible_to?(_item, _user), do: true

  # Apply the production cover blur contract to in-line thumbnails when
  # the item carries cover NSFW/suggestive flags. Independent of the
  # screenshot-prefs filter above (covers are blurred, not hidden).
  defp item_needs_blur?(nil), do: false

  defp item_needs_blur?(item) when is_map(item) do
    value_of(item, :is_image_nsfw) == true or
      value_of(item, :is_image_suggestive) == true or
      value_of(item, :is_nsfw) == true or
      value_of(item, :is_brutal) == true
  end

  defp item_needs_blur?(_), do: false

  defp image_flags(item) do
    []
    |> maybe_flag(value_of(item, :is_image_nsfw), "NSFW")
    |> maybe_flag(value_of(item, :is_image_suggestive), "suggestive")
    |> maybe_flag(value_of(item, :is_nsfw), "NSFW")
    |> maybe_flag(value_of(item, :is_brutal), "brutal")
    |> maybe_flag(present?(value_of(item, :language)), value_of(item, :language))
    |> Enum.join(" · ")
  end

  defp maybe_flag(flags, true, label), do: flags ++ [to_string(label)]
  defp maybe_flag(flags, _condition, _label), do: flags

  defp list_value(value) when is_list(value), do: value
  defp list_value(_), do: []

  defp has_any_key?(map, keys) do
    Enum.any?(keys, &has_key?(map, &1))
  end

  defp has_key?(map, key) when is_map(map) and is_atom(key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp has_key?(map, key) when is_map(map) and is_binary(key) do
    Map.has_key?(map, key) or existing_atom_key?(map, key)
  end

  defp has_key?(_, _), do: false

  defp value_of(nil, _key), do: nil

  defp value_of(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp value_of(map, key) when is_map(map) and is_binary(key) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      value_of_existing_atom(map, key)
    end
  end

  defp value_of(_, _), do: nil

  defp existing_atom_key?(map, key) do
    atom = String.to_existing_atom(key)
    Map.has_key?(map, atom)
  rescue
    ArgumentError -> false
  end

  defp value_of_existing_atom(map, key) do
    atom = String.to_existing_atom(key)
    Map.get(map, atom)
  rescue
    ArgumentError -> nil
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  # Word/punctuation-level inline text diff backed by `String.myers_difference/2`.
  # Tokens are joined back together inside each chunk so the renderer emits one
  # contiguous span per `:equal | :removed | :added` run, matching prod's
  # `inlineTextDiff` helper. Falls back to a whole-value swap when either side
  # is unusually large to keep the worker stack bounded.
  defp inline_text_diff(old_text, new_text)
       when is_binary(old_text) and is_binary(new_text) do
    old_tokens = tokenize(old_text)
    new_tokens = tokenize(new_text)

    if length(old_tokens) * length(new_tokens) > @max_lcs_cells do
      [
        %{type: :removed, text: old_text},
        %{type: :added, text: new_text}
      ]
    else
      old_tokens
      |> List.myers_difference(new_tokens)
      |> Enum.flat_map(fn
        {:eq, tokens} -> [%{type: :equal, text: Enum.join(tokens)}]
        {:del, tokens} -> [%{type: :removed, text: Enum.join(tokens)}]
        {:ins, tokens} -> [%{type: :added, text: Enum.join(tokens)}]
      end)
    end
  end

  defp inline_text_diff(_, _), do: []

  defp tokenize(text) do
    ~r/(\s+|[.,;:!?()\[\]{}"'])/
    |> Regex.split(text, include_captures: true, trim: true)
  end
end

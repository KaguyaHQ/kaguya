defmodule KaguyaWeb.Components.Shared.RevisionDiffTable do
  @moduledoc """
  Standalone side-by-side revision diff renderer.

  This is intentionally separate from the compact profile activity diff. It
  uses the same revision payload shape, but optimizes for the full detail page:
  field sections with full-width additions and removals, paired replacements,
  readable collections, and media thumbnails.
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
      "medium" => "Medium (10-30 hours)",
      "long" => "Long (30-50 hours)",
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
    "_state" => "State",
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

  @metadata_label %{
    "is_image_nsfw" => "NSFW",
    "is_nsfw" => "NSFW",
    "is_image_suggestive" => "Suggestive",
    "is_brutal" => "Brutal",
    "language" => "Language",
    "release_date" => "Release date",
    "release_id" => "Release"
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
      primary_image_id featured_screenshot_id titles relations characters covers screenshots
      external_links
    ),
    character: ~w(
      name description sex spoiler_sex gender spoiler_gender birthday age height
      weight bust waist hip cup_size blood_type is_image_nsfw is_image_suggestive images
      visual_novels
    ),
    producer: ~w(name description producer_type language external_links),
    release: ~w(
      title display_title latin_title original_language release_date release_type
      minage voiced engine reso_x reso_y patch freeware official uncensored has_ero
      media platforms languages mtl_languages notes producers external_links
    ),
    series: ~w(name description entries producers)
  }

  attr :snapshot, :map, default: nil
  attr :entity_type, :any, default: nil
  attr :current_user, :map, default: nil

  def initial_snapshot(assigns) do
    assigns = assign(assigns, :entries, snapshot_entries(assigns.snapshot, assigns.entity_type))

    ~H"""
    <section
      :if={@entries != []}
      id="revision-initial-snapshot"
      aria-labelledby="revision-initial-heading"
      class="space-y-3"
    >
      <div>
        <h2 id="revision-initial-heading" class="text-foreground-primary text-sm font-semibold">
          Initial version
        </h2>
        <p class="text-foreground-tertiary mt-1 text-sm">
          Values recorded when this entry was created.
        </p>
      </div>
      <dl class="border-border-divider divide-border-divider divide-y rounded-lg border">
        <div
          :for={entry <- @entries}
          id={"revision-initial-field-#{entry.field}"}
          class="grid gap-3 p-4 sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-5 sm:p-5"
        >
          <dt class="text-foreground-secondary text-sm font-medium">{field_label(entry.field)}</dt>
          <dd class="text-foreground-primary min-w-0 text-sm">
            <%= cond do %>
              <% entry.collection -> %>
                <.collection_cell items={entry.value} tone={:neutral} current_user={@current_user} />
              <% image_scalar_field?(entry.field) -> %>
                <.image_scalar_cell
                  field={entry.field}
                  value={entry.value}
                  url={read_image_url(@snapshot, entry.field)}
                  snapshot={@snapshot}
                  tone={:neutral}
                  current_user={@current_user}
                />
              <% true -> %>
                <.value_cell field={entry.field} value={entry.value} tone={:neutral} />
            <% end %>
          </dd>
        </div>
      </dl>
    </section>
    <p :if={@entries == []} id="revision-initial-empty" class="text-foreground-tertiary text-sm">
      The initial version’s contents aren’t available.
    </p>
    """
  end

  defp image_scalar_field?(field), do: MapSet.member?(@image_scalar_fields, field)

  defp snapshot_entries(snapshot, entity_type) do
    hist = value_of(snapshot, :hist)

    if is_map(hist) do
      scalars =
        @scalar_fields
        |> Enum.reject(&MapSet.member?(@state_fields, &1))
        |> Enum.map(&%{field: &1, value: value_of(hist, &1), collection: false})

      collections =
        ~w(titles relations characters covers screenshots external_links images visual_novels appearances entries producers links extlinks)
        |> Enum.map(&%{field: &1, value: value_of(snapshot, &1), collection: true})

      (scalars ++ collections)
      |> Enum.reject(&(&1.value in [nil, "", []]))
      |> Enum.sort_by(& &1.field)
      |> order_entries(entity_type)
    else
      []
    end
  end

  attr :diff_entries, :list, default: []
  attr :current_snapshot, :map, default: nil
  attr :previous_snapshot, :map, default: nil
  attr :entity_type, :any, default: nil
  attr :current_user, :map, default: nil
  attr :previous_revision_meta, :map, default: nil
  attr :current_revision_meta, :map, default: nil

  def diff_table(assigns) do
    entries =
      assigns.diff_entries
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and present?(value_of(&1, :field))))

    state_entry = state_entry(assigns.previous_snapshot, assigns.current_snapshot, entries)

    ordered_entries =
      entries
      |> Enum.reject(&MapSet.member?(@state_fields, to_string(value_of(&1, :field))))
      |> then(fn entries -> if state_entry, do: [state_entry | entries], else: entries end)
      |> order_entries(assigns.entity_type)

    assigns =
      assigns
      |> assign(:ordered_entries, ordered_entries)
      |> assign(
        :shared_columns,
        ordered_entries != [] and Enum.all?(ordered_entries, &paired_entry?/1)
      )

    ~H"""
    <div id="revision-changes" class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
        <h2 class="text-foreground-primary font-semibold">
          {length(@ordered_entries)} {if length(@ordered_entries) == 1, do: "field", else: "fields"} changed
        </h2>
        <div class="text-foreground-tertiary flex items-center gap-2">
          <.revision_header_cell meta={@previous_revision_meta} fallback="Previous revision" />
          <span aria-hidden="true">→</span>
          <.revision_header_cell
            meta={@current_revision_meta}
            fallback="Current revision"
            current?={true}
          />
        </div>
      </div>
      <div class="border-border-divider divide-border-divider divide-y rounded-lg border">
        <div
          :if={@shared_columns}
          id="revision-column-headings"
          class="text-foreground-tertiary hidden grid-cols-[9rem_minmax(0,1fr)] gap-5 px-5 py-3 text-xs md:grid"
          aria-hidden="true"
        >
          <span>Field</span>
          <div class="grid grid-cols-2 gap-4"><span>Before</span><span>After</span></div>
        </div>
        <.field_row
          :for={entry <- @ordered_entries}
          entry={entry}
          shared_columns={@shared_columns}
          previous_snapshot={@previous_snapshot}
          current_snapshot={@current_snapshot}
          current_user={@current_user}
        />
      </div>
    </div>
    """
  end

  attr :meta, :map, default: nil
  attr :fallback, :string, default: "—"
  attr :current?, :boolean, default: false

  defp revision_header_cell(assigns) do
    ~H"""
    <div :if={@meta} class="space-y-1 text-sm tracking-normal normal-case">
      <div class="flex flex-wrap items-baseline gap-x-2">
        <.link
          :if={@meta.href && !@current?}
          navigate={@meta.href}
          class="hover:text-text-link-hover text-text-link-default font-mono font-semibold transition-colors"
        >
          r{@meta.revision_number}
        </.link>
        <span
          :if={!@meta.href || @current?}
          class="text-foreground-primary font-mono font-semibold"
        >
          r{@meta.revision_number}
        </span>
      </div>
    </div>
    <p :if={!@meta} class="text-foreground-tertiary text-xs tracking-normal normal-case">
      {@fallback}
    </p>
    """
  end

  attr :entry, :map, required: true
  attr :current_snapshot, :map, default: nil
  attr :previous_snapshot, :map, default: nil
  attr :current_user, :map, default: nil

  attr :shared_columns, :boolean, default: false

  defp field_row(assigns) do
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

    old_present =
      if assigns.scalar or assigns.image_scalar,
        do: old not in [nil, "", []],
        else: list_value(value_of(assigns.entry, :removed)) != []

    new_present =
      if assigns.scalar or assigns.image_scalar,
        do: new not in [nil, "", []],
        else:
          list_value(value_of(assigns.entry, :added)) != [] or
            list_value(value_of(assigns.entry, :changed)) != []

    assigns =
      assign(assigns,
        old_present: old_present,
        new_present: new_present,
        collection_changed: list_value(value_of(assigns.entry, :changed)) != []
      )

    ~H"""
    <section
      id={"revision-diff-row-#{@field}"}
      aria-labelledby={"revision-field-#{@field}"}
      class="grid gap-3 p-4 sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-5 sm:p-5"
    >
      <h3 id={"revision-field-#{@field}"} class="text-foreground-primary text-sm font-medium">
        {@label}
      </h3>
      <div class={["grid min-w-0 gap-4", (@old_present and @new_present) && "md:grid-cols-2"]}>
        <div :if={@old_present} class="text-foreground-primary min-w-0 space-y-2">
          <p class={["text-foreground-tertiary text-xs", @shared_columns && "md:sr-only"]}>
            {if @new_present, do: "Before", else: "Removed"}
          </p>
          <%= cond do %>
            <% @image_scalar -> %>
              <.image_scalar_cell
                field={@field}
                value={@old}
                url={read_image_url(@previous_snapshot, @field)}
                snapshot={@previous_snapshot}
                tone={:removed}
                current_user={@current_user}
              />
            <% @long_text -> %>
              <.value_cell field={@field} value={@old} tone={:removed} />
            <% @scalar -> %>
              <.value_cell field={@field} value={@old} tone={:removed} />
            <% true -> %>
              <.collection_cell
                items={value_of(@entry, :removed)}
                changed={[]}
                tone={:removed}
                current_user={@current_user}
              />
          <% end %>
        </div>
        <div :if={@new_present} class="text-foreground-primary min-w-0 space-y-2">
          <p class={["text-foreground-tertiary text-xs", @shared_columns && "md:sr-only"]}>
            {cond do
              @old_present -> "After"
              @collection_changed -> "Added / updated"
              true -> "Added"
            end}
          </p>
          <%= cond do %>
            <% @image_scalar -> %>
              <.image_scalar_cell
                field={@field}
                value={@new}
                url={read_image_url(@current_snapshot, @field)}
                snapshot={@current_snapshot}
                tone={:added}
                current_user={@current_user}
              />
            <% @long_text -> %>
              <.value_cell field={@field} value={@new} tone={:added} />
            <% @scalar -> %>
              <.value_cell field={@field} value={@new} tone={:added} />
            <% true -> %>
              <.collection_cell
                items={value_of(@entry, :added)}
                changed={value_of(@entry, :changed)}
                tone={:added}
                current_user={@current_user}
              />
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  attr :field, :string, required: true
  attr :value, :any, default: nil
  attr :tone, :atom, required: true

  defp value_cell(assigns) do
    assigns = assign(assigns, :text, format_scalar_value(assigns.field, assigns.value))

    ~H"""
    <div class={value_class(@tone)}>
      <span class="wrap-break-word whitespace-pre-wrap">{@text}</span>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :value, :any, default: nil
  attr :url, :string, default: nil
  attr :snapshot, :map, default: nil
  attr :tone, :atom, required: true
  attr :current_user, :map, default: nil

  defp image_scalar_cell(assigns) do
    assigns =
      assigns
      |> assign(:visible, !is_nil(assigns.value))
      |> assign(:item, image_item(assigns.url, assigns.snapshot, assigns.field))

    ~H"""
    <div :if={@visible} class={image_item_class(@tone)}>
      <.thumbnail item={@item} current_user={@current_user} />
      <span :if={!@url} class="min-w-0 font-mono text-xs wrap-break-word">
        {format_scalar_value(@field, @value)}
      </span>
    </div>
    <span :if={!@visible} class="text-foreground-quaternary">[empty]</span>
    """
  end

  attr :items, :any, default: []
  attr :changed, :any, default: []
  attr :tone, :atom, required: true
  attr :current_user, :map, default: nil

  defp collection_cell(assigns) do
    visible = &visible_to?(&1, assigns.current_user)

    items =
      assigns.items
      |> list_value()
      |> Enum.filter(visible)

    changed_items =
      assigns.changed
      |> list_value()
      |> Enum.filter(fn entry ->
        visible.(value_of(entry, :old)) and visible.(value_of(entry, :new))
      end)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:changed_items, changed_items)
      |> assign(:image_grid?, image_collection?(items) and changed_items == [])

    ~H"""
    <div :if={@image_grid?} class="flex flex-wrap gap-2">
      <.image_collection_item
        :for={item <- @items}
        item={item}
        tone={@tone}
        current_user={@current_user}
      />
    </div>

    <div :if={!@image_grid? and (@items != [] or @changed_items != [])} class="space-y-2">
      <.collection_item
        :for={item <- @items}
        item={item}
        tone={@tone}
        current_user={@current_user}
      />
      <.changed_collection_item
        :for={entry <- @changed_items}
        entry={entry}
        current_user={@current_user}
      />
    </div>
    <span :if={@items == [] and @changed_items == []} class="text-foreground-quaternary">
      [empty]
    </span>
    """
  end

  attr :item, :any, default: nil
  attr :tone, :atom, required: true
  attr :current_user, :map, default: nil

  defp image_collection_item(assigns) do
    assigns = assign(assigns, :label, image_flags(assigns.item))

    ~H"""
    <div class={image_item_class(@tone)}>
      <.thumbnail item={@item} current_user={@current_user} />
      <span :if={@label != "Image"} class="truncate text-[11px] leading-tight">
        {@label}
      </span>
      <span :if={@label == "Image"} class="sr-only">Image</span>
    </div>
    """
  end

  attr :item, :any, default: nil
  attr :tone, :atom, required: true
  attr :current_user, :map, default: nil

  defp collection_item(assigns) do
    ~H"""
    <div class={item_class(@tone)}>
      <.thumbnail item={@item} current_user={@current_user} />
      <span class="min-w-0 flex-1 wrap-break-word">{short_item(@item)}</span>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :current_user, :map, default: nil

  defp changed_collection_item(assigns) do
    item = value_of(assigns.entry, :new)
    changes = metadata_changes(value_of(assigns.entry, :fields))

    assigns =
      assigns
      |> assign(:item, item)
      |> assign(:changes, changes)

    ~H"""
    <div class={item_class(:changed)}>
      <.thumbnail item={@item} current_user={@current_user} />
      <div class="min-w-0 flex-1">
        <p class="wrap-break-word">{short_item(@item)}</p>
        <p :if={@changes != []} class="mt-1 text-xs text-amber-200">
          <%= for {change, index} <- Enum.with_index(@changes) do %>
            <span>{change}</span><span :if={index < length(@changes) - 1}> · </span>
          <% end %>
        </p>
      </div>
    </div>
    """
  end

  attr :item, :any, default: nil
  attr :current_user, :map, default: nil

  defp thumbnail(assigns) do
    assigns =
      assigns
      |> assign(:url, image_url_of(assigns.item))
      |> assign(:nsfw_blur?, item_needs_blur?(assigns.item))

    ~H"""
    <span
      :if={@url}
      class={[
        "ring-border-divider/60 relative inline-block shrink-0 overflow-hidden rounded-[6px] ring-1",
        thumbnail_shape(@item)
      ]}
    >
      <img
        src={@url}
        alt=""
        class="size-full object-contain"
        loading="lazy"
        decoding="async"
        data-nsfw-blur={if @nsfw_blur?, do: "1"}
        style={if @nsfw_blur?, do: "--nsfw-blur-size: 30;"}
      />
    </span>
    """
  end

  defp paired_entry?(entry) do
    if has_any_key?(entry, [:old, :new]) do
      value_of(entry, :old) not in [nil, "", []] and value_of(entry, :new) not in [nil, "", []]
    else
      list_value(value_of(entry, :removed)) != [] and
        (list_value(value_of(entry, :added)) != [] or list_value(value_of(entry, :changed)) != [])
    end
  end

  defp state_entry(previous_snapshot, current_snapshot, entries) do
    if Enum.any?(entries, &MapSet.member?(@state_fields, to_string(value_of(&1, :field)))) do
      %{
        field: "_state",
        old: derive_state(value_of(previous_snapshot, :hist)),
        new: derive_state(value_of(current_snapshot, :hist))
      }
    end
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

  defp metadata_label(field), do: Map.get(@metadata_label, field) || field_label(field)

  defp format_scalar_value(_field, value) when value in [nil, ""], do: "[empty]"
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
    case value do
      [] -> "[empty]"
      values -> Enum.map_join(values, ", ", &format_scalar_value(field, &1))
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

  defp image_item(nil, _snapshot, _field), do: nil

  defp image_item(url, snapshot, field) do
    hist = value_of(snapshot, :hist) || %{}

    %{
      url: url,
      is_image_nsfw: value_of(hist, :is_image_nsfw),
      is_image_suggestive: value_of(hist, :is_image_suggestive),
      is_nsfw: value_of(hist, :is_nsfw),
      field: field
    }
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

  defp short_item(nil), do: "[empty]"
  defp short_item(value) when is_binary(value), do: value
  defp short_item(value) when is_number(value), do: to_string(value)
  defp short_item(value) when is_atom(value), do: to_string(value)
  defp short_item(%Date{} = value), do: Date.to_iso8601(value)

  defp short_item(%{} = item) do
    cond do
      title_object?(item) ->
        format_title_object(item)

      relation_object?(item) ->
        format_relation_object(item)

      cast_object?(item) ->
        format_cast_object(item)

      appearance_object?(item) ->
        format_appearance_object(item)

      release_producer_object?(item) ->
        format_release_producer_object(item)

      external_link_object?(item) ->
        format_external_link_object(item)

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
    rtype = if rtype in [nil, "", "[empty]"], do: "?", else: rtype

    name =
      value_of(item, :related_vn_title) ||
        short_id(value_of(item, :related_vn_id)) ||
        "?"

    "[#{prefix}] #{rtype}: #{name}"
  end

  defp format_cast_object(item) do
    role = format_scalar_value("role", value_of(item, :role))
    role = if role in [nil, "", "[empty]"], do: "?", else: role

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
    role = if role in [nil, "", "[empty]"], do: "?", else: role

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

  defp image_collection?(items) when is_list(items) and items != [] do
    Enum.all?(items, &image_identity?/1)
  end

  defp image_collection?(_items), do: false

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

  defp item_needs_blur?(nil), do: false

  defp item_needs_blur?(item) when is_map(item) do
    value_of(item, :is_image_nsfw) == true or
      value_of(item, :is_image_suggestive) == true or
      value_of(item, :is_nsfw) == true or
      value_of(item, :is_brutal) == true
  end

  defp item_needs_blur?(_), do: false

  defp thumbnail_shape(item) do
    if present?(value_of(item, :screenshot_id)) do
      "w-48 max-w-full aspect-video"
    else
      "h-40 max-w-full aspect-[3/4]"
    end
  end

  defp image_flags(item) do
    []
    |> maybe_flag(value_of(item, :is_image_nsfw), "NSFW")
    |> maybe_flag(value_of(item, :is_image_suggestive), "suggestive")
    |> maybe_flag(value_of(item, :is_nsfw), "NSFW")
    |> maybe_flag(value_of(item, :is_brutal), "brutal")
    |> maybe_flag(present?(value_of(item, :language)), value_of(item, :language))
    |> Enum.join(" · ")
    |> case do
      "" -> "Image"
      value -> value
    end
  end

  defp metadata_changes(fields) do
    fields
    |> list_value()
    |> Enum.reject(fn field ->
      value_of(field, :field) in ["cover_id", "image_id", "screenshot_id"]
    end)
    |> Enum.map(fn field ->
      key = to_string(value_of(field, :field))
      old = format_scalar_value(key, value_of(field, :old))
      new = format_scalar_value(key, value_of(field, :new))
      "#{metadata_label(key)}: #{old} -> #{new}"
    end)
  end

  defp maybe_flag(flags, true, label), do: flags ++ [to_string(label)]
  defp maybe_flag(flags, _condition, _label), do: flags

  defp value_class(:neutral), do: "text-foreground-primary text-sm"

  defp value_class(:removed),
    do: "rounded-[6px] border border-red-500/25 bg-red-500/10 px-3 py-2 text-sm text-red-100"

  defp value_class(:added),
    do:
      "rounded-[6px] border border-green-500/25 bg-green-500/10 px-3 py-2 text-sm text-green-100"

  defp item_class(:neutral), do: "text-foreground-primary flex items-center gap-3 text-sm"

  defp item_class(:removed),
    do:
      "flex items-center gap-3 rounded-[6px] border border-red-500/25 bg-red-500/10 px-3 py-2 text-sm text-red-100"

  defp item_class(:added),
    do:
      "flex items-center gap-3 rounded-[6px] border border-green-500/25 bg-green-500/10 px-3 py-2 text-sm text-green-100"

  defp item_class(:changed),
    do:
      "flex items-center gap-3 rounded-[6px] border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-100"

  defp image_item_class(:neutral),
    do:
      "text-foreground-secondary inline-flex w-fit max-w-full flex-col items-start gap-2 text-xs"

  defp image_item_class(:removed),
    do:
      "inline-flex w-fit max-w-full flex-col items-start gap-2 rounded-[6px] border border-red-500/40 text-xs text-foreground-secondary"

  defp image_item_class(:added),
    do:
      "inline-flex w-fit max-w-full flex-col items-start gap-2 rounded-[6px] border border-green-500/40 text-xs text-foreground-secondary"

  defp image_item_class(:changed),
    do:
      "inline-flex w-fit max-w-full flex-col items-start gap-2 rounded-[6px] border border-amber-500/40 text-xs text-foreground-secondary"

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
end

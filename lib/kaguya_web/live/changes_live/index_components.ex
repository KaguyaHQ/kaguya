defmodule KaguyaWeb.ChangesLive.IndexComponents do
  @moduledoc false

  use KaguyaWeb, :html

  alias Kaguya.Revisions.ChangedFields

  attr :payload, :map, required: true

  def changes_page(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-6 sm:px-6 lg:px-8">
      <header class="border-border-divider border-b pb-5">
        <div>
          <h1 class="text-foreground-primary text-xl font-semibold lg:text-2xl">Recent changes</h1>
          <p class="text-foreground-secondary mt-1 max-w-2xl text-sm">
            Latest user-authored edits across visual novels, characters, producers, releases, and series.
          </p>
        </div>
      </header>

      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <nav class="flex gap-2 overflow-x-auto pb-1" aria-label="Change type filters">
          <.filter_link
            :for={{label, value} <- @payload.entity_type_options}
            label={label}
            value={value}
            active={
              @payload.entity_type_param == value ||
                (is_nil(value) && is_nil(@payload.entity_type_param))
            }
          />
        </nav>

        <p class="text-foreground-tertiary shrink-0 text-sm">
          {count_label(@payload.total_count)}
        </p>
      </div>

      <section class="bg-surface-base border-border-divider overflow-hidden rounded-[8px] border">
        <div
          :if={@payload.rows == []}
          class="text-foreground-secondary px-4 py-12 text-center text-sm"
        >
          No changes found.
        </div>

        <ol :if={@payload.rows != []} class="divide-border-divider divide-y">
          <.change_row :for={row <- @payload.rows} row={row} />
        </ol>
      </section>

      <.pagination payload={@payload} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :active, :boolean, default: false

  defp filter_link(assigns) do
    ~H"""
    <.link
      patch={filter_href(@value)}
      class={[
        "rounded-full border px-3 py-1.5 text-sm whitespace-nowrap transition-colors",
        if(@active,
          do: "bg-foreground-primary border-foreground-primary text-background",
          else:
            "border-border-divider hover:border-foreground-tertiary hover:text-foreground-primary text-foreground-secondary"
        )
      ]}
    >
      {@label}
    </.link>
    """
  end

  attr :row, :map, required: true

  defp change_row(assigns) do
    ~H"""
    <li
      :if={@row.change_href}
      class="cursor-pointer"
      role="link"
      tabindex="0"
      onclick="if(!event.target.closest('a')) event.currentTarget.querySelector('[data-row-link]')?.click()"
      onkeydown="if((event.key==='Enter' || event.key===' ') && !event.target.closest('a')) { event.preventDefault(); event.currentTarget.querySelector('[data-row-link]')?.click() }"
    >
      <.link navigate={@row.change_href} data-row-link class="sr-only" aria-hidden="true">
        Open change
      </.link>
      <.change_row_content row={@row} />
    </li>
    <li :if={!@row.change_href}>
      <.change_row_content row={@row} />
    </li>
    """
  end

  attr :row, :map, required: true

  defp change_row_content(assigns) do
    ~H"""
    <div class={[
      "hover:bg-surface-elevated/35 flex gap-3 border-l-2 p-3 transition-colors sm:gap-4 sm:px-4",
      action_accent_class(@row.action)
    ]}>
      <.entity_image entity={@row.entity} type={@row.entity_type} />

      <div class="min-w-0 flex-1">
        <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
          <div class="min-w-0 flex-1">
            <.link
              :if={@row.entity.href}
              navigate={@row.entity.href}
              class="text-foreground-primary inline-block max-w-full truncate align-bottom text-base font-semibold underline-offset-4 hover:underline"
            >
              {@row.entity.title}
            </.link>
            <span
              :if={!@row.entity.href}
              class="text-foreground-primary inline-block max-w-full truncate align-bottom text-base font-semibold"
            >
              {@row.entity.title}
            </span>
          </div>

          <.revision_pill row={@row} />
          <time
            class="text-foreground-tertiary shrink-0 text-xs"
            title={@row.inserted_at_label}
          >
            {@row.relative_time}
          </time>
        </div>

        <div class="text-foreground-tertiary mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          <span class="text-foreground-secondary font-medium">
            {change_meta(@row)}
          </span>
          <span aria-hidden="true">·</span>
          <.user_link user={@row.user} />
          <div
            :if={@row.changed_fields != []}
            class="flex flex-wrap gap-1"
            aria-label={changed_fields_label(@row.changed_fields)}
          >
            <span aria-hidden="true" class="text-foreground-tertiary">·</span>
            <.field_chip :for={field <- changed_field_chips(@row.changed_fields)} field={field} />
          </div>
        </div>

        <p class="text-foreground-secondary mt-1 line-clamp-2 text-sm">{@row.summary}</p>
      </div>
    </div>
    """
  end

  attr :row, :map, required: true

  defp revision_pill(assigns) do
    ~H"""
    <.link
      :if={@row.change_href}
      navigate={@row.change_href}
      class="bg-surface-elevated border-border-divider hover:text-foreground-primary text-foreground-secondary shrink-0 rounded-full border px-2 py-0.5 font-mono text-xs transition-colors"
    >
      r{@row.revision_number}
    </.link>
    <span
      :if={!@row.change_href}
      class="bg-surface-elevated border-border-divider text-foreground-secondary shrink-0 rounded-full border px-2 py-0.5 font-mono text-xs"
    >
      r{@row.revision_number}
    </span>
    """
  end

  attr :entity, :map, required: true
  attr :type, :atom, required: true

  defp entity_image(assigns) do
    assigns =
      assigns
      |> assign(:placeholder, placeholder(assigns.type))
      |> assign(:nsfw_blur?, entity_cover_needs_blur?(assigns.entity))

    ~H"""
    <div class="bg-surface-elevated/70 text-foreground-tertiary flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-[6px] text-xs font-semibold sm:size-11">
      <img
        :if={@entity.image_url}
        src={@entity.image_url}
        alt=""
        class="size-full object-cover"
        loading="lazy"
        data-nsfw-blur={if @nsfw_blur?, do: "1"}
        style={if @nsfw_blur?, do: "--nsfw-blur-size: 56;"}
      />
      <span :if={!@entity.image_url}>{@placeholder}</span>
    </div>
    """
  end

  defp entity_cover_needs_blur?(%{} = entity) do
    Map.get(entity, :is_image_nsfw) == true or
      Map.get(entity, :is_image_suggestive) == true
  end

  defp entity_cover_needs_blur?(_), do: false

  attr :user, :map, required: true

  defp user_link(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <img
        :if={@user.avatar_url}
        src={@user.avatar_url}
        alt=""
        class="size-4 rounded-full object-cover"
        loading="lazy"
      />
      <.link
        :if={@user.href}
        navigate={@user.href}
        class="hover:text-foreground-primary hover:underline"
      >
        {@user.display_name}
      </.link>
      <span :if={!@user.href}>{@user.display_name}</span>
    </span>
    """
  end

  attr :field, :string, required: true

  defp field_chip(assigns) do
    ~H"""
    <span class="bg-surface-elevated text-foreground-tertiary max-w-full truncate rounded px-1.5 py-0.5 text-[11px]">
      {@field}
    </span>
    """
  end

  attr :payload, :map, required: true

  defp pagination(assigns) do
    ~H"""
    <nav
      :if={@payload.total_pages > 1}
      class="flex items-center justify-between gap-3 text-sm"
      aria-label="Pagination"
    >
      <.link
        patch={page_href(@payload.entity_type_param, @payload.page - 1)}
        class={[
          "border-border-divider hover:border-foreground-tertiary hover:text-foreground-primary text-foreground-secondary rounded-[6px] border px-3 py-2 transition-colors",
          unless(@payload.has_previous, do: "pointer-events-none opacity-40")
        ]}
      >
        Previous
      </.link>

      <span class="text-foreground-tertiary">
        Page {@payload.page} of {@payload.total_pages}
      </span>

      <.link
        patch={page_href(@payload.entity_type_param, @payload.page + 1)}
        class={[
          "border-border-divider hover:border-foreground-tertiary hover:text-foreground-primary text-foreground-secondary rounded-[6px] border px-3 py-2 transition-colors",
          unless(@payload.has_next, do: "pointer-events-none opacity-40")
        ]}
      >
        Next
      </.link>
    </nav>
    """
  end

  defp filter_href(nil), do: "/history"
  defp filter_href(value), do: "/history?type=#{value}"

  defp page_href(type, page) when page <= 1, do: filter_href(type)
  defp page_href(nil, page), do: "/history?page=#{page}"
  defp page_href(type, page), do: "/history?type=#{type}&page=#{page}"

  defp changed_fields_label(fields) do
    ChangedFields.summary_label(fields)
  end

  defp changed_field_chips(fields) do
    fields
    |> Enum.take(3)
    |> Enum.map(&ChangedFields.field_label/1)
  end

  defp change_meta(row) do
    "#{row.action_label} #{entity_type_name(row.entity_type)}"
  end

  defp entity_type_name(:visual_novel), do: "visual novel"
  defp entity_type_name(:character), do: "character"
  defp entity_type_name(:producer), do: "producer"
  defp entity_type_name(:release), do: "release"
  defp entity_type_name(:series), do: "series"
  defp entity_type_name(type), do: to_string(type)

  defp count_label(1), do: "1 change"
  defp count_label(count), do: "#{count} changes"

  defp action_accent_class(:create), do: "border-l-action-create"
  defp action_accent_class(:revert), do: "border-l-action-revert"
  defp action_accent_class(:hide), do: "border-l-action-restrict"
  defp action_accent_class(:lock), do: "border-l-action-restrict"
  defp action_accent_class(_), do: "border-l-transparent"

  defp placeholder(:visual_novel), do: "VN"
  defp placeholder(:character), do: "CH"
  defp placeholder(:producer), do: "PR"
  defp placeholder(:release), do: "RL"
  defp placeholder(:series), do: "SR"
  defp placeholder(_), do: "ED"
end

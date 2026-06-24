defmodule KaguyaWeb.VN.Panels.Tags do
  @moduledoc """
  Tags tab: grouped chips per `kind`, a popover-driven vote menu for
  editors, and the "Available on" store-links row anchored beneath the
  groups. `tag_vote_trigger/1` has two clauses — signed-in editors get
  the full popover; everyone else gets an auth-gated button that opens
  the sign-in prompt.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Shared.SocialIcons

  import KaguyaWeb.AuthPromptComponents, only: [auth_button: 1]
  import KaguyaWeb.UI.Menu, only: [menu: 1]
  import KaguyaWeb.VN.Formatters, only: [availability_label: 1, tag_percentage: 1]

  attr :tags, :list, required: true
  attr :visual_novel_id, :string, required: true
  attr :available_on_links, :list, default: []
  attr :id_prefix, :string, default: "vn"
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false
  attr :expanded_kinds, :list, default: []

  def panel(assigns) do
    by_kind = Enum.group_by(assigns.tags, & &1.kind)
    assigns = assign(assigns, :by_kind, by_kind)

    ~H"""
    <div class="flex flex-col gap-5">
      <%= for {kind, label} <- tag_kinds() do %>
        <.tag_kind_group
          :if={@by_kind[kind]}
          kind={kind}
          label={label}
          tags={@by_kind[kind]}
          visual_novel_id={@visual_novel_id}
          id_prefix={@id_prefix}
          is_logged_in={@is_logged_in}
          user_can_edit={@user_can_edit}
          expanded={kind in @expanded_kinds}
        />
      <% end %>

      <.available_on_row :if={@available_on_links != []} links={@available_on_links} />
    </div>
    """
  end

  def skeleton(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div :for={width <- ["w-12", "w-16", "w-14"]} class="flex flex-col gap-2">
        <div class={["h-3 rounded-full bg-[rgb(var(--surface-banner))]/40", width]}></div>
        <div class="flex flex-wrap gap-2">
          <div
            :for={w <- skeleton_chip_widths()}
            class={["h-[26px] rounded-[4px] bg-[rgb(var(--surface-banner))]/30", w]}
          >
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :kind, :string, required: true
  attr :label, :string, required: true
  attr :tags, :list, required: true
  attr :visual_novel_id, :string, required: true
  attr :id_prefix, :string, default: "vn"
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false
  attr :expanded, :boolean, default: false

  defp tag_kind_group(assigns) do
    overflow = length(assigns.tags) - 10
    visible = if assigns.expanded, do: assigns.tags, else: Enum.take(assigns.tags, 10)
    assigns = assign(assigns, overflow: overflow, visible: visible)

    ~H"""
    <section class="flex flex-col gap-2">
      <h3 class="text-style-captionRegular tracking-wider text-[rgb(var(--foreground-tertiary))] uppercase">
        {@label}
      </h3>
      <div class="flex flex-wrap gap-2">
        <.tag_chip
          :for={tag <- @visible}
          tag={tag}
          visual_novel_id={@visual_novel_id}
          id_prefix={@id_prefix}
          is_logged_in={@is_logged_in}
          user_can_edit={@user_can_edit}
        />
        <button
          :if={@overflow > 0}
          type="button"
          phx-click="toggle_tag_kind"
          phx-value-kind={@kind}
          class="text-style-captionRegular flex items-center rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[rgb(var(--foreground-tertiary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
        >
          {if @expanded, do: "Less", else: "+#{@overflow} more"}
        </button>
      </div>
    </section>
    """
  end

  attr :tag, :map, required: true
  attr :visual_novel_id, :string, required: true
  attr :id_prefix, :string, default: "vn"
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  defp tag_chip(assigns) do
    assigns =
      assigns
      |> assign(:percentage, tag_percentage(assigns.tag))
      |> assign(:has_vote, not is_nil(Map.get(assigns.tag, :my_vote)))

    ~H"""
    <span class="relative inline-flex items-stretch overflow-visible rounded-[4px] border border-[rgb(var(--chip-border-default))] transition-colors duration-200 hover:border-[rgb(var(--chip-border-hover))]">
      <span
        :if={@has_vote}
        class="pointer-events-none absolute right-[2px] bottom-[2px] z-10 size-[3px] rounded-full bg-[rgb(var(--foreground-primary))]"
      >
      </span>
      <.link
        navigate={~p"/browse?tags=#{@tag.slug}"}
        class="text-style-captionRegular px-[8px] py-[4px] text-white transition-colors hover:text-white"
      >
        {@tag.name}
      </.link>
      <.tag_vote_trigger
        :if={@percentage}
        tag={@tag}
        percentage={@percentage}
        visual_novel_id={@visual_novel_id}
        id_prefix={@id_prefix}
        is_logged_in={@is_logged_in}
        user_can_edit={@user_can_edit}
      />
    </span>
    """
  end

  attr :tag, :map, required: true
  attr :percentage, :integer, required: true
  attr :visual_novel_id, :string, required: true
  attr :id_prefix, :string, default: "vn"
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  defp tag_vote_trigger(%{is_logged_in: true, user_can_edit: true} = assigns) do
    ~H"""
    <.menu
      id={"tag-vote-#{@id_prefix}-#{@tag.id}"}
      align="end"
      side_offset={6}
      class="group/vote text-style-captionRegular flex cursor-pointer list-none items-center gap-[3px] border-l border-[rgb(var(--chip-border-default))] py-[4px] pr-[6px] pl-[6px] text-[rgb(var(--foreground-quaternary))] tabular-nums transition-colors hover:bg-white/4 hover:text-[rgb(var(--foreground-secondary))] data-[state=open]:bg-white/6"
    >
      <:trigger aria-label={"Vote on #{@tag.name}"}>
        {@percentage}%
        <Lucide.chevrons_up_down
          class="hidden size-[9px] text-[rgb(var(--foreground-tertiary))] group-hover/vote:inline-block group-data-[state=open]/vote:inline-block"
          stroke_width="2.5"
          aria-hidden
        />
      </:trigger>
      <div
        aria-label={"Vote on #{@tag.name}"}
        class="w-[240px] rounded-[6px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-1 shadow-[0_10px_30px_rgba(0,0,0,0.6)]"
      >
        <.tag_vote_menu tag={@tag} visual_novel_id={@visual_novel_id} />
      </div>
    </.menu>
    """
  end

  defp tag_vote_trigger(assigns) do
    ~H"""
    <.auth_button
      event="vote_tag"
      is_logged_in={@is_logged_in}
      modal_id="vn-auth-prompt"
      auth_message="Sign in to vote on tags"
      phx-value-tag-id={@tag.id}
      phx-value-vote={Map.get(@tag, :my_vote) || 4}
      class="text-style-captionRegular flex items-center border-l border-[rgb(var(--chip-border-default))] py-[4px] pr-[6px] pl-[6px] text-[rgb(var(--foreground-quaternary))] tabular-nums transition-colors hover:bg-white/4 hover:text-[rgb(var(--foreground-secondary))]"
      aria-label={"Vote on #{@tag.name}"}
    >
      {@percentage}%
    </.auth_button>
    """
  end

  attr :tag, :map, required: true
  attr :visual_novel_id, :string, required: true

  defp tag_vote_menu(assigns) do
    assigns = assign(assigns, :buckets, tag_vote_buckets())

    ~H"""
    <div class="flex flex-col">
      <.tag_vote_row
        :for={{value, label} <- @buckets}
        tag={@tag}
        value={value}
        label={label}
        count={tag_vote_count(@tag, value)}
        selected={Map.get(@tag, :my_vote) == value}
      />

      <div class="m-1 border-t border-[rgb(var(--border-divider))]/60"></div>

      <.tag_vote_row
        tag={@tag}
        value={0}
        label="Not relevant"
        count={tag_vote_count(@tag, 0)}
        selected={Map.get(@tag, :my_vote) == 0}
        muted
      />

      <%= if not is_nil(Map.get(@tag, :my_vote)) do %>
        <div class="mx-1 mt-1 border-t border-[rgb(var(--border-divider))]/60"></div>
        <button
          type="button"
          phx-click="clear_tag_vote"
          phx-value-tag-id={@tag.id}
          class="w-full rounded-[5px] px-2.5 py-1.5 text-left text-[12px] text-[rgb(var(--foreground-quaternary))] transition-colors hover:text-[rgb(var(--foreground-secondary))]"
        >
          Clear vote
        </button>
      <% end %>
    </div>
    """
  end

  attr :tag, :map, required: true
  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :selected, :boolean, default: false
  attr :muted, :boolean, default: false

  defp tag_vote_row(assigns) do
    assigns = assign(assigns, :has_voters, assigns.count > 0)

    ~H"""
    <div class={[
      "group/row relative flex rounded-[5px] transition-colors",
      @selected && "bg-white/6",
      !@selected && "hover:bg-white/4"
    ]}>
      <button
        type="button"
        phx-click="vote_tag"
        phx-value-tag-id={@tag.id}
        phx-value-vote={@value}
        aria-pressed={if(@selected, do: "true", else: "false")}
        aria-label={"Vote #{@label}"}
        class="flex w-full items-center justify-between gap-3 rounded-[5px] px-2.5 py-[7px] text-left text-[13px] leading-tight transition-colors"
      >
        <span class={[
          "tracking-[-0.005em]",
          @selected && "font-medium text-[rgb(var(--foreground-primary))]",
          !@selected && @muted && "text-[rgb(var(--foreground-tertiary))]",
          !@selected && !@muted && "text-[rgb(var(--foreground-secondary))]"
        ]}>
          {@label}
        </span>
        <span class={["transition-opacity", @has_voters && "group-hover/row:opacity-0"]}>
          <%= cond do %>
            <% @value > 0 -> %>
              <.tag_vote_dots value={@value} selected={@selected} />
            <% @selected -> %>
              <span class="block size-[5px] rounded-full bg-[rgb(var(--foreground-primary))]"></span>
            <% true -> %>
          <% end %>
        </span>
      </button>
      <span
        :if={@has_voters}
        aria-hidden="true"
        class="pointer-events-none absolute inset-y-0 right-0 flex items-center gap-0.5 rounded-r-[5px] pr-2 pl-2.5 text-[11px] text-[rgb(var(--foreground-tertiary))] tabular-nums opacity-0 transition-opacity group-hover/row:opacity-100"
      >
        {@count}
        <Lucide.chevron_right class="size-[11px]" stroke_width="2.5" aria-hidden />
      </span>
    </div>
    """
  end

  attr :value, :integer, required: true
  attr :selected, :boolean, default: false

  defp tag_vote_dots(assigns) do
    ~H"""
    <span :if={@value > 0} aria-hidden="true" class="inline-flex shrink-0 items-center gap-[3px]">
      <span
        :for={dot <- 1..5}
        class={[
          "size-[5px] rounded-full",
          dot <= @value && @selected && "bg-[rgb(var(--foreground-primary))]",
          dot <= @value && !@selected && "bg-[rgb(var(--foreground-tertiary))]",
          dot > @value && "bg-[rgb(var(--border-divider))]"
        ]}
      >
      </span>
    </span>
    """
  end

  attr :links, :list, required: true

  defp available_on_row(assigns) do
    ~H"""
    <section class="mt-2 rounded-[8px] border border-[rgb(var(--border-divider))]/70 bg-white/2 p-3">
      <div class="flex items-center gap-2">
        <span class="shrink-0 text-[11px] tracking-[0.08em] text-[rgb(var(--foreground-tertiary))] uppercase">
          Available on
        </span>
        <span class="h-px flex-1 bg-[rgb(var(--border-divider))]/60"></span>
      </div>

      <div class="mt-2.5 flex flex-wrap gap-1.5">
        <.link
          :for={link <- @links}
          href={available_link_url(link)}
          target="_blank"
          rel="noopener noreferrer"
          class="group inline-flex items-center gap-1.5 rounded-full border border-[rgb(var(--chip-border-default))] bg-[rgb(var(--surface-elevated))]/55 px-2.5 py-1 text-[12px]/4 text-[rgb(var(--foreground-secondary))] transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
        >
          <SocialIcons.icon
            :if={available_link_icon?(link)}
            site={available_link_site(link)}
            class="size-3 shrink-0"
          />
          <span class="font-medium text-[rgb(var(--foreground-secondary))] group-hover:text-[rgb(var(--foreground-primary))]">
            {available_link_label(link)}
          </span>
          <span
            :if={available_link_availability_label(link)}
            class="rounded-full bg-[rgb(var(--surface-banner))] px-1.5 py-px text-[10px] font-medium tracking-wide text-[rgb(var(--foreground-tertiary))] lowercase"
          >
            {available_link_availability_label(link)}
          </span>
        </.link>
      </div>
    </section>
    """
  end

  defp tag_kinds do
    [
      {"GENRE", "Genres"},
      {"THEME", "Themes"},
      {"CAST", "Cast"},
      {"FORMAT", "Format"},
      {"SEXUAL", "Sexual"},
      {"GAMEPLAY", "Gameplay"}
    ]
  end

  defp tag_vote_buckets do
    [
      {5, "Main Theme"},
      {4, "Major Element"},
      {3, "Moderate Element"},
      {2, "Minor Element"},
      {1, "Small Element"}
    ]
  end

  defp tag_vote_count(tag, value) do
    tag
    |> Map.get(:kaguya_bucket_counts, [])
    |> Enum.at(value, 0)
  end

  defp skeleton_chip_widths,
    do: ["w-16", "w-20", "w-14", "w-24", "w-16", "w-20", "w-12", "w-16", "w-20", "w-16"]

  defp available_link_url(%{url: url}) when is_binary(url) and url != "", do: url
  defp available_link_url(_), do: "#"

  defp available_link_label(%{label: label}) when is_binary(label) and label != "", do: label
  defp available_link_label(%{site: site}) when is_binary(site) and site != "", do: site
  defp available_link_label(_), do: "Store"

  defp available_link_icon?(link), do: link |> available_link_site() |> SocialIcons.glyph?()

  defp available_link_site(%{site: site}) when is_binary(site) and site != "", do: site
  defp available_link_site(%{source_site: site}) when is_binary(site) and site != "", do: site
  defp available_link_site(_), do: nil

  defp available_link_availability_label(link),
    do: availability_label(Map.get(link, :availability))
end

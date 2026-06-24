defmodule KaguyaWeb.Lists.ShowComponents do
  @moduledoc """
  HEEx components for the read-only VN list show page.
  """

  use KaguyaWeb, :html
  import Bitwise, only: [&&&: 2]

  alias KaguyaWeb.SharedComponents.Cover
  alias KaguyaWeb.SharedComponents.LikeButton
  alias KaguyaWeb.SharedComponents.Pagination, as: SharedPagination

  attr :list, :map, required: true
  attr :owner, :map, required: true
  attr :updated_from_now, :string, required: true
  attr :reading_percentage, :float, required: true
  attr :my_read_count, :integer, required: true
  attr :total_count, :integer, required: true

  def list_header(assigns) do
    ~H"""
    <div class="space-y-3 px-4 md:space-y-2.5 md:max-lg:px-8 lg:px-0">
      <div class="flex items-center justify-between lg:hidden">
        <div class="flex min-w-0 items-center gap-2">
          <.owner_avatar owner={@owner} size="size-6" />
          <div class="flex min-w-0 items-baseline gap-1.5">
            <.link
              navigate={profile_path(@owner)}
              class="min-w-0 text-sm font-semibold text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))]"
            >
              <span class="truncate">{display_name(@owner)}</span>
            </.link>
            <span class="text-[11px] text-[rgb(var(--foreground-primary))]/40">·</span>
            <span class="shrink-0 text-[11px] text-[rgb(var(--foreground-secondary))]">
              {@updated_from_now}
            </span>
          </div>
        </div>
      </div>

      <h1 class="text-[20px] leading-[26px] font-semibold text-[rgb(var(--foreground-primary))] md:-mt-1.5! lg:text-2xl">
        {@list.name}
        <span
          :if={!@list.is_public}
          class="ml-1.5 inline-flex items-center align-middle text-[rgb(var(--foreground-secondary))]"
        >
          <Lucide.lock class="-mt-0.5 size-4" aria-hidden />
        </span>
      </h1>

      <div class="hidden items-center gap-2.5 lg:flex">
        <div class="flex min-w-0 items-center gap-1">
          <.owner_avatar owner={@owner} size="size-7" />
          <.link
            navigate={profile_path(@owner)}
            class="min-w-0 text-base font-semibold text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))]"
          >
            <span class="truncate">{display_name(@owner)}</span>
          </.link>
        </div>

        <span class="text-[11px] text-[rgb(var(--foreground-primary))]/40">•</span>

        <span class="text-sm text-[rgb(var(--foreground-secondary))]" title={@list.updated_at_title}>
          Updated {@updated_from_now}
        </span>
      </div>

      <p
        :if={present?(@list.description)}
        class="text-sm font-normal wrap-break-word whitespace-pre-line text-[rgb(var(--foreground-primary))] lg:text-base"
      >
        {String.trim(@list.description)}
      </p>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :is_ranked, :boolean, default: false
  attr :fade_read, :boolean, default: false

  def list_grid(assigns) do
    ~H"""
    <div>
      <Cover.cover_tooltip_provider id="list-grid-cover-tooltips">
        <div class={[
          "my-0 grid grid-cols-4 gap-x-[5px] gap-y-[5px] px-4 sm:grid-cols-5 md:gap-2 md:max-lg:grid-cols-6 md:max-lg:px-8 lg:my-0 lg:px-0",
          @is_ranked && "gap-y-[5px] md:gap-y-2"
        ]}>
          <div :for={item <- @items} class="flex min-w-0 flex-col gap-1">
            <.vn_cover
              vn={item.visual_novel}
              fade={@fade_read && read?(item.visual_novel)}
              image_class="rounded-[2px]"
            />

            <div
              :if={@is_ranked}
              class={[
                "mb-[3px] flex items-center justify-center gap-0.5 text-xs font-normal text-[rgb(var(--foreground-primary))] lg:text-sm",
                @fade_read && read?(item.visual_novel) && "opacity-20"
              ]}
            >
              <p>{item.position}</p>
            </div>
          </div>
        </div>
      </Cover.cover_tooltip_provider>

      <div
        :if={@items == []}
        class="px-4 py-12 text-sm text-[rgb(var(--foreground-tertiary))] md:px-8 lg:px-0"
      >
        No visual novels on this page.
      </div>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :tiers, :list, required: true
  attr :fade_read, :boolean, default: false
  attr :fullscreen, :boolean, default: false
  attr :list_name, :string, default: "Tier list"

  def tier_board(assigns) do
    ~H"""
    <div class="px-4 md:max-lg:px-8 lg:px-0">
      <Cover.cover_tooltip_provider :if={!@fullscreen} id="tier-board-cover-tooltips">
        <.tier_board_inner
          items={@items}
          tiers={@tiers}
          fade_read={@fade_read}
        />
      </Cover.cover_tooltip_provider>

      <div
        :if={@fullscreen}
        class="fixed inset-0 z-120 overflow-auto bg-[rgb(var(--surface-base))] p-2 sm:p-4"
      >
        <div class="mb-3 flex items-center justify-between gap-3">
          <p class="truncate text-sm font-semibold text-[rgb(var(--foreground-primary))]">
            {@list_name}
          </p>
          <button
            type="button"
            phx-click="close_tier_fullscreen"
            class="flex size-9 items-center justify-center rounded-[8px] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))]"
            aria-label="Close tier list fullscreen"
          >
            <Lucide.x class="size-4" aria-hidden />
          </button>
        </div>
        <div class="mx-auto max-w-[1600px]">
          <Cover.cover_tooltip_provider id="tier-board-fullscreen-cover-tooltips">
            <.tier_board_inner items={@items} tiers={@tiers} fade_read={@fade_read} />
          </Cover.cover_tooltip_provider>
        </div>
      </div>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :tiers, :list, required: true
  attr :fade_read, :boolean, default: false

  defp tier_board_inner(assigns) do
    ~H"""
    <div class="tier-board space-y-3">
      <div class="overflow-hidden rounded-[8px] border border-[rgb(var(--border-divider))]">
        <div
          :for={tier <- @tiers}
          class="grid min-h-[112px] grid-cols-[104px_1fr] border-b border-[rgb(var(--border-divider))] last:border-b-0 max-sm:min-h-[64px] max-sm:grid-cols-[56px_1fr]"
        >
          <div
            class="flex items-center justify-center border-r border-white/6 text-base font-bold text-white/95 max-sm:text-[11px]"
            style={tier_header_style(tier)}
          >
            <span class="line-clamp-2 px-2 text-center wrap-break-word max-sm:px-1">
              {tier.label}
            </span>
          </div>

          <div class="flex min-h-[112px] flex-wrap content-start gap-2 p-2 max-sm:min-h-[56px] max-sm:gap-1 max-sm:p-1">
            <.tier_cover
              :for={item <- tier_items(@items, tier.id)}
              item={item}
              fade={@fade_read && read?(item.visual_novel)}
            />
          </div>
        </div>

        <div
          :if={@tiers == []}
          class="px-4 py-12 text-sm text-[rgb(var(--foreground-tertiary))]"
        >
          No tier rows available.
        </div>
      </div>
    </div>
    """
  end

  attr :list, :map, required: true
  attr :owner, :map, required: true
  attr :liked_by_me, :boolean, default: false
  attr :likes_count, :integer, default: 0
  attr :is_mine, :boolean, default: false
  attr :is_logged_in, :boolean, default: false
  attr :is_admin, :boolean, default: false
  attr :is_public, :boolean, default: true
  attr :is_hidden, :boolean, default: false
  attr :fade_read, :boolean, default: false
  attr :total_count, :integer, default: 0
  attr :current_count, :integer, default: 0
  attr :reading_percentage, :float, default: 0.0
  attr :panel_id, :string, required: true
  attr :mobile, :boolean, default: false
  attr :share_url, :string, required: true

  def actions_panel(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-[10px] bg-[#1a1a1a] ring-1 ring-white/4">
      <.list_like_action
        liked_by_me={@liked_by_me}
        likes_count={@likes_count}
        is_public={@is_public}
        panel_id={@panel_id}
      />

      <.list_management_actions
        :if={@mobile}
        list={@list}
        owner={@owner}
        is_mine={@is_mine}
        is_admin={@is_admin}
        is_public={@is_public}
        is_hidden={@is_hidden}
        panel_id={@panel_id}
      />

      <%= if @total_count > 0 do %>
        <div class="mx-4 h-px bg-white/6" />
        <.reading_progress
          current_count={@current_count}
          total_count={@total_count}
          percentage={@reading_percentage}
          class={[
            "rounded-none border-0 bg-transparent",
            @mobile && "p-4",
            !@mobile && "py-5 pr-4 pl-5"
          ]}
        />
      <% end %>

      <div class="mx-4 h-px bg-white/6" />
      <div class="flex items-center">
        <button
          type="button"
          data-share-button
          data-share-url={@share_url}
          data-share-title="Share list"
          class="flex flex-1 items-center justify-center gap-2 py-3 text-xs font-normal text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]"
        >
          <Lucide.link_2 class="size-[14px]" aria-hidden />
          <span>Share</span>
        </button>
        <div class="h-4 w-px bg-white/6" />
        <button
          type="button"
          id={"#{@panel_id}-fade-read"}
          phx-click="toggle_fade_read"
          phx-hook="FadeReadPreference"
          data-storage-key="fadeReadLists"
          data-fade-read={to_string(@fade_read)}
          data-is-logged-in={to_string(@is_logged_in)}
          aria-pressed={@fade_read}
          aria-label={if @fade_read, do: "Show all VNs", else: "Fade read VNs"}
          class={[
            "flex flex-1 items-center justify-center py-3 text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]",
            @fade_read && "text-[rgb(var(--foreground-secondary))]"
          ]}
        >
          <%= if @fade_read do %>
            <Lucide.eye_off class="size-[15px]" aria-hidden />
          <% else %>
            <Lucide.eye class="size-[15px]" aria-hidden />
          <% end %>
        </button>
        <%= if @list.display_mode == "tier" and !@mobile do %>
          <div class="h-4 w-px bg-white/6" />
          <button
            type="button"
            phx-click="open_tier_fullscreen"
            aria-label="Open tier list fullscreen"
            class="flex flex-1 items-center justify-center py-3 text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]"
          >
            <Lucide.maximize class="size-[15px]" aria-hidden />
          </button>
        <% end %>
      </div>

      <.list_management_actions
        :if={!@mobile}
        list={@list}
        owner={@owner}
        is_mine={@is_mine}
        is_admin={@is_admin}
        is_public={@is_public}
        is_hidden={@is_hidden}
        panel_id={@panel_id}
      />
    </div>
    """
  end

  attr :liked_by_me, :boolean, default: false
  attr :likes_count, :integer, default: 0
  attr :is_public, :boolean, default: true
  attr :panel_id, :string, required: true

  defp list_like_action(assigns) do
    ~H"""
    <LikeButton.like_button
      :if={@is_public}
      id={"like-list-#{@panel_id}"}
      click="toggle_like"
      liked={@liked_by_me}
      likes_count={@likes_count}
      class="flex w-full cursor-pointer justify-center p-4"
    />
    """
  end

  attr :list, :map, required: true
  attr :owner, :map, required: true
  attr :is_mine, :boolean, default: false
  attr :is_admin, :boolean, default: false
  attr :is_public, :boolean, default: true
  attr :is_hidden, :boolean, default: false
  attr :panel_id, :string, required: true

  defp list_management_actions(assigns) do
    ~H"""
    <%= if @is_mine do %>
      <div class="mx-4 h-px bg-white/6" />
      <.link
        navigate={"/@#{@owner.username}/list/#{@list.slug}/edit"}
        class="flex cursor-pointer items-center justify-center py-3 text-xs font-normal text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]"
      >
        Edit this list...
      </.link>
      <div class="mx-4 h-px bg-white/6" />
      <button
        id={"toggle-visibility-#{@panel_id}"}
        type="button"
        phx-click="toggle_visibility"
        class="flex w-full cursor-pointer items-center justify-center py-3 text-xs font-normal text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]"
      >
        <%= if @is_public do %>
          Make this list private
        <% else %>
          Make this list public
        <% end %>
      </button>
    <% end %>

    <%= if @is_admin && !@is_mine do %>
      <div class="mx-4 h-px bg-white/6" />
      <button
        id={"toggle-hidden-#{@panel_id}"}
        type="button"
        phx-click="toggle_hidden"
        class="flex w-full cursor-pointer items-center justify-center py-3 text-xs font-normal text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/3 hover:text-[rgb(var(--foreground-secondary))]"
      >
        <%= if @is_hidden do %>
          Unhide this list
        <% else %>
          Hide this list
        <% end %>
      </button>
    <% end %>
    """
  end

  attr :current_count, :integer, required: true
  attr :total_count, :integer, required: true
  attr :percentage, :float, required: true
  attr :class, :any, default: nil
  attr :percentage_class, :string, default: nil

  def reading_progress(assigns) do
    ~H"""
    <div
      :if={@total_count > 0}
      class={[
        "relative flex items-center justify-between gap-1.5 overflow-hidden rounded-b-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] py-[18px] pr-4 pl-6",
        @class
      ]}
    >
      <div class="flex flex-col">
        <span class="text-sm text-[rgb(var(--foreground-secondary))] md:max-lg:text-[9px] md:max-lg:leading-[11px]">
          You've read
        </span>
        <span class="text-sm text-[rgb(var(--foreground-secondary))] md:max-lg:text-[9px] md:max-lg:leading-[11px]">
          {@current_count} of {@total_count}
        </span>
      </div>

      <span class={[
        "inline-flex items-baseline text-[32px] leading-[39px] text-[rgb(var(--foreground-secondary))]",
        @percentage_class
      ]}>
        {rounded_percentage(@percentage)}
        <span class="text-[0.55em] font-light">%</span>
      </span>

      <div class="absolute bottom-0 left-0 h-1 w-full bg-white/4 md:max-lg:h-[2px]">
        <div
          class="h-full bg-[rgb(var(--foreground-secondary))]"
          style={"width: #{clamped_percentage(@percentage)}%"}
        />
      </div>
    </div>
    """
  end

  attr :pagination, :map, required: true
  attr :current_page, :integer, required: true
  attr :base_path, :string, required: true
  attr :page_param, :string, default: "listPage"

  def pagination(assigns) do
    ~H"""
    <SharedPagination.pagination
      total_pages={@pagination.total_pages || 1}
      current_page={@current_page}
      base_path={@base_path}
      page_param={@page_param}
      aria_label="List pagination"
    />
    """
  end

  attr :vn, :map, required: true
  attr :fade, :boolean, default: false
  attr :image_class, :string, default: "rounded-[4px]"

  defp vn_cover(assigns) do
    ~H"""
    <div class={[
      "transition-opacity",
      @fade && "opacity-20"
    ]}>
      <Cover.cover
        vn={@vn}
        sizes="(max-width: 640px) 124px, 144px"
        link
        show_title_tooltip
        shadow
        class={
          join_classes([
            "aspect-2/3 w-full bg-[rgb(var(--surface-elevated))] object-cover object-center text-transparent",
            @image_class
          ])
        }
        fallback_class={join_classes(["border border-[rgb(var(--border-divider))]", @image_class])}
      />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :fade, :boolean, default: false

  defp tier_cover(assigns) do
    ~H"""
    <div class={[
      "group relative h-[104px] w-[70px] shrink-0 overflow-hidden rounded-[4px] bg-[rgb(var(--surface-elevated))] transition-opacity max-sm:h-[72px] max-sm:w-[48px]",
      @fade && "opacity-20"
    ]}>
      <Cover.cover
        vn={@item.visual_novel}
        sizes="80px"
        link
        show_title_tooltip
        class="h-[104px] w-[70px] rounded-[4px] object-cover object-center text-transparent max-sm:h-[72px] max-sm:w-[48px]"
        fallback_class="h-[104px] w-[70px] rounded-[4px] border border-[rgb(var(--border-divider))] max-sm:h-[72px] max-sm:w-[48px]"
      />
    </div>
    """
  end

  attr :owner, :map, required: true
  attr :size, :string, default: "size-8"

  defp owner_avatar(assigns) do
    ~H"""
    <.link navigate={profile_path(@owner)} class="shrink-0">
      <%= if @owner.avatar_url do %>
        <img
          src={@owner.avatar_url}
          alt={display_name(@owner)}
          class={[@size, "rounded-full object-cover"]}
        />
      <% else %>
        <div class={[
          @size,
          "flex items-center justify-center rounded-full bg-[rgb(var(--surface-banner))] text-xs text-[rgb(var(--foreground-secondary))]"
        ]}>
          {initials(@owner)}
        </div>
      <% end %>
    </.link>
    """
  end

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_owner), do: "/"

  defp display_name(%{display_name: name, username: username}) do
    if present?(name), do: name, else: username
  end

  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp initials(%{display_name: name}) when is_binary(name) and name != "",
    do: initials_from(name)

  defp initials(%{username: name}) when is_binary(name) and name != "", do: initials_from(name)
  defp initials(_), do: "?"

  defp initials_from(name) do
    name
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn part -> part |> String.first() |> String.upcase() end)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp read?(%{my_reading_status: %{status: status}}), do: status in [:read, "read", "READ"]
  defp read?(_), do: false

  defp tier_items(items, tier_id) do
    items
    |> Enum.filter(&(Map.get(&1, :tier_id) == tier_id))
    |> Enum.sort_by(
      &{Map.get(&1, :tier_position) || Map.get(&1, :position), Map.get(&1, :position)}
    )
  end

  defp tier_header_style(tier) do
    color = tier.color

    "background: linear-gradient(135deg, #{hex_to_rgba(color, 0.58)}, #{hex_to_rgba(color, 0.36)}); " <>
      "box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.1);"
  end

  defp hex_to_rgba("#" <> hex, alpha) when byte_size(hex) == 6 do
    with {value, ""} <- Integer.parse(hex, 16) do
      r = Bitwise.bsr(value, 16) &&& 255
      g = Bitwise.bsr(value, 8) &&& 255
      b = value &&& 255
      "rgba(#{r}, #{g}, #{b}, #{alpha})"
    else
      _ -> "rgba(255, 255, 255, #{alpha})"
    end
  end

  defp hex_to_rgba(_hex, alpha), do: "rgba(255, 255, 255, #{alpha})"

  defp rounded_percentage(value) when is_number(value), do: value |> Float.round(0) |> trunc()
  defp rounded_percentage(_), do: 0

  defp clamped_percentage(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(100.0)
    |> Float.round(2)
  end

  defp clamped_percentage(_), do: 0

  defp join_classes(classes) do
    classes
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or &1 == false))
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end
end

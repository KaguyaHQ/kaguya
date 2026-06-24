defmodule KaguyaWeb.Lists.Cards do
  @moduledoc """
  Shared list render primitives reused by profile and list surfaces.

  These components mirror the existing Next.js list card/row treatment while
  delegating VN cover rendering to `KaguyaWeb.SharedComponents.Cover`.
  """

  use KaguyaWeb, :html

  attr :list, :map, required: true
  attr :sizes, :string, required: true
  attr :max_covers, :integer, default: 4
  attr :responsive_max_covers, :map, default: nil
  attr :class, :any, default: nil
  attr :container_class, :any, default: nil
  attr :grid_class, :any, default: nil
  attr :image_class, :any, default: nil
  attr :title_class, :any, default: nil
  attr :details_class, :any, default: nil
  attr :details_variant, :string, default: "icon"
  attr :hide_details, :boolean, default: false
  attr :show_description, :boolean, default: false
  attr :variant, :string, default: "card"
  attr :description_class, :any, default: nil
  attr :cover_fallback_size, :integer, default: 42

  def list_card(assigns) do
    assigns =
      assigns
      |> assign(:href, list_path(assigns.list))
      |> assign(:user_href, user_path(assigns.list[:user]))
      |> assign(:thumbnail_items, thumbnail_items(assigns.list))
      |> assign(:public?, Map.get(assigns.list, :is_public, true))
      |> assign(:vns_count, assigns.list[:vns_count] || 0)

    ~H"""
    <div class={[
      @variant == "description" && "grid gap-x-4 sm:grid-cols-[40%_1fr] sm:max-lg:gap-x-3",
      @class
    ]}>
      <div class="relative">
        <.link navigate={@href}>
          <.stacked_covers
            sizes={@sizes}
            items={@thumbnail_items}
            max_covers={@max_covers}
            responsive_max_covers={@responsive_max_covers}
            container_class={@container_class}
            class={@grid_class}
            image_class={@image_class}
            cover_fallback_size={@cover_fallback_size}
            disable_cover_link
          />
        </.link>
      </div>

      <div>
        <.link
          navigate={@href}
          class={[
            "mt-2.5 line-clamp-2 leading-[21px] font-semibold text-[rgb(var(--foreground-primary))] md:max-lg:text-sm dark:text-[#f9f9f9]",
            @title_class
          ]}
        >
          {@list.name}
          <.lock_badge :if={!@public?} />
        </.link>

        <div
          :if={!@hide_details}
          class={["mt-[5px] flex items-center gap-[9px] sm:max-lg:mt-1", @details_class]}
        >
          <div class="flex max-w-[62%] min-w-0 items-center gap-1">
            <.link
              navigate={@user_href}
              class="shrink-0"
              style="box-shadow: 4px 4px 4px rgba(0, 0, 0, 0.25);"
            >
              <.avatar user={@list.user} size="size-[18px] md:max-lg:size-[13px]" sizes="18px" />
            </.link>
            <.link
              navigate={@user_href}
              class="truncate text-xs leading-[160%] font-semibold text-[rgb(var(--foreground-quaternary))] md:max-lg:text-[10px] md:max-lg:leading-[12px] md:max-lg:font-medium"
            >
              {display_name(@list.user)}
            </.link>
          </div>

          <span class="text-xs leading-[160%] text-[rgb(var(--foreground-quaternary))] md:max-lg:text-[10px] md:max-lg:leading-[12px]">
            {format_integer(@vns_count)} {pluralize(@vns_count, "VN", "VNs")}
          </span>

          <div class="flex items-center gap-[3px]">
            <Lucide.heart
              class={[
                "size-3.5 fill-current text-[rgb(var(--foreground-secondary))]",
                @details_variant == "text" && "hidden"
              ]}
              aria-hidden
            />
            <span class="text-xs leading-[160%] text-[rgb(var(--foreground-quaternary))] md:max-lg:text-[10px] md:max-lg:leading-[12px]">
              {format_count(@list.likes_count || 0)}
              <span :if={@details_variant == "text"}>
                {pluralize(@list.likes_count || 0, "like", "likes")}
              </span>
            </span>
          </div>
        </div>

        <p
          :if={(@variant == "description" or @show_description) and present?(@list.description)}
          class={[
            "mt-[5px] line-clamp-3 text-sm font-normal text-[rgb(var(--foreground-secondary))] sm:mt-1.5 md:max-lg:text-xs md:max-lg:leading-[17px] md:max-lg:text-[rgb(var(--foreground-quaternary))] lg:mt-2",
            @show_description && @variant != "description" && "line-clamp-2",
            @description_class
          ]}
        >
          {@list.description}
        </p>
      </div>
    </div>
    """
  end

  attr :list, :map, required: true
  attr :class, :any, default: nil
  attr :show_description, :boolean, default: true
  attr :hide_user, :boolean, default: false
  attr :show_edit_link, :boolean, default: false
  attr :size, :atom, default: :default, values: [:default, :large]
  attr :mobile_max_covers, :integer, default: nil

  def list_row(assigns) do
    assigns =
      assigns
      |> assign(:href, list_path(assigns.list))
      |> assign(:edit_href, list_path(assigns.list) <> "/edit")
      |> assign(:user_href, user_path(assigns.list[:user]))
      |> assign(:thumbnail_items, thumbnail_items(assigns.list))
      |> assign(:large?, assigns.size == :large)
      |> assign(:public?, Map.get(assigns.list, :is_public, true))
      |> assign(:vns_count, assigns.list[:vns_count] || 0)

    ~H"""
    <div class={[
      "grid grid-cols-[auto_1fr]",
      if(@large?, do: "gap-x-5 lg:gap-x-7", else: "gap-x-3 lg:gap-x-5"),
      @class
    ]}>
      <.link navigate={@href}>
        <.stacked_covers
          sizes={
            if @large?, do: "(max-width: 1024px) 70px, 85px", else: "(max-width: 1024px) 56px, 70px"
          }
          items={@thumbnail_items}
          responsive_max_covers={%{mobile: @mobile_max_covers || 3, desktop: 4}}
          disable_cover_link
          container_class={[
            "flex w-fit overflow-hidden",
            if(@large?,
              do: "-space-x-[12px] rounded-[4px] lg:-space-x-[18px] lg:rounded-[5px]",
              else: "-space-x-[12px] rounded-[3px] lg:-space-x-[18px] lg:rounded-[4px]"
            )
          ]}
          class={[
            "flex-none!",
            if(@large?,
              do: "w-[70px] rounded-[4px] lg:w-[85px] lg:rounded-[5px]",
              else: "w-[56px] rounded-[3px] lg:w-[70px] lg:rounded-[4px]"
            )
          ]}
          image_class={
            if @large?, do: "rounded-[4px] lg:rounded-[5px]", else: "rounded-[3px] lg:rounded-[4px]"
          }
        />
      </.link>

      <div class="flex min-w-0 flex-col justify-center">
        <.link
          navigate={@href}
          class={[
            "line-clamp-2 font-semibold text-[rgb(var(--foreground-primary))]",
            if(@large?,
              do: "text-base/tight lg:text-xl",
              else: "text-sm leading-[21px] lg:text-lg"
            )
          ]}
        >
          {@list.name}
          <.lock_badge :if={!@public?} />
        </.link>

        <div class={["flex items-center gap-[9px]", if(@large?, do: "mt-1.5", else: "mt-1")]}>
          <div :if={!@hide_user} class="flex min-w-0 items-center gap-1">
            <.link navigate={@user_href} class="shrink-0">
              <.avatar user={@list.user} size="size-4" sizes="16px" />
            </.link>
            <.link
              navigate={@user_href}
              class="truncate text-xs leading-[160%] font-semibold text-[rgb(var(--foreground-quaternary))]"
            >
              {display_name(@list.user)}
            </.link>
          </div>

          <span class="shrink-0 text-xs leading-[160%] text-[rgb(var(--foreground-quaternary))]">
            {format_integer(@vns_count)} {pluralize(@vns_count, "VN", "VNs")}
          </span>

          <div class="flex shrink-0 items-center gap-[3px]">
            <Lucide.heart
              class="size-3.5 fill-current text-[rgb(var(--foreground-secondary))]"
              aria-hidden
            />
            <span class="text-xs leading-[160%] text-[rgb(var(--foreground-quaternary))]">
              {format_count(@list.likes_count || 0)}
            </span>
          </div>

          <.link
            :if={@show_edit_link}
            navigate={@edit_href}
            class="shrink-0 text-[rgb(var(--foreground-tertiary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
            title="Edit list"
          >
            <Lucide.pencil class="size-3" aria-hidden />
          </.link>
        </div>

        <p
          :if={@show_description and present?(@list.description)}
          class={[
            "line-clamp-2 text-[rgb(var(--foreground-secondary))] lg:line-clamp-3",
            if(@large?,
              do: "mt-2 max-w-lg text-sm lg:mt-3 lg:text-[15px] lg:leading-relaxed",
              else: "text-style-body2Regular mt-1.5 max-w-md"
            )
          ]}
        >
          {@list.description}
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Stacked overlapping covers — shim that delegates to
  `KaguyaWeb.SharedComponents.StackedCovers`. Kept for back-compat with
  list-card / list-row callsites that pass `class` (vs the shared
  module's `item_class`) and `disable_cover_link` defaulting to `false`.
  """
  attr :items, :list, required: true
  attr :sizes, :string, required: true
  attr :max_covers, :integer, default: 5
  attr :responsive_max_covers, :map, default: nil
  attr :class, :any, default: nil
  attr :container_class, :any, default: nil
  attr :image_class, :any, default: nil
  attr :disable_cover_link, :boolean, default: false
  attr :cover_fallback_size, :integer, default: 42
  attr :empty_slot_class, :any, default: nil

  def stacked_covers(assigns) do
    _ = assigns.cover_fallback_size

    ~H"""
    <KaguyaWeb.SharedComponents.StackedCovers.stacked_covers
      items={@items}
      sizes={@sizes}
      max_covers={@max_covers}
      responsive_max_covers={@responsive_max_covers}
      container_class={@container_class}
      item_class={@class}
      image_class={@image_class}
      empty_slot_class={@empty_slot_class}
      disable_cover_link={@disable_cover_link}
    />
    """
  end

  defp thumbnail_items(%{visual_novels: %{items: items}}), do: Enum.map(items, & &1.visual_novel)

  defp thumbnail_items(%{visual_novels: items}) when is_list(items),
    do: Enum.map(items, & &1.visual_novel)

  defp thumbnail_items(%{cover_urls: items}) when is_list(items), do: items
  defp thumbnail_items(_list), do: []

  defp list_path(%{user: %{username: username}, slug: slug})
       when is_binary(username) and is_binary(slug),
       do: "/@#{username}/list/#{slug}"

  defp list_path(%{username: username, slug: slug})
       when is_binary(username) and is_binary(slug),
       do: "/@#{username}/list/#{slug}"

  defp list_path(_list), do: "/lists"

  defp user_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp user_path(_user), do: "/"

  attr :user, :map, required: true
  attr :size, :string, required: true
  attr :sizes, :string, required: true

  defp avatar(%{user: user} = assigns) do
    _ = user

    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@user}
      size={@size}
      sizes={@sizes}
      fallback={:initials}
    />
    """
  end

  defp lock_badge(assigns) do
    ~H"""
    <span class="ml-1 inline-flex items-center align-middle">
      <Lucide.lock class="-mt-0.5 size-4 text-[rgb(var(--foreground-secondary))]" aria-hidden />
    </span>
    """
  end

  defp display_name(%{display_name: name, username: username}) do
    if present?(name), do: name, else: username
  end

  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_user), do: "Kaguya user"

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp format_integer(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_integer(_value), do: "0"

  defp format_count(value) when is_integer(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 1)}M"
  end

  defp format_count(value) when is_integer(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 1)}K"
  end

  defp format_count(value), do: to_string(value || 0)
end

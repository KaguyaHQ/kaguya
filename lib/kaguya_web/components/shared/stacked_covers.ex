defmodule KaguyaWeb.SharedComponents.StackedCovers do
  @moduledoc """
  Overlapping group of VN covers.

  Single source of truth for the rounded, overlapping cover thumbnail
  rows used across list cards, list rows, profile sidebar wishlist,
  stats most-liked sections, and the activity / feed showcases.

  Each item is rendered via `KaguyaWeb.SharedComponents.Cover.cover/1`,
  so srcset, NSFW blur, and title fallback come for free.

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 12.

  ## Example

      <.stacked_covers
        items={Enum.take(@list.visual_novels, 5)}
        sizes="(max-width: 1024px) 56px, 70px"
        responsive_max_covers={%{mobile: 3, desktop: 4}}
        container_class="flex w-fit overflow-hidden -space-x-[12px] lg:-space-x-[18px] rounded-[5px]"
      />
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Cover

  attr :items, :list,
    required: true,
    doc: "List of VN maps (need `:images`, `:title`, `:slug`). May contain `nil` for empty slots."

  attr :sizes, :string,
    required: true,
    doc: "HTML `sizes` attribute forwarded to each `<Cover.cover>`."

  attr :max_covers, :integer, default: 5

  attr :responsive_max_covers, :map,
    default: nil,
    doc:
      "`%{mobile: n, desktop: n}` — overrides `:max_covers` per breakpoint. Items beyond the lower count are hidden on that breakpoint."

  attr :container_class, :any,
    default: nil,
    doc: "Class for the flex container."

  attr :item_class, :any,
    default: nil,
    doc: "Class for each cover slot (placed on the relative wrapper, not the img)."

  attr :image_class, :any,
    default: nil,
    doc: "Class forwarded to each `<Cover.cover>` and the empty fallback."

  attr :empty_slot_class, :any, default: nil, doc: "Extra class for empty placeholder slots."

  attr :disable_cover_link, :boolean,
    default: true,
    doc:
      "Default `true` because most callers wrap the whole stack in a parent link (list card, sidebar widget). Pass `false` to make each cover a link to its VN."

  attr :rest, :global

  def stacked_covers(assigns) do
    responsive = assigns.responsive_max_covers || %{}

    mobile_count =
      Map.get(responsive, :mobile) || Map.get(responsive, "mobile") || assigns.max_covers

    desktop_count =
      Map.get(responsive, :desktop) || Map.get(responsive, "desktop") || assigns.max_covers

    final_count = max(mobile_count, desktop_count)

    display_items =
      for index <- 0..(final_count - 1) do
        %{
          item: Enum.at(assigns.items || [], index),
          index: index,
          responsive_class: responsive_cover_class(index, mobile_count, desktop_count)
        }
      end

    assigns =
      assigns
      |> assign(:display_items, display_items)
      |> assign(:final_count, final_count)

    ~H"""
    <div
      class={[
        "flex items-stretch -space-x-4 overflow-hidden rounded-[3px] bg-[rgb(var(--surface-base))] p-0",
        @container_class
      ]}
      style="box-shadow: rgba(0, 0, 0, 0.25) 0px 1px 5px 0px, rgba(0, 0, 0, 0.35) 0px 1px 10px 0px;"
      {@rest}
    >
      <div
        :for={entry <- @display_items}
        class={[
          "relative aspect-2/3 flex-1 overflow-hidden",
          entry.responsive_class,
          @item_class
        ]}
        style={"z-index: #{@final_count - entry.index}; box-shadow: rgba(0, 0, 0, 0.9) 2px 0px 6px 0px;"}
      >
        <Cover.cover
          :if={entry.item}
          vn={entry.item}
          sizes={@sizes}
          link={not @disable_cover_link}
          class={[
            "size-full rounded-none object-cover object-center text-transparent",
            @image_class
          ]}
          fallback_class={["h-full w-full rounded-none", @image_class]}
        />
        <div
          :if={!entry.item}
          class={[
            "size-full rounded-none bg-[rgb(var(--surface-base))]",
            @image_class,
            @empty_slot_class
          ]}
        />
        <span class="pointer-events-none absolute inset-0 rounded-[inherit] shadow-[inset_0_0_0_1px_rgba(50,50,50,0.5)]" />
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp responsive_cover_class(index, mobile_count, desktop_count) do
    cond do
      mobile_count < desktop_count and index >= mobile_count -> "hidden md:block"
      desktop_count < mobile_count and index >= desktop_count -> "md:hidden"
      true -> nil
    end
  end
end

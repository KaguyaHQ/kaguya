defmodule KaguyaWeb.VN.Panels.Quotes do
  @moduledoc """
  Quotes tab: serif-typeset character quotes with per-quote like
  affordance. The first eight render inline; the rest collapse behind a
  "Show more" toggle, matching the releases panel's overflow pattern.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.VN.PanelHelpers, only: [show_more_button_class: 1]

  attr :items, :list, required: true

  def panel(assigns) do
    visible_limit = 8
    visible = Enum.take(assigns.items, visible_limit)
    overflow = Enum.drop(assigns.items, visible_limit)
    assigns = assign(assigns, visible: visible, overflow: overflow)

    ~H"""
    <div class="flex flex-col divide-y divide-[rgb(var(--border-divider))]/50">
      <.quote_block :for={quote <- @visible} quote={quote} />

      <details :if={@overflow != []} class="group/quotes-more">
        <summary class={show_more_button_class(["pt-3", "group-open/quotes-more:hidden"])}>
          Show more
        </summary>
        <div class="flex flex-col divide-y divide-[rgb(var(--border-divider))]/50">
          <.quote_block :for={quote <- @overflow} quote={quote} />
        </div>
      </details>
    </div>
    """
  end

  def skeleton(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div :for={_ <- 1..3} class="rounded-[8px] border border-[rgb(var(--border-divider))] p-4">
        <div class="space-y-2">
          <div class="h-3 w-11/12 animate-pulse rounded-full bg-[rgb(var(--surface-banner))]/40">
          </div>
          <div class="h-3 w-9/12 animate-pulse rounded-full bg-[rgb(var(--surface-banner))]/40"></div>
        </div>
      </div>
    </div>
    """
  end

  attr :quote, :map, required: true

  defp quote_block(assigns) do
    ~H"""
    <blockquote class="group/quote-row flex items-start gap-3 py-4 first:pt-0">
      <div class="min-w-0 flex-1">
        <p
          class="text-[15px] leading-relaxed text-[rgb(var(--foreground-secondary))]"
          style="font-family: var(--font-source-serif)"
        >
          “{@quote.quote}”
        </p>
        <div class="mt-2 truncate text-xs text-[rgb(var(--foreground-tertiary))]">
          <%= if @quote.character do %>
            <span aria-hidden="true">— </span>
            <.link
              navigate={"/character/#{@quote.character.slug}"}
              class="transition-colors hover:text-[rgb(var(--foreground-secondary))]"
            >
              {@quote.character.name}
            </.link>
          <% else %>
            <span aria-hidden="true">— </span>Unknown
          <% end %>
        </div>
      </div>
      <div class="relative flex shrink-0 items-center gap-1">
        <button
          type="button"
          phx-click="toggle_quote_like"
          phx-value-quote-id={@quote.id}
          aria-label={if @quote.liked_by_me, do: "Unlike quote", else: "Like quote"}
          aria-pressed={if @quote.liked_by_me, do: "true", else: "false"}
          class={[
            "group/like relative inline-flex items-center rounded-full text-[rgb(var(--foreground-secondary))] before:absolute before:-inset-2 before:content-['']",
            @quote.liked_by_me && "text-[rgb(var(--like-heart))]"
          ]}
        >
          <span class="flex items-center -space-x-0.5 rounded-full">
            <span class="flex size-7 items-center justify-center rounded-full transition-colors lg:group-hover/like:bg-white/4">
              <Lucide.heart
                class={[
                  "size-4 transition-colors duration-100 lg:group-hover/like:fill-[rgb(var(--like-heart))] lg:group-hover/like:text-[rgb(var(--like-heart))]",
                  @quote.liked_by_me && "fill-current",
                  @quote.liked_by_me &&
                    "fill-[rgb(var(--like-heart))] text-[rgb(var(--like-heart))]"
                ]}
                aria-hidden
              />
            </span>
            <span
              :if={@quote.likes_count > 0}
              class={[
                "translate-y-px text-xs font-normal tabular-nums transition-colors lg:group-hover/like:text-[rgb(var(--like-heart))]",
                @quote.liked_by_me && "text-[rgb(var(--like-heart))]"
              ]}
            >
              {@quote.likes_count}
            </span>
          </span>
        </button>
      </div>
    </blockquote>
    """
  end
end

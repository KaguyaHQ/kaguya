defmodule KaguyaWeb.VN.Similar do
  @moduledoc """
  Components for the dedicated `/vn/:slug/similar` page.

  The root VN page owns the short recommendation strip; this module owns the
  full-page grid and add/search dialog so the two surfaces can evolve without
  sharing page-specific layout state.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Cover, as: SharedCover

  attr :vn, :map, required: true
  attr :recommendations, :list, required: true

  def page(assigns) do
    ~H"""
    <div class="mx-auto mt-4 mb-[110px] min-h-[calc(100vh-172px)] max-w-[1060px] sm:mb-32 md:mt-8 lg:mt-[64px] lg:mb-[88px]">
      <div class="size-full px-4 pt-2 pb-3 sm:pb-8 md:px-8 md:pt-0">
        <.page_header vn={@vn} />

        <div class="grid grid-cols-1 gap-12 lg:grid-cols-[786px_auto]">
          <div class="mt-6 lg:mt-8">
            <%= if @recommendations != [] do %>
              <ul class="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6">
                <li :for={entry <- @recommendations}>
                  <.similar_item entry={entry} />
                </li>
              </ul>
            <% else %>
              <div class="flex flex-col items-center gap-2 py-16 text-center">
                <p class="text-[15px] text-[rgb(var(--foreground-secondary))]">
                  Nothing recommended yet.
                </p>
                <p class="max-w-[320px] text-[13px] text-[rgb(var(--foreground-tertiary))]">
                  Know one that fits? Use Add to suggest a match.
                </p>
              </div>
            <% end %>
          </div>

          <aside
            class="hidden shrink-0 lg:mt-8 lg:block lg:w-[300px]"
            aria-label={"#{@vn.title} cover"}
          >
            <.link
              navigate={~p"/vn/#{@vn.slug}"}
              class="block w-[245px] overflow-hidden rounded-[6px] bg-[rgb(var(--surface-banner))]"
            >
              <.cover_image
                vn={@vn}
                class="w-full rounded-[6px]"
                fallback_class="aspect-[2/3] w-full rounded-[6px] bg-[rgb(var(--surface-banner))]"
              />
            </.link>
          </aside>
        </div>
      </div>
    </div>
    """
  end

  attr :vn, :map, required: true

  defp page_header(assigns) do
    ~H"""
    <header class="max-lg:flex max-lg:items-center max-lg:gap-3">
      <.link
        navigate={~p"/vn/#{@vn.slug}"}
        class="block aspect-2/3 w-[43px] overflow-hidden rounded-[4px] lg:hidden"
      >
        <.cover_image
          vn={@vn}
          class="aspect-2/3 w-[43px] rounded-[4px] border border-[#97989d] object-cover"
          fallback_class="aspect-[2/3] w-[43px] rounded-[4px] border border-[#97989d] bg-[rgb(var(--surface-banner))]"
        />
      </.link>

      <div class="flex min-w-0 flex-1 flex-col sm:gap-px lg:w-[786px] lg:flex-none">
        <span class="text-sm/5 text-[rgb(var(--foreground-secondary))]">
          Similar to
        </span>
        <div class="flex items-center justify-between gap-3">
          <.link
            navigate={~p"/vn/#{@vn.slug}"}
            class="font-source-serif w-fit truncate text-lg leading-[22px] font-semibold text-[rgb(var(--foreground-primary))] transition lg:text-2xl lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            {@vn.title}
          </.link>
          <button
            type="button"
            phx-click="open_recommendation_dialog"
            class="flex shrink-0 cursor-pointer items-center gap-1.5 rounded-[6px] border border-[rgb(var(--button-border-secondary))] bg-[rgb(var(--button-background-neutral-default))] px-2.5 py-1.5 text-[rgb(var(--button-text-on-neutral))] transition hover:bg-[rgb(var(--button-background-neutral-hover))] active:bg-[rgb(var(--button-background-neutral-pressed))]"
          >
            <Lucide.plus class="size-2.5 text-[rgb(var(--foreground-primary))]" aria-hidden />
            <span class="text-[13px] leading-none font-medium text-[rgb(var(--foreground-primary))]">
              Add
            </span>
          </button>
        </div>
      </div>
    </header>
    """
  end

  attr :entry, :map, required: true

  defp similar_item(assigns) do
    assigns =
      assigns
      |> assign(:vn, assigns.entry.visual_novel)
      |> assign(:vote, Map.get(assigns.entry, :user_vote))
      |> assign(:net_votes, Map.get(assigns.entry, :net_votes, 0))

    ~H"""
    <div
      id={"similar-vn-#{@vn.id}"}
      class="group relative flex flex-col"
      phx-hook="SimilarVnMobileReveal"
      data-mobile-active="false"
    >
      <.link navigate={~p"/vn/#{@vn.slug}"} class="block" title={@vn.title} data-similar-link>
        <.cover_image
          vn={@vn}
          class="aspect-2/3 w-full rounded-[1px] object-cover shadow-[0_4px_10px_rgba(0,0,0,0.35)] lg:rounded-[3px]"
          fallback_class="aspect-[2/3] w-full rounded-[1px] bg-[rgb(var(--surface-banner))] shadow-[0_4px_10px_rgba(0,0,0,0.35)] lg:rounded-[3px]"
        />
      </.link>
      <div
        data-similar-vote-controls
        hidden
        class="absolute bottom-0.5 left-1/2 flex -translate-x-1/2 items-center rounded-full bg-[rgb(var(--surface-overlay))]/90 p-1 opacity-100 transition-opacity duration-200 lg:pointer-events-none lg:bottom-[9px] lg:opacity-0 lg:group-focus-within:pointer-events-auto lg:group-focus-within:opacity-100 lg:group-hover:pointer-events-auto lg:group-hover:opacity-100"
      >
        <.vote_button entry={@entry} vote={@vote} direction={:up} />
        <span class={[
          "min-w-5 text-center text-xs font-bold transition-colors duration-150",
          vote_selected?(@vote, :up) && "text-[rgb(var(--icons-user-star))]",
          vote_selected?(@vote, :down) && "text-[#07BBB8]",
          !vote_selected?(@vote, :up) && !vote_selected?(@vote, :down) && "text-white/90"
        ]}>
          {@net_votes}
        </span>
        <.vote_button entry={@entry} vote={@vote} direction={:down} />
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :vote, :any, default: nil
  attr :direction, :atom, required: true

  defp vote_button(assigns) do
    assigns =
      assigns
      |> assign(:selected?, vote_selected?(assigns.vote, assigns.direction))
      |> assign(:vote_value, Atom.to_string(assigns.direction))
      |> assign(
        :label,
        if(assigns.direction == :up,
          do: "Upvote this recommendation",
          else: "Downvote this recommendation"
        )
      )

    ~H"""
    <button
      type="button"
      phx-click="vote_recommendation"
      phx-value-vn-id={@entry.visual_novel.id}
      phx-value-vote={@vote_value}
      data-vote-control="true"
      aria-label={@label}
      aria-pressed={@selected?}
      class={[
        "cursor-pointer rounded-full p-1.5 transition-colors duration-150",
        @selected? && @direction == :up && "bg-[rgb(var(--icons-user-star))]/20",
        @selected? && @direction == :down && "bg-[#07BBB8]/20",
        !@selected? && "hover:bg-white/10"
      ]}
    >
      <Lucide.arrow_big_up
        class={[
          "size-[18px] transition-colors duration-150",
          @direction == :down && "rotate-180",
          @selected? && @direction == :up &&
            "fill-[rgb(var(--icons-user-star))] text-[rgb(var(--icons-user-star))]",
          @selected? && @direction == :down && "fill-[#07BBB8] text-[#07BBB8]",
          !@selected? && "fill-none text-white/70 hover:text-white"
        ]}
        aria-hidden
      />
    </button>
    """
  end

  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :error, :string, default: nil

  def add_dialog(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="similar-dialog-title"
    >
      <div class="w-full max-w-[437px] overflow-hidden rounded-t-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] shadow-2xl sm:rounded-[16px]">
        <div class="flex items-center justify-between gap-4 border-b border-[rgb(var(--border-divider))] py-3.5 pr-[21px] pl-6">
          <h2
            id="similar-dialog-title"
            class="text-xl font-medium text-[rgb(var(--foreground-primary))] sm:text-2xl"
          >
            Add similar VN
          </h2>
          <button
            type="button"
            phx-click="close_recommendation_dialog"
            class="flex size-11 items-center justify-center rounded-full border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))]"
            aria-label="Close similar VN search"
          >
            <Lucide.x class="size-5" aria-hidden />
          </button>
        </div>
        <div class="p-6 pb-8">
          <.form
            for={%{}}
            as={:recommendation_search}
            phx-change="search_recommendations"
            phx-submit="search_recommendations"
            class="relative"
          >
            <.search_icon
              class="pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2 text-[rgb(var(--foreground-primary))]"
              aria-hidden
            />
            <input
              type="search"
              name="recommendation_search[query]"
              value={@query}
              placeholder="Search visual novels"
              autocomplete="off"
              phx-debounce="300"
              class="h-11 w-full rounded-full border-none bg-white px-4 pl-12 text-sm font-normal text-[#1b1b1b] placeholder:text-[#1b1b1b]/40 focus:outline-none sm:pl-9 dark:bg-white/6 dark:text-[rgb(var(--foreground-primary))] dark:placeholder:text-[rgb(var(--foreground-primary))]/40"
            />
          </.form>

          <p :if={@error} class="mt-4 text-sm text-[rgb(var(--foreground-tertiary))]">
            {@error}
          </p>
          <p
            :if={!@error and String.trim(@query || "") != "" and @results == []}
            class="mt-4 text-sm text-[rgb(var(--foreground-tertiary))]"
          >
            No matches.
          </p>
          <p
            :if={!@error and String.trim(@query || "") == ""}
            class="mt-4 text-sm text-[rgb(var(--foreground-tertiary))]"
          >
            Search for a visual novel to recommend.
          </p>

          <div :if={@results != []} class="mt-4 max-h-[360px] overflow-y-auto">
            <button
              :for={result <- @results}
              type="button"
              phx-click="add_recommendation"
              phx-value-vn-id={result.id}
              phx-value-slug={result.slug}
              phx-value-title={result.title}
              phx-value-image-url={result.image_url}
              class="flex w-full items-center gap-3 rounded-[8px] p-2 text-left transition hover:bg-[rgb(var(--surface-menu-item-hover))]"
            >
              <div class="h-14 w-[38px] shrink-0">
                <KaguyaWeb.SharedComponents.Cover.cover
                  vn={result}
                  sizes="38px"
                  enable_nsfw_reveal
                  class="h-14 w-[38px] rounded-[4px]"
                  fallback_class="rounded-[4px]"
                  alt=""
                />
              </div>
              <span class="min-w-0 flex-1">
                <span class="line-clamp-2 text-sm text-[rgb(var(--foreground-primary))]">
                  {result.title}
                </span>
                <span
                  :if={result.producers != []}
                  class="mt-0.5 block truncate text-xs text-[rgb(var(--foreground-tertiary))]"
                >
                  {producer_text(result.producers)}
                </span>
              </span>
              <span class="flex size-8 shrink-0 items-center justify-center rounded-full border border-[rgb(var(--border-divider))] text-[rgb(var(--foreground-secondary))]">
                +
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :class, :string, required: true
  attr :fallback_class, :string, required: true

  defp cover_image(assigns) do
    ~H"""
    <SharedCover.cover
      vn={@vn}
      sizes="(max-width: 1024px) 33vw, 245px"
      class={@class}
      fallback_class={@fallback_class}
      object_fit="contain"
    />
    """
  end

  defp vote_selected?(vote, direction) when is_atom(vote), do: vote == direction
  defp vote_selected?(1, :up), do: true
  defp vote_selected?(-1, :down), do: true

  defp vote_selected?(vote, direction) when is_binary(vote) do
    normalized = String.downcase(vote)
    normalized == Atom.to_string(direction) or normalized == direction_value(direction)
  end

  defp vote_selected?(_vote, _direction), do: false

  defp direction_value(:up), do: "1"
  defp direction_value(:down), do: "-1"

  defp producer_text(producers) when is_list(producers) do
    producers
    |> Enum.map(fn
      %{"name" => name} -> name
      %{name: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp producer_text(_), do: nil
end

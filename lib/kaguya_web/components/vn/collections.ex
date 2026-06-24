defmodule KaguyaWeb.VN.Collections do
  @moduledoc """
  Sections that show one or more linked VN/character collections under
  the main content column: Characters, More-in-this-series, Related,
  Recommendations, and Popular Lists.

  All sections share the same `cover_card/1` primitive for the 2:3 cover
  link with title, so adjusting cover styling happens in one place.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Lists.Cards, as: ListCards
  alias KaguyaWeb.SharedComponents.Cover, as: SharedCover
  alias Phoenix.LiveView.JS

  import KaguyaWeb.AuthPromptComponents, only: [auth_button: 1]
  import KaguyaWeb.VN.Formatters
  import KaguyaWeb.VN.Shared, only: [section_header: 1]

  # ---------------------------------------------------------------------------
  # Characters — horizontal scroll on mobile, 6-col grid on desktop.
  # ---------------------------------------------------------------------------

  @desktop_initial_character_count 6

  # Mobile keeps horizontal scroll over all characters; desktop starts with
  # one 6-card row and exposes a native details/summary expander when there
  # are more. This keeps the expand affordance client-side without adding a
  # LiveView event.

  attr :characters, :list, required: true
  attr :slug, :string, default: nil
  attr :user_can_edit, :boolean, default: false

  def characters_section(assigns) do
    total = length(assigns.characters)

    assigns =
      assigns
      |> assign(:total_characters, total)
      |> assign(:desktop_has_more?, total > @desktop_initial_character_count)
      |> assign(:desktop_initial_count, @desktop_initial_character_count)
      |> assign(:add_character_href, character_add_href(assigns))

    ~H"""
    <%= if @characters != [] do %>
      <div class="flex flex-col lg:hidden">
        <div class="flex items-center justify-between gap-4 px-4">
          <.characters_title count={@total_characters} />
          <.add_character_link href={@add_character_href} />
        </div>
        <div class="no-scrollbar mt-4 flex gap-1 overflow-x-auto px-4">
          <.character_card :for={character <- @characters} character={character} mobile? />
        </div>
      </div>

      <div
        id={"characters-#{@slug || "vn"}"}
        class="rounded-[12px] p-5 pt-6 max-lg:hidden lg:px-8 lg:py-6"
        data-characters-expanded="false"
      >
        <div class="flex items-center justify-between gap-4">
          <button
            :if={@desktop_has_more?}
            type="button"
            phx-click={
              JS.toggle_class("hidden", to: "#characters-#{@slug || "vn"}-more")
              |> JS.toggle_class("rotate-180", to: "#characters-#{@slug || "vn"}-chev")
            }
            class="flex cursor-pointer items-center text-left"
            aria-label="Toggle characters"
          >
            <.characters_title count={@total_characters} />
            <span
              id={"characters-#{@slug || "vn"}-chev"}
              class="-ml-0.5 translate-y-[2px] p-1 text-[rgb(var(--foreground-secondary))] transition-transform"
            >
              <Lucide.chevron_down class="size-4" aria-hidden />
            </span>
          </button>
          <div :if={!@desktop_has_more?} class="flex items-center">
            <.characters_title count={@total_characters} />
          </div>
          <.add_character_link href={@add_character_href} />
        </div>
        <div class="mt-3 mb-[20px] h-px bg-[rgb(var(--border-divider))]"></div>
        <div class="grid grid-cols-6 gap-5">
          <.character_card
            :for={character <- Enum.take(@characters, @desktop_initial_count)}
            character={character}
          />
        </div>
        <div
          :if={@desktop_has_more?}
          id={"characters-#{@slug || "vn"}-more"}
          class="mt-5 hidden grid-cols-6 gap-5 [&:not(.hidden)]:grid"
        >
          <.character_card
            :for={character <- Enum.drop(@characters, @desktop_initial_count)}
            character={character}
          />
        </div>
      </div>
    <% end %>
    """
  end

  attr :count, :integer, required: true

  defp characters_title(assigns) do
    ~H"""
    <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
      Characters
      <span class="ml-0.5 text-sm font-normal text-[rgb(var(--foreground-primary))]/40">
        ({@count})
      </span>
    </h2>
    """
  end

  attr :href, :string, default: nil

  defp add_character_link(assigns) do
    ~H"""
    <.link
      :if={@href}
      navigate={@href}
      class="flex items-center gap-0.5 text-xs text-[rgb(var(--foreground-tertiary))] transition hover:text-[rgb(var(--foreground-secondary))]"
    >
      <Lucide.plus class="size-[13px]" aria-hidden />
      <span>Add</span>
    </.link>
    """
  end

  attr :character, :map, required: true
  attr :mobile?, :boolean, default: false

  defp character_card(assigns) do
    ~H"""
    <.link
      navigate={"/character/#{@character.slug}"}
      class={[
        "group flex min-w-0 flex-col gap-2",
        @mobile? && "w-[calc((100vw-50px)/4)] max-w-[100px] shrink-0",
        !@mobile? && "flex-1"
      ]}
    >
      <KaguyaWeb.SharedComponents.CharacterImage.character_image
        character={@character}
        sizes="100px"
        class="aspect-square w-full object-cover"
        fallback_class="aspect-square w-full bg-[rgb(var(--surface-banner))]"
        rounded="rounded-[4px]"
      />
      <span class={[
        "group-hover:text-foreground-secondary text-foreground-tertiary font-normal transition-colors",
        @mobile? && "truncate text-xs",
        !@mobile? && "line-clamp-2 text-sm"
      ]}>
        {@character.name}
      </span>
    </.link>
    """
  end

  # ---------------------------------------------------------------------------
  # Series / Related / Recommendations — all 6-col cover grids.
  # ---------------------------------------------------------------------------

  attr :series, :map, default: nil

  def series_section(assigns) do
    ~H"""
    <section :if={@series} class="px-4 lg:rounded-[12px] lg:px-8 lg:py-6">
      <.section_header
        title="More in this series"
        right_label="View series"
        right_href={"/series/#{@series.slug}"}
      />
      <div class="grid grid-cols-3 gap-3 md:grid-cols-6 md:gap-2">
        <.cover_card :for={entry <- @series.entries} vn={entry.visual_novel} show_title={false} />
      </div>
    </section>
    """
  end

  # In prod, Related shows ONLY the relation type label (Fandisc, Side Story,
  # …) under each cover — the title would crowd the row at 6-col.
  attr :relations, :list, required: true

  def related_section(assigns) do
    ~H"""
    <section :if={@relations != []}>
      <div class="flex flex-col px-4 lg:hidden">
        <span class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
          Related
        </span>

        <SharedCover.cover_tooltip_provider id="related-mobile-cover-tooltips">
          <div class="mt-4 grid grid-cols-4 gap-1">
            <SharedCover.cover
              :for={relation <- Enum.take(@relations, 4)}
              vn={relation.related_vn}
              sizes="(max-width: 640px) 25vw, 100px"
              class="aspect-2/3 w-full rounded-[2px] object-cover"
              fallback_class="aspect-[2/3] w-full rounded-[2px] bg-[rgb(var(--surface-banner))]"
              show_title_tooltip
              link
              shadow
            />
          </div>
        </SharedCover.cover_tooltip_provider>
      </div>

      <div class="hidden rounded-[12px] p-5 pt-6 lg:block lg:px-8 lg:py-6">
        <div class="flex items-center gap-4">
          <p class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
            Related
          </p>
        </div>

        <div class="mt-3 mb-5 h-px bg-[rgb(var(--border-divider))]"></div>
        <SharedCover.cover_tooltip_provider id="related-desktop-cover-tooltips">
          <div class="grid grid-cols-6 gap-2">
            <div :for={relation <- Enum.take(@relations, 6)} class="flex flex-col gap-2">
              <SharedCover.cover
                vn={relation.related_vn}
                sizes="(max-width: 640px) 100px, 146px"
                class="aspect-2/3 w-full rounded-[6px] object-cover"
                fallback_class="aspect-[2/3] w-full rounded-[6px] bg-[rgb(var(--surface-banner))]"
                show_title_tooltip
                link
                shadow
              />
              <span
                :if={relation.relation_type}
                class="truncate text-xs text-[rgb(var(--foreground-secondary))]"
              >
                {humanize(relation.relation_type)}
              </span>
            </div>
          </div>
        </SharedCover.cover_tooltip_provider>
      </div>
    </section>
    """
  end

  # In prod, Recommendations is a clean strip of covers with no captions —
  # title-on-hover only. Rendering the title under every cover was the
  # main "noisy" diff.
  attr :recommendations, :list, required: true
  attr :slug, :string, required: true
  attr :user_can_edit, :boolean, default: true
  attr :is_logged_in, :boolean, default: false

  def recommendations_section(assigns) do
    assigns =
      assigns
      |> assign(:visible_recommendations, Enum.take(assigns.recommendations, 6))
      |> assign(:has_more_mobile?, length(assigns.recommendations) > 4)
      |> assign(:has_more_desktop?, length(assigns.recommendations) > 6)
      |> assign(:similar_href, "/vn/#{assigns.slug}/similar")

    ~H"""
    <section class="px-4 lg:rounded-[12px] lg:px-8 lg:py-6">
      <div class="flex items-center justify-between gap-4">
        <.link
          navigate={@similar_href}
          class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))] transition lg:hover:text-[rgb(var(--text-link-hover))]"
        >
          Recommendations
        </.link>
        <div class="flex items-center gap-3">
          <.link
            :if={@has_more_mobile? || @has_more_desktop?}
            navigate={@similar_href}
            class={[
              "text-xs font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase transition hover:text-[rgb(var(--text-link-hover))]",
              @has_more_mobile? && !@has_more_desktop? && "md:hidden",
              !@has_more_mobile? && @has_more_desktop? && "max-lg:hidden"
            ]}
          >
            More
          </.link>
          <button
            :if={@user_can_edit}
            type="button"
            phx-click="open_recommendation_dialog"
            class="flex cursor-pointer items-center gap-1.5 rounded-[6px] border border-[rgb(var(--button-border-secondary))] bg-[rgb(var(--button-background-neutral-default))] px-2.5 py-1.5 text-[rgb(var(--button-text-on-neutral))] transition-colors hover:bg-[rgb(var(--button-background-neutral-hover))] active:bg-[rgb(var(--button-background-neutral-pressed))]"
          >
            <Lucide.plus class="size-2.5" aria-hidden />
            <span class="text-[13px] leading-none font-medium">Add</span>
          </button>
        </div>
      </div>
      <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] md:block"></div>
      <div
        :if={@recommendations == []}
        class="flex flex-col items-center justify-center py-10 max-lg:mt-2"
      >
        <p class="text-foreground-secondary text-sm">Nothing recommended yet</p>
        <p class="text-foreground-tertiary mt-1 text-xs">
          Know one that fits? Use Add to suggest a match.
        </p>
      </div>
      <div :if={@recommendations != []} class="mt-4 grid grid-cols-4 gap-1 md:grid-cols-6 md:gap-2">
        <.recommendation_card
          :for={{entry, idx} <- Enum.with_index(@visible_recommendations)}
          entry={entry}
          mobile_visible?={idx < 4}
          is_logged_in={@is_logged_in}
        />
      </div>
    </section>
    """
  end

  attr :entry, :map, required: true
  attr :mobile_visible?, :boolean, default: true
  attr :is_logged_in, :boolean, default: false

  defp recommendation_card(assigns) do
    assigns =
      assign(assigns,
        vote: Map.get(assigns.entry, :user_vote),
        net_votes: Map.get(assigns.entry, :net_votes, 0),
        card_id: recommendation_card_id(assigns.entry)
      )

    ~H"""
    <div
      id={@card_id}
      phx-hook="MobileRecommendationVote"
      data-vote-control
      data-vn-recommendation-item
      class={["group/rec relative flex min-w-0 flex-col", !@mobile_visible? && "max-md:hidden"]}
    >
      <div class="relative">
        <.cover_card vn={@entry.visual_novel} show_title={false} />
        <div class="vn-recommendation-vote-controls absolute bottom-[2px] left-1/2 flex -translate-x-1/2 items-center rounded-full bg-[rgb(var(--surface-overlay))]/90 p-1 text-white transition-opacity duration-200 lg:bottom-[9px] lg:group-focus-within/rec:pointer-events-auto lg:group-focus-within/rec:opacity-100 lg:group-hover/rec:pointer-events-auto lg:group-hover/rec:opacity-100">
          <.recommendation_vote_button
            entry={@entry}
            vote={@vote}
            direction={:up}
            is_logged_in={@is_logged_in}
          />
          <span class={[
            "min-w-5 text-center text-xs font-bold tabular-nums transition-colors duration-150",
            vote_count_class(@vote)
          ]}>
            {@net_votes}
          </span>
          <.recommendation_vote_button
            entry={@entry}
            vote={@vote}
            direction={:down}
            is_logged_in={@is_logged_in}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :vote, :any, default: nil
  attr :direction, :atom, required: true
  attr :is_logged_in, :boolean, default: false

  defp recommendation_vote_button(assigns) do
    assigns =
      assigns
      |> assign(:selected?, vote_selected?(assigns.vote, assigns.direction))
      |> assign(:label, if(assigns.direction == :up, do: "Upvote", else: "Downvote"))
      |> assign(:vote_value, Atom.to_string(assigns.direction))

    ~H"""
    <.auth_button
      event="vote_recommendation"
      is_logged_in={@is_logged_in}
      modal_id="vn-auth-prompt"
      auth_message="Sign in to vote on recommendations"
      phx-value-vn-id={@entry.visual_novel.id}
      phx-value-vote={@vote_value}
      aria-label={"#{@label} this recommendation"}
      aria-pressed={@selected?}
      class={[
        "flex cursor-pointer items-center justify-center rounded-full p-1.5 transition-colors duration-150 hover:bg-white/10",
        @selected? && @direction == :up && "bg-[rgb(var(--icons-user-star))]/20",
        @selected? && @direction == :down && "bg-[#07BBB8]/20"
      ]}
    >
      <%= if @direction == :up do %>
        <Lucide.arrow_big_up
          class={[
            "vote-arrow size-[18px] transition-colors duration-150",
            @selected? && "fill-[rgb(var(--icons-user-star))] text-[rgb(var(--icons-user-star))]",
            !@selected? && "fill-transparent text-white/70 hover:text-white"
          ]}
          aria-hidden
        />
      <% else %>
        <Lucide.arrow_big_down
          class={[
            "vote-arrow size-[18px] transition-colors duration-150",
            @selected? && "fill-[#07BBB8] text-[#07BBB8]",
            !@selected? && "fill-transparent text-white/70 hover:text-white"
          ]}
          aria-hidden
        />
      <% end %>
    </.auth_button>
    """
  end

  # ---------------------------------------------------------------------------
  # Popular Lists — stacked covers + list metadata.
  # ---------------------------------------------------------------------------

  attr :lists, :list, required: true
  attr :slug, :string, default: nil

  def popular_lists_section(assigns) do
    assigns =
      assigns
      |> assign(:lists_href, if(present?(assigns.slug), do: "/vn/#{assigns.slug}/lists"))

    ~H"""
    <section :if={@lists != []} class="px-4 lg:px-8">
      <div class="flex items-center justify-between gap-4">
        <%= if @lists_href do %>
          <.link
            navigate={@lists_href}
            class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))] transition lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            Popular Lists
          </.link>
        <% else %>
          <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
            Popular Lists
          </h2>
        <% end %>
        <.link
          :if={@lists_href}
          navigate={@lists_href}
          class="text-xs font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase transition hover:text-[rgb(var(--text-link-hover))]"
        >
          More
        </.link>
      </div>
      <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] md:block"></div>
      <div class="mt-4 flex flex-col gap-5 lg:mt-0 lg:gap-6">
        <div :for={list <- Enum.take(@lists, 3)} id={"popular-list-#{list.id}"}>
          <ListCards.list_row list={list} />
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared 2:3 cover card with title + optional subtitle. Used by series,
  # related, recommendations.
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :subtitle, :string, default: nil
  attr :show_title, :boolean, default: true

  defp cover_card(assigns) do
    ~H"""
    <.link navigate={~p"/vn/#{@vn.slug}"} class="group flex min-w-0 flex-col gap-1">
      <SharedCover.cover
        vn={@vn}
        sizes="(max-width: 768px) 25vw, 160px"
        class="aspect-2/3 w-full rounded-[2px] object-cover lg:rounded-[6px]"
        fallback_class="aspect-[2/3] w-full rounded-[2px] bg-[rgb(var(--surface-banner))] lg:rounded-[6px]"
        shadow
      />
      <p
        :if={@show_title}
        class="line-clamp-2 text-xs text-[rgb(var(--foreground-tertiary))] transition group-hover:text-[rgb(var(--text-link-hover))] lg:text-sm"
      >
        {@vn.title}
      </p>
      <p
        :if={@subtitle}
        class="text-[11px] font-normal text-[rgb(var(--foreground-tertiary))]"
      >
        {@subtitle}
      </p>
    </.link>
    """
  end

  defp character_add_href(%{slug: slug, user_can_edit: true}) when is_binary(slug) and slug != "",
    do: "/contribute/character?vn=#{slug}"

  defp character_add_href(_assigns), do: nil

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

  defp recommendation_card_id(%{visual_novel: %{id: id}}) when not is_nil(id),
    do: "vn-recommendation-#{id}"

  defp recommendation_card_id(%{visual_novel: %{slug: slug}}) when is_binary(slug) and slug != "",
    do: "vn-recommendation-#{slug}"

  defp recommendation_card_id(_entry), do: "vn-recommendation-unknown"

  defp vote_count_class(1), do: "text-[rgb(var(--icons-user-star))]"
  defp vote_count_class(-1), do: "text-[#07BBB8]"
  defp vote_count_class("1"), do: "text-[rgb(var(--icons-user-star))]"
  defp vote_count_class("-1"), do: "text-[#07BBB8]"
  defp vote_count_class(:up), do: "text-[rgb(var(--icons-user-star))]"
  defp vote_count_class(:down), do: "text-[#07BBB8]"
  defp vote_count_class(_vote), do: "text-white/90"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end

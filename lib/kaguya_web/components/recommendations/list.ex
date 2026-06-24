defmodule KaguyaWeb.Components.Recommendations.List do
  @moduledoc """
  Profile recommendation list components ported from the Next
  `RecommendationList` list variant.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.SharedComponents.Cover

  attr :recs, :list, required: true
  attr :tag_counts, :list, default: []
  attr :selected_tag_slug, :string, default: nil
  attr :tag_filter_query, :string, default: ""
  attr :hide_wishlisted, :boolean, default: false
  attr :show_wishlist_toggle, :boolean, default: false
  attr :is_own_profile, :boolean, default: false
  attr :mode, :atom, default: :other_user
  attr :signals_count, :integer, default: 0
  attr :signals_required, :integer, default: 3
  attr :is_refreshing, :boolean, default: false
  attr :has_active_filter, :boolean, default: false
  attr :empty_filtered, :boolean, default: false
  attr :vndb_user_id, :string, default: nil
  attr :current_user, :map, default: nil

  def recommendation_list(assigns) do
    assigns =
      assigns
      |> assign(:selected_tag, selected_tag(assigns.tag_counts, assigns.selected_tag_slug))
      |> assign(:active_count, active_count(assigns.selected_tag_slug, assigns.hide_wishlisted))
      |> assign(:guest?, assigns.mode == :guest_vndb)

    ~H"""
    <section aria-labelledby="profile-recommendations-heading">
      <h2 id="profile-recommendations-heading" class="sr-only">Recommendations</h2>

      <div
        :if={!@guest? and (@recs != [] or @has_active_filter)}
        class="mb-4 flex items-start justify-between gap-3"
      >
        <.filters
          tag_counts={@tag_counts}
          selected_tag={@selected_tag}
          tag_filter_query={@tag_filter_query}
          active_count={@active_count}
          hide_wishlisted={@hide_wishlisted}
          show_wishlist_toggle={@show_wishlist_toggle}
        />

        <.refresh_button :if={@is_own_profile} is_refreshing={@is_refreshing} variant={:icon} />
      </div>

      <%= cond do %>
        <% @recs == [] and @empty_filtered -> %>
          <.empty_filtered />
        <% @recs == [] -> %>
          <.empty_state
            mode={@mode}
            vndb_user_id={@vndb_user_id}
            signals_count={@signals_count}
            signals_required={@signals_required}
            is_refreshing={@is_refreshing}
          />
        <% true -> %>
          <div class={["flex flex-col sm:gap-10", if(@is_own_profile, do: "gap-6", else: "gap-8")]}>
            <.rec_card
              :for={rec <- @recs}
              rec={rec}
              is_own_profile={@is_own_profile}
              is_guest={@guest?}
              current_user={@current_user}
            />
          </div>
      <% end %>
    </section>
    """
  end

  attr :tag_counts, :list, required: true
  attr :selected_tag, :map, default: nil
  attr :tag_filter_query, :string, required: true
  attr :active_count, :integer, required: true
  attr :hide_wishlisted, :boolean, required: true
  attr :show_wishlist_toggle, :boolean, required: true

  defp filters(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col items-start gap-2">
      <details
        id="rec-tag-filter-menu"
        class="group/filter relative"
        phx-hook="ClientTagFilter"
      >
        <summary
          class={[
            "inline-flex h-8 shrink-0 cursor-pointer list-none items-center gap-1.5 rounded-full border px-3 text-[12px] font-medium transition-colors [&::-webkit-details-marker]:hidden",
            @active_count > 0 &&
              "border-[rgb(var(--foreground-tertiary)/0.6)] text-[rgb(var(--foreground-primary))]",
            @active_count == 0 &&
              "border-[rgb(var(--border-divider))] text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
          ]}
          aria-haspopup="dialog"
          aria-label={filter_summary_label(@active_count)}
        >
          <Lucide.list_filter class="size-3.5" aria-hidden />
          <span>
            Filter<%= if @active_count > 0 do %>
              · {@active_count}
            <% end %>
          </span>
        </summary>

        <div
          role="dialog"
          aria-label="Recommendation filters"
          class="absolute left-0 z-40 mt-1.5 w-[280px] overflow-hidden rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-2 shadow-xl"
        >
          <div class="relative">
            <.search_icon
              class="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-[rgb(var(--foreground-tertiary))]"
              aria-hidden
            />
            <input
              id="rec-tag-filter-query"
              type="search"
              value={@tag_filter_query}
              placeholder="Search tags…"
              aria-label="Search tags"
              autocomplete="off"
              data-client-tag-filter-input
              class="h-8 w-full rounded-md bg-transparent pr-2 pl-8 text-[13px] text-[rgb(var(--foreground-primary))] outline-none placeholder:text-[rgb(var(--foreground-tertiary))]"
            />
          </div>

          <div id="rec-filter-tag-options" class="mt-1 max-h-[240px] overflow-y-auto">
            <button
              :for={tag <- @tag_counts}
              type="button"
              phx-click="set_tag_filter"
              phx-value-slug={tag.slug}
              aria-pressed={to_string(tag_selected?(@selected_tag, tag))}
              value={tag.slug}
              data-client-tag-filter-option
              data-tag-name={tag_search_text(tag)}
              class={[
                "flex h-8 w-full items-center justify-between rounded-md px-2 text-left text-[13px] transition-colors",
                tag_selected?(@selected_tag, tag) &&
                  "bg-white/6 font-medium text-[rgb(var(--foreground-primary))]",
                !tag_selected?(@selected_tag, tag) &&
                  "text-[rgb(var(--foreground-secondary))] hover:bg-white/4"
              ]}
            >
              <span class="truncate">{tag.name}</span>
              <span class="ml-2 shrink-0 text-xs text-[rgb(var(--foreground-tertiary))] tabular-nums">
                {tag.count}
              </span>
            </button>

            <p
              data-client-tag-filter-empty
              hidden
              class="px-2 py-3 text-center text-[13px] text-[rgb(var(--foreground-tertiary))]"
            >
              No tags found
            </p>
          </div>

          <div
            :if={@show_wishlist_toggle}
            class="mt-2 border-t border-[rgb(var(--border-divider))] pt-2"
          >
            <button
              type="button"
              phx-click="toggle_hide_wishlisted"
              role="switch"
              aria-checked={to_string(@hide_wishlisted)}
              aria-label="Hide wishlisted recommendations"
              class="flex w-full items-center justify-between p-1 text-[13px] text-[rgb(var(--foreground-secondary))]"
            >
              <span>Hide wishlisted</span>
              <span class={[
                "relative h-5 w-9 rounded-full transition",
                if(@hide_wishlisted,
                  do: "bg-[rgb(var(--foreground-secondary))]",
                  else: "bg-[rgb(var(--surface-menu-item-hover))]"
                )
              ]}>
                <span class={[
                  "absolute top-0.5 size-4 rounded-full bg-[rgb(var(--surface-base))] transition",
                  if(@hide_wishlisted, do: "left-[18px]", else: "left-0.5")
                ]} />
              </span>
            </button>
          </div>
        </div>
      </details>

      <div :if={@active_count > 0} class="flex flex-wrap items-center gap-1.5">
        <.filter_chip
          :if={@selected_tag}
          label={@selected_tag.name}
          event="clear_tag_filter"
        />
        <.filter_chip
          :if={@hide_wishlisted}
          label="Wishlisted hidden"
          event="toggle_hide_wishlisted"
        />
        <button
          :if={@active_count >= 2}
          type="button"
          phx-click="clear_rec_filters"
          class="-my-1 ml-1 p-1 text-[11px] text-[rgb(var(--foreground-tertiary))] underline underline-offset-2 hover:text-[rgb(var(--foreground-secondary))]"
        >
          Clear all
        </button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :event, :string, required: true

  defp filter_chip(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.FilterChip.filter_chip
      label={@label}
      shape="pill"
      class="max-w-[160px]"
      phx-click={@event}
      aria-label={"Remove #{@label} filter"}
      icon_x
    />
    """
  end

  attr :is_refreshing, :boolean, required: true
  attr :variant, :atom, default: :icon

  defp refresh_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="refresh_recommendations"
      disabled={@is_refreshing}
      aria-label={
        if @is_refreshing, do: "Refreshing recommendations", else: "Refresh recommendations"
      }
      title="Refreshes every 5 minutes."
      class={[
        "inline-flex shrink-0 items-center border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))] disabled:cursor-wait disabled:opacity-60",
        if(@variant == :icon,
          do: "size-8 justify-center rounded-full",
          else: "h-8 gap-1.5 rounded-full px-3 text-[12px] font-medium"
        )
      ]}
    >
      <Lucide.refresh_cw class={["size-3.5", @is_refreshing && "animate-spin"]} aria-hidden />
      <span :if={@variant == :labeled}>{if @is_refreshing, do: "Refreshing…", else: "Refresh"}</span>
    </button>
    """
  end

  attr :mode, :atom, required: true
  attr :signals_count, :integer, required: true
  attr :signals_required, :integer, required: true
  attr :is_refreshing, :boolean, required: true
  attr :vndb_user_id, :string, default: nil

  defp empty_state(assigns) do
    assigns = assign(assigns, :eligible?, assigns.signals_count >= assigns.signals_required)

    ~H"""
    <%= if @mode == :guest_vndb do %>
      <div class="flex flex-col items-center gap-2 py-16 text-center">
        <p class="text-sm text-[rgb(var(--foreground-secondary))]">
          No recommendations for {@vndb_user_id || "this VNDB user"}.
        </p>
        <p class="max-w-[380px] text-[13px] text-[rgb(var(--foreground-tertiary))]">
          Either the VNDB user has fewer than 3 rated or labeled VNs that exist in our catalog.
        </p>
      </div>
    <% else %>
      <%= if @mode == :other_user do %>
        <div class="flex flex-col items-center gap-2 py-16 text-center">
          <p class="text-sm text-[rgb(var(--foreground-secondary))]">
            No recommendations to show yet.
          </p>
          <p class="max-w-[320px] text-[13px] text-[rgb(var(--foreground-tertiary))]">
            Once they rate or shelve more VNs, personalized picks will appear here.
          </p>
        </div>
      <% else %>
        <div class="flex flex-col items-center gap-3 py-16 text-center">
          <p class="text-sm text-[rgb(var(--foreground-secondary))]">
            <%= if @eligible? do %>
              No recommendations yet — generate your first set.
            <% else %>
              Please rate at least {@signals_required} visual novels to generate recommendations.
            <% end %>
          </p>
          <p class="max-w-[340px] text-[13px] text-[rgb(var(--foreground-tertiary))]">
            <%= if @eligible? do %>
              We'll pull personalized picks from your ratings and library. The more you rate, the better the picks.
            <% else %>
              The more VNs you rate and add to your library, the better your recommendations will be.
            <% end %>
          </p>
          <.refresh_button is_refreshing={@is_refreshing} variant={:labeled} />
        </div>
      <% end %>
    <% end %>
    """
  end

  defp empty_filtered(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 py-16 text-center">
      <p class="text-sm text-[rgb(var(--foreground-tertiary))]">
        No recommendations match the current filters.
      </p>
      <button
        type="button"
        phx-click="clear_rec_filters"
        class="text-[13px] text-[rgb(var(--foreground-secondary))] underline underline-offset-2 hover:text-[rgb(var(--foreground-primary))]"
      >
        Clear filters
      </button>
    </div>
    """
  end

  attr :rec, :map, required: true
  attr :is_own_profile, :boolean, required: true
  attr :is_guest, :boolean, default: false
  attr :current_user, :map, default: nil

  defp rec_card(assigns) do
    screenshots = hero_screenshots(assigns.rec.visual_novel, assigns.current_user)

    assigns =
      assigns
      |> assign(:vn, assigns.rec.visual_novel)
      |> assign(:href, vn_href(assigns.rec.visual_novel))
      |> assign(:screenshots, screenshots)
      |> assign(:tags, content_tags(assigns.rec.visual_novel))
      |> assign(:has_hero, length(screenshots) >= 2)

    ~H"""
    <article>
      <.link :if={@has_hero} navigate={@href} class="block">
        <div class={[
          "grid gap-0.5 overflow-hidden rounded-lg",
          if(length(@screenshots) == 2, do: "grid-cols-2", else: "grid-cols-3")
        ]}>
          <div :for={screenshot <- @screenshots} class="aspect-video overflow-hidden">
            <img
              src={screenshot_src(screenshot)}
              alt=""
              loading="lazy"
              decoding="async"
              class="size-full object-cover transition-transform duration-300 hover:scale-105"
            />
          </div>
        </div>
      </.link>

      <div class={@has_hero && "mt-4 sm:mt-5"}>
        <div class={!@has_hero && "flex gap-4"}>
          <.link :if={!@has_hero} navigate={@href} class="shrink-0">
            <Cover.cover vn={@vn} sizes="80px" class="aspect-2/3 w-16 rounded sm:w-20" />
          </.link>

          <div class={!@has_hero && "min-w-0 flex-1"}>
            <div class="flex items-start gap-3">
              <.link
                navigate={@href}
                class="font-source-serif line-clamp-2 min-w-0 flex-1 text-xl/tight font-semibold text-[rgb(var(--foreground-primary))] sm:text-2xl"
              >
                <span class="decoration-1 underline-offset-[6px] hover:underline">{@vn.title}</span>
              </.link>
              <span
                aria-label={"#{@rec.relevance_pct || 0}% match"}
                class={[
                  "shrink-0 text-xl/tight font-semibold tabular-nums sm:text-2xl",
                  if((@rec.relevance_pct || 0) >= 70,
                    do: "text-[rgb(var(--foreground-primary))]",
                    else: "text-[rgb(var(--foreground-tertiary))]"
                  )
                ]}
              >
                {@rec.relevance_pct || 0}<span class="ml-0.5 text-sm font-medium opacity-60">%</span>
              </span>
            </div>

            <div :if={@rec.because_you_liked != []} class="mt-1.5">
              <.reason_tag
                items={@rec.because_you_liked}
                total_positive_contribution={@rec.total_positive_contribution}
                is_own_profile={@is_own_profile}
                is_guest={@is_guest}
              />
            </div>

            <div
              :if={@tags != []}
              class="mt-2 line-clamp-1 text-xs text-[rgb(var(--foreground-tertiary))]"
            >
              <span :for={{tag, index} <- Enum.with_index(@tags)}>
                <span :if={index > 0} class="mx-2 opacity-40">·</span>{tag.name}
              </span>
            </div>

            <.feedback :if={@is_own_profile} rec={@rec} />
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :rec, :map, required: true

  defp feedback(assigns) do
    assigns =
      assigns
      |> assign(:status, get_in(assigns.rec, [:user_reading_status, :status]))
      |> assign(
        :saved?,
        get_in(assigns.rec, [:user_reading_status, :status]) in [
          :want_to_read,
          "want_to_read",
          "WANT_TO_READ"
        ]
      )

    ~H"""
    <div class="mt-4">
      <%= if @rec[:dismissed?] do %>
        <div
          role="status"
          aria-live="polite"
          class="inline-flex items-center gap-2 text-[11px] text-[rgb(var(--foreground-tertiary))]"
        >
          <span class="italic">Not interested.</span>
          <button
            type="button"
            phx-click="undo_dismiss_rec"
            phx-value-vn-id={@rec.visual_novel.id}
            class="-m-2 p-2 font-medium text-[rgb(var(--foreground-secondary))] underline underline-offset-2 hover:text-[rgb(var(--foreground-primary))]"
          >
            Undo
          </button>
        </div>
      <% else %>
        <div class="-ml-2 flex items-center gap-2">
          <button
            type="button"
            phx-click={if @saved?, do: "undo_wishlist_rec", else: "wishlist_rec"}
            phx-value-vn-id={@rec.visual_novel.id}
            aria-label={if @saved?, do: "Remove from wishlist", else: "Add to wishlist"}
            class={[
              "flex items-center gap-1.5 rounded-md p-2 text-[11px] transition-colors hover:bg-[rgb(var(--surface-elevated))]",
              if(@saved?,
                do:
                  "text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-tertiary))]",
                else:
                  "text-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-secondary))]"
              )
            ]}
          >
            <Lucide.bookmark class={["size-3.5", @saved? && "fill-current"]} aria-hidden />
            <span>{if @saved?, do: "Wishlisted", else: "Wishlist"}</span>
          </button>

          <button
            type="button"
            phx-click="dismiss_rec"
            phx-value-vn-id={@rec.visual_novel.id}
            aria-label="Not interested"
            class="flex items-center gap-1.5 rounded-md p-2 text-[11px] text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-[rgb(var(--surface-elevated))] hover:text-[rgb(var(--foreground-secondary))]"
          >
            <Lucide.x class="size-3.5" aria-hidden />
            <span>Not interested</span>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :total_positive_contribution, :any, default: nil
  attr :is_own_profile, :boolean, default: false
  attr :is_guest, :boolean, default: false

  defp reason_tag(assigns) do
    assigns =
      assigns
      |> assign(:primary, primary_reason(assigns.items))
      |> assign(:groups, reason_groups(assigns.items))

    ~H"""
    <span
      :if={@primary}
      tabindex="0"
      aria-label="Show why this VN was recommended"
      class="group/reason relative inline-flex w-fit max-w-full cursor-default items-center gap-1 text-sm text-[rgb(var(--foreground-secondary))] transition-colors outline-none hover:text-[rgb(var(--foreground-primary))]"
    >
      <span class="truncate">{inline_reason(@primary, @is_own_profile, @is_guest)}</span>
      <span class="pointer-events-none absolute top-full left-0 z-40 mt-2 hidden w-[320px] max-w-[min(320px,80vw)] rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-3 text-left text-xs font-normal text-[rgb(var(--foreground-primary))] shadow-xl group-hover/reason:block group-focus/reason:block">
        <.reason_tooltip
          groups={@groups}
          total_positive_contribution={@total_positive_contribution}
          is_guest={@is_guest}
        />
      </span>
    </span>
    """
  end

  attr :groups, :list, required: true
  attr :total_positive_contribution, :any, default: nil
  attr :is_guest, :boolean, default: false

  defp reason_tooltip(assigns) do
    assigns =
      assign(
        assigns,
        :can_show_pct,
        is_number(assigns.total_positive_contribution) and assigns.total_positive_contribution > 0
      )

    ~H"""
    <div class="space-y-2 text-xs font-normal">
      <div :for={group <- @groups}>
        <div class="mb-0.5 text-[10px] font-semibold tracking-[0.08em] uppercase opacity-60">
          {group.label}
        </div>
        <ul class="space-y-0.5">
          <li :for={item <- group.items} class="flex items-baseline gap-3">
            <span class="truncate">{item.visual_novel.title}</span>
            <span class="ml-auto inline-flex shrink-0 items-baseline gap-1 tabular-nums opacity-80">
              <span
                :if={group.key == :rated and is_number(item.user_rating)}
                class="inline-flex items-center gap-0.5"
              >
                {format_rating(item.user_rating)}★
              </span>
              <span :if={@can_show_pct and is_number(item.contribution)} class="w-7 text-right">
                {round(item.contribution / @total_positive_contribution * 100)}%
              </span>
            </span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp selected_tag(_tags, nil), do: nil
  defp selected_tag(tags, slug), do: Enum.find(tags, &(to_string(&1.slug) == to_string(slug)))

  defp tag_selected?(nil, _tag), do: false
  defp tag_selected?(selected_tag, tag), do: selected_tag.slug == tag.slug

  defp active_count(tag_slug, hide_wishlisted) do
    if(tag_slug, do: 1, else: 0) + if hide_wishlisted, do: 1, else: 0
  end

  defp filter_summary_label(0), do: "Open recommendation filters"
  defp filter_summary_label(count), do: "Open recommendation filters, #{count} active"

  defp tag_search_text(tag), do: tag.name |> to_string() |> String.downcase()

  defp vn_href(%{slug: slug}) when is_binary(slug), do: "/vn/#{slug}"
  defp vn_href(_vn), do: "#"

  defp hero_screenshots(%{screenshots: screenshots}, current_user) when is_list(screenshots) do
    show_nsfw = Map.get(current_user || %{}, :show_nsfw_screenshots, false)
    show_brutal = Map.get(current_user || %{}, :show_brutal_screenshots, false)

    screenshots
    |> Enum.reject(&screenshot_hidden_by_prefs?(&1, show_nsfw, show_brutal))
    |> Enum.filter(&(screenshot_src(&1) not in [nil, ""]))
    |> Enum.take(3)
  end

  defp hero_screenshots(_, _), do: []

  defp screenshot_hidden_by_prefs?(screenshot, show_nsfw, show_brutal) do
    nsfw? = Map.get(screenshot, :is_nsfw) || Map.get(screenshot, "is_nsfw") || false
    brutal? = Map.get(screenshot, :is_brutal) || Map.get(screenshot, "is_brutal") || false
    (nsfw? and not show_nsfw) or (brutal? and not show_brutal)
  end

  defp screenshot_src(%{images: images}) when is_map(images),
    do: images[:medium] || images["medium"] || images[:small] || images["small"]

  defp screenshot_src(_), do: nil

  defp content_tags(%{tags: tags}) when is_list(tags) do
    tags
    |> Enum.filter(fn tag ->
      spoiler = tag[:spoiler_level] || tag["spoiler_level"]

      category =
        get_in(tag, [:tag, :category]) || get_in(tag, ["tag", "category"]) || tag[:category]

      spoiler in [nil, :none, "NONE", "none", 0] and category in [:content, "CONTENT", "content"]
    end)
    |> Enum.take(5)
    |> Enum.map(fn tag ->
      tag[:tag] || tag["tag"] || tag
    end)
  end

  defp content_tags(_), do: []

  @reason_order [:rated, :read, :currently_reading, :did_not_finish, :on_hold, :want_to_read]

  defp primary_reason(items) do
    Enum.find_value(items, fn item ->
      with key when not is_nil(key) <- reason_key(item),
           title when is_binary(title) <- get_in(item, [:visual_novel, :title]) do
        %{key: key, title: title, rating: item[:user_rating]}
      else
        _ -> nil
      end
    end)
  end

  defp reason_groups(items) do
    buckets =
      Enum.reduce(items, %{}, fn item, acc ->
        case reason_key(item) do
          nil -> acc
          key -> Map.update(acc, key, [item], &(&1 ++ [item]))
        end
      end)

    @reason_order
    |> Enum.map(fn key ->
      %{key: key, label: reason_label(key), items: Map.get(buckets, key, [])}
    end)
    |> Enum.reject(&(&1.items == []))
    |> Enum.sort_by(&group_sort_key/1)
  end

  defp group_sort_key(group) do
    max_contribution =
      group.items
      |> Enum.map(&(&1[:contribution] || 0))
      |> Enum.max(fn -> 0 end)

    {-max_contribution, Enum.find_index(@reason_order, &(&1 == group.key)) || 99}
  end

  defp reason_key(%{user_rating: rating}) when is_number(rating), do: :rated

  defp reason_key(%{user_status: status}) when not is_nil(status) do
    case status |> to_string() |> String.downcase() do
      "read" -> :read
      "currently_reading" -> :currently_reading
      "did_not_finish" -> :did_not_finish
      "on_hold" -> :on_hold
      "want_to_read" -> :want_to_read
      _ -> nil
    end
  end

  defp reason_key(_), do: nil

  defp reason_label(:rated), do: "Rated"
  defp reason_label(:read), do: "Read"
  defp reason_label(:currently_reading), do: "Reading"
  defp reason_label(:did_not_finish), do: "Did not finish"
  defp reason_label(:on_hold), do: "Paused"
  defp reason_label(:want_to_read), do: "Wishlisted"

  defp inline_reason(primary, is_own_profile, is_guest) do
    subject = if is_own_profile, do: "you", else: "they"

    suffix =
      if primary.key == :rated and is_number(primary.rating),
        do: " #{format_rating_badge(primary.rating, is_guest)}",
        else: ""

    "Because #{subject} #{reason_verb(primary.key)} #{primary.title}#{suffix}"
  end

  defp reason_verb(:rated), do: "rated"
  defp reason_verb(:read), do: "read"
  defp reason_verb(:currently_reading), do: "are reading"
  defp reason_verb(:did_not_finish), do: "didn't finish"
  defp reason_verb(:on_hold), do: "paused"
  defp reason_verb(:want_to_read), do: "wishlisted"

  defp format_rating_badge(rating, _is_guest), do: "#{format_rating(rating)}★"

  defp format_rating(rating) when is_integer(rating), do: Integer.to_string(rating)

  defp format_rating(rating) when is_float(rating) and rating == trunc(rating) * 1.0,
    do: Integer.to_string(trunc(rating))

  defp format_rating(rating) when is_float(rating),
    do: :erlang.float_to_binary(rating, decimals: 1)
end

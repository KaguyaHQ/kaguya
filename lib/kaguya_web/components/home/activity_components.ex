defmodule KaguyaWeb.Home.ActivityComponents do
  @moduledoc """
  Compact activity rail for the signed-in home page.

    * Per-row avatar + actor link + verb sentence + relative timestamp.
    * Same-actor follow-ups collapse — avatar hidden, indented `ml-[38px]`,
      smaller text.
    * Server-grouped entries (`group_size > 1`) render as a single
      summary sentence (`liked 50 covers from <vn>`, `started reading
      <vn₀> and <vn₁>`, `followed <a> and <b>`).
    * Reviews and lists are excluded from the activity stream on every
      surface — they live in the home feed and on `/reviews` / `/lists`.

  Verb resolution and href mapping are shared with the profile activity
  feed via `KaguyaWeb.Components.Activity.Helpers` and the inline verb
  phrases via `KaguyaWeb.Components.Activity.Verbs`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.SharedComponents.SegmentedControl
  import KaguyaWeb.VN.Icons, only: [display_ratings: 1]

  alias KaguyaWeb.Components.Activity.Helpers
  alias KaguyaWeb.Components.Activity.Verbs
  alias KaguyaWeb.Lists.Cards, as: ListCards
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  # ---------------------------------------------------------------------------
  # Top-level: tab header, empty state, list of entries.
  # ---------------------------------------------------------------------------

  attr :activity, :map, required: true
  attr :active_type, :atom, default: :global
  attr :bounded, :boolean, default: false
  attr :mobile, :boolean, default: false

  attr :has_follows?, :boolean,
    default: false,
    doc:
      "When false, the Friends/Global filter is suppressed entirely — its only state would be an empty list, so the control wouldn't earn its place."

  attr :can_top_up, :boolean,
    default: false,
    doc:
      "Bounded sidebar only. When true, the JS hook is allowed to fire `bounded_top_up` once if the rail's rendered height is shorter than the viewport — a same-user-compaction backstop."

  def activity_feed(assigns) do
    ~H"""
    <div
      id={if @bounded, do: "home-activity-bounded", else: nil}
      phx-hook={if @bounded, do: "HomeActivityTopUp", else: nil}
      data-can-top-up={if @bounded, do: to_string(@can_top_up), else: nil}
    >
      <%!-- before:h-6 mirrors top-6 — masks items above the toggle when the
      outer rail unpins (bottom of the aside reaches the sticky offset). --%>
      <div
        :if={@has_follows? and @bounded}
        class="before:bg-surface-base bg-surface-base sticky top-6 z-10 -mx-1 flex justify-end px-1 pb-1 before:absolute before:inset-x-0 before:bottom-full before:h-6"
      >
        <.segmented_control label="Activity scope" size={:sm}>
          <:segment
            selected={@active_type == :following}
            on_select="set_activity_type"
            value={%{type: "following"}}
          >
            Friends
          </:segment>
          <:segment
            selected={@active_type == :global}
            on_select="set_activity_type"
            value={%{type: "global"}}
          >
            Global
          </:segment>
        </.segmented_control>
      </div>

      <%= cond do %>
        <% @activity.entries == [] and @active_type == :following -> %>
          <div class="py-10 text-center">
            <p class="text-foreground-tertiary text-sm">No recent activity from your friends.</p>
            <p class="text-foreground-tertiary mt-1 text-xs">
              Follow people to see their activity here.
            </p>
          </div>
        <% @activity.entries == [] -> %>
          <div class="py-10 text-center">
            <p class="text-foreground-tertiary text-sm">No recent activity.</p>
          </div>
        <% true -> %>
          <div>
            <.activity_entry
              :for={{entry, index} <- Enum.with_index(@activity.entries)}
              entry={entry}
              previous={if index > 0, do: Enum.at(@activity.entries, index - 1), else: nil}
            />

            <div :if={!@bounded && @activity.has_next} class="flex justify-center py-4">
              <.load_more phx-click="load_more_activity" size={:sm} />
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Per-entry dispatch — picks between grouped summary or single compact
  # row. Inserts the "new group" border-top divider when actor changes.
  # Reviews and lists are excluded at the data layer (see
  # `Data.@activity_excluded_actions`) so they never reach this dispatch.
  # ---------------------------------------------------------------------------

  attr :entry, :map, required: true
  attr :previous, :map, default: nil

  defp activity_entry(assigns) do
    rep = List.first(assigns.entry.members || [])
    prev_rep = assigns.previous && List.first(assigns.previous.members || [])
    collapse = collapse_user?(rep, prev_rep)

    assigns =
      assigns
      |> assign(:rep, rep)
      |> assign(:collapse_user, collapse)
      |> assign(:is_new_group, not is_nil(prev_rep) and not collapse)

    ~H"""
    <div class={[@is_new_group && "border-border-divider mt-3 border-t pt-3"]}>
      <%= cond do %>
        <% @rep == nil -> %>
        <% @entry.group_size > 1 -> %>
          <.grouped_row entry={@entry} collapse_user={@collapse_user} />
        <% true -> %>
          <.compact_row item={@rep} collapse_user={@collapse_user} />
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Single compact row — avatar, actor, verb sentence, date, optional
  # rating stars and preview lines.
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true
  attr :collapse_user, :boolean, default: false

  defp compact_row(assigns) do
    item = assigns.item
    metadata = item.metadata || %{}
    actor = item.actor
    actor_username = (actor && actor.username) || ""

    verb =
      Helpers.activity_verb(
        item.action,
        metadata,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    target_href =
      Helpers.target_href(
        item.action,
        metadata,
        actor_username,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    is_rated = item.action == :rated

    is_commented =
      item.action == :commented and Helpers.present?(metadata["text_preview"])

    is_quote =
      item.action in [:added_quote, :liked_quote] and
        Helpers.present?(metadata["quote_text_preview"])

    is_revision_summary =
      item.action in [:edited_entity, :reverted_entity, :created_entity] and
        Helpers.present?(metadata["summary"])

    target_class = home_target_class(assigns.collapse_user)

    assigns =
      assigns
      |> assign(:metadata, metadata)
      |> assign(:actor, actor)
      |> assign(:actor_username, actor_username)
      |> assign(:verb, verb)
      |> assign(:target_href, target_href)
      |> assign(:is_rated, is_rated)
      |> assign(:is_commented, is_commented)
      |> assign(:is_quote, is_quote)
      |> assign(:is_revision_summary, is_revision_summary)
      |> assign(:target_class, target_class)

    ~H"""
    <div class={["px-1", @collapse_user && "ml-[38px] py-[3px]", !@collapse_user && "py-[7px]"]}>
      <div class={["flex items-center", !@collapse_user && "gap-2.5"]}>
        <.link :if={!@collapse_user and @actor} navigate={profile_path(@actor)} class="shrink-0">
          <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
            user={@actor}
            size="size-7"
            sizes="28px"
            fallback={:initials}
          />
        </.link>

        <div class="min-w-0 flex-1">
          <div class={["flex items-baseline gap-2", !@collapse_user && "justify-between"]}>
            <%!--
              Sentence is a block paragraph (via line-clamp's webkit-box
              display) so its inline children — actor link, verb_phrase
              text + links, optional rating stars — reflow at word
              boundaries instead of each link wrapping as an atomic flex
              item. Capped at 2 lines so a pathological VN title can't
              push the rail height past two rows.
            --%>
            <div class={[
              "text-foreground-tertiary line-clamp-2 min-w-0 leading-relaxed",
              @collapse_user && "text-xs",
              !@collapse_user && "text-[13px]"
            ]}>
              <.link
                :if={!@collapse_user and @actor}
                navigate={profile_path(@actor)}
                class="hover:text-text-link-hover text-foreground-secondary inline-block max-w-[130px] truncate align-bottom font-medium transition-colors"
              >
                {display_name(@actor)}
              </.link>
              <Verbs.verb_phrase
                item={@item}
                metadata={@metadata}
                verb={@verb}
                target_href={@target_href}
                feed_username={@actor_username}
                target_class={@target_class}
                star_icon_class="text-icons-star-muted"
              />
              <.display_ratings
                :if={@is_rated and is_number(@metadata["rating"]) and @metadata["rating"] > 0}
                rating={@metadata["rating"]}
                class="inline-flex align-baseline"
                star_class="size-3"
                icon_class="text-icons-star-muted"
                half_rating_class="text-icons-star-muted"
              />
            </div>
            <time
              :if={!@collapse_user}
              datetime={datetime_attr(@item.inserted_at)}
              title={datetime_title(@item.inserted_at)}
              class="shrink-0 text-xs whitespace-nowrap text-[#7a7a7a]"
            >
              {SharedTime.calendar_short(@item.inserted_at)}
            </time>
          </div>

          <p
            :if={@is_commented}
            class="text-foreground-tertiary mt-1 line-clamp-2 text-xs italic"
          >
            “{@metadata["text_preview"]}”
          </p>

          <p
            :if={@is_quote}
            class="text-foreground-tertiary mt-1 line-clamp-2 text-xs italic"
          >
            “{@metadata["quote_text_preview"]}”
          </p>

          <p
            :if={@is_revision_summary}
            class="text-foreground-tertiary mt-1 line-clamp-2 text-xs"
          >
            {@metadata["summary"]}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Grouped row — server-grouped run rendered as one summary sentence.
  # ---------------------------------------------------------------------------

  attr :entry, :map, required: true
  attr :collapse_user, :boolean, default: false

  defp grouped_row(assigns) do
    rep = List.first(assigns.entry.members)
    actor = rep && rep.actor
    actor_username = (actor && actor.username) || ""
    target_class = home_target_class(assigns.collapse_user)

    assigns =
      assigns
      |> assign(:rep, rep)
      |> assign(:actor, actor)
      |> assign(:actor_username, actor_username)
      |> assign(:target_class, target_class)

    ~H"""
    <div
      :if={@rep}
      class={["px-1", @collapse_user && "ml-[38px] py-[3px]", !@collapse_user && "py-[7px]"]}
    >
      <div class={["flex items-center", !@collapse_user && "gap-2.5"]}>
        <.link :if={!@collapse_user and @actor} navigate={profile_path(@actor)} class="shrink-0">
          <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
            user={@actor}
            size="size-7"
            sizes="28px"
            fallback={:initials}
          />
        </.link>

        <div class="min-w-0 flex-1">
          <div class={["flex items-baseline gap-2", !@collapse_user && "justify-between"]}>
            <%!--
              Same paragraph + line-clamp-2 pattern as `compact_row/1`:
              inline children reflow at word boundaries and the row
              caps at 2 lines. The grouped_sentence body emits inline
              text + links + target links with no outer wrapper, so it
              flows naturally inside this block.
            --%>
            <div class={[
              "text-foreground-tertiary line-clamp-2 min-w-0 leading-relaxed",
              @collapse_user && "text-xs",
              !@collapse_user && "text-[13px]"
            ]}>
              <.link
                :if={!@collapse_user and @actor}
                navigate={profile_path(@actor)}
                class="hover:text-text-link-hover text-foreground-secondary inline-block max-w-[130px] truncate align-bottom font-medium transition-colors"
              >
                {display_name(@actor)}
              </.link>
              <.grouped_sentence
                entry={@entry}
                representative={@rep}
                actor_username={@actor_username}
                target_class={@target_class}
              />
            </div>
            <time
              :if={!@collapse_user}
              datetime={datetime_attr(@rep.inserted_at)}
              title={datetime_title(@rep.inserted_at)}
              class="shrink-0 text-xs whitespace-nowrap text-[#7a7a7a]"
            >
              {SharedTime.calendar_short(@rep.inserted_at)}
            </time>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :representative, :map, required: true
  attr :actor_username, :string, required: true
  attr :target_class, :string, required: true

  defp grouped_sentence(assigns) do
    metas = Enum.map(assigns.entry.members, &(&1.metadata || %{}))
    first = List.first(metas) || %{}
    second = Enum.at(metas, 1)

    assigns =
      assigns
      |> assign(:first, first)
      |> assign(:second, second)
      |> assign(:count, assigns.entry.group_size)

    case assigns.representative.action do
      :liked_screenshot ->
        vn_href = if first["vn_slug"], do: "/vn/#{first["vn_slug"]}", else: "#"

        assigns =
          assigns
          |> assign(:vn_href, vn_href)
          |> assign(:vn_title, first["vn_title"] || "a visual novel")

        ~H"""
        <span class="text-foreground-tertiary shrink-0">liked {@count} screenshots from</span>
        <Verbs.target_link href={@vn_href} text={@vn_title} class={@target_class} />
        """

      :liked_cover ->
        vn_href = if first["vn_slug"], do: "/vn/#{first["vn_slug"]}", else: "#"

        assigns =
          assigns
          |> assign(:vn_href, vn_href)
          |> assign(:vn_title, first["vn_title"] || "a visual novel")

        ~H"""
        <span class="text-foreground-tertiary shrink-0">liked {@count} covers from</span>
        <Verbs.target_link href={@vn_href} text={@vn_title} class={@target_class} />
        """

      :status_changed ->
        verb = Helpers.status_verb(first)
        shelf = Helpers.status_shelf_slug(first["status"])

        library_href =
          if shelf,
            do: "/@#{assigns.actor_username}/library/#{shelf}",
            else: "/@#{assigns.actor_username}/library"

        assigns =
          assigns
          |> assign(:verb_text, verb.text)
          |> assign(:verb_suffix, Map.get(verb, :suffix))
          |> assign(:library_href, library_href)
          |> assign(:href0, slug_or_hash(first["vn_slug"]))
          |> assign(:title0, first["vn_title"] || "a visual novel")
          |> assign(:href1, second && slug_or_hash(second["vn_slug"]))
          |> assign(:title1, second && (second["vn_title"] || "a visual novel"))

        ~H"""
        <%= cond do %>
          <% @count == 2 and @second -> %>
            <span class="text-foreground-tertiary shrink-0">{@verb_text}</span>
            <Verbs.target_link href={@href0} text={@title0} class={@target_class} />
            <span class="text-foreground-tertiary shrink-0">and</span>
            <Verbs.target_link href={@href1} text={@title1} class={@target_class} />
            <span :if={@verb_suffix} class="text-foreground-tertiary shrink-0">{@verb_suffix}</span>
          <% true -> %>
            <span class="text-foreground-tertiary shrink-0">{@verb_text}</span>
            <Verbs.target_link href={@href0} text={@title0} class={@target_class} />
            <.link
              navigate={@library_href}
              class="hover:text-text-link-hover text-foreground-tertiary shrink-0 transition-colors"
            >
              and {@count - 1} more
            </.link>
            <span :if={@verb_suffix} class="text-foreground-tertiary shrink-0">{@verb_suffix}</span>
        <% end %>
        """

      :followed ->
        targets = Enum.map(assigns.entry.members, &follow_target/1)
        [t0 | _] = targets
        t1 = Enum.at(targets, 1)

        assigns =
          assigns
          |> assign(:t0, t0)
          |> assign(:t1, t1)

        ~H"""
        <%= cond do %>
          <% @count == 2 and @t1 -> %>
            <span class="text-foreground-tertiary shrink-0">followed</span>
            <Verbs.target_link href={@t0.href} text={@t0.label} class={@target_class} />
            <span class="text-foreground-tertiary shrink-0">and</span>
            <Verbs.target_link href={@t1.href} text={@t1.label} class={@target_class} />
          <% true -> %>
            <span class="text-foreground-tertiary shrink-0">followed</span>
            <Verbs.target_link href={@t0.href} text={@t0.label} class={@target_class} />
            <span class="text-foreground-tertiary shrink-0">and {@count - 1} others</span>
        <% end %>
        """

      _ ->
        # Unexpected groupable action — fall back to verb + target so we
        # never render an empty sentence.
        verb =
          Helpers.activity_verb(
            assigns.representative.action,
            first,
            assigns.representative.followed_user,
            assigns.representative.followed_producer,
            assigns.representative.entity_ref
          )

        target_href =
          Helpers.target_href(
            assigns.representative.action,
            first,
            assigns.actor_username,
            assigns.representative.followed_user,
            assigns.representative.followed_producer,
            assigns.representative.entity_ref
          )

        assigns =
          assigns
          |> assign(:verb_text, verb.text)
          |> assign(:verb_suffix, Map.get(verb, :suffix))
          |> assign(:verb_target, verb.target)
          |> assign(:target_href, target_href)

        ~H"""
        <span class="text-foreground-tertiary shrink-0">{@verb_text}</span>
        <Verbs.target_link href={@target_href} text={@verb_target} class={@target_class} />
        <span :if={@verb_suffix} class="text-foreground-tertiary shrink-0">{@verb_suffix}</span>
        """
    end
  end

  @doc """
  Renders a list as a feed-stream card: actor + action + list name with likes
  pill and timestamp in the header, followed by a stacked-covers preview.

  Shared between the home Feed tab (rendering `:list` feed items) and the
  mobile Activity tab (rendering `:created_list` activity rows) since both
  surfaces show the same domain card for the same `Data.normalize_list/2`
  shape. Keeping a single component prevents the shape contracts from
  drifting again.
  """
  attr :list, :map, required: true

  def list_activity_card(assigns) do
    ~H"""
    <article class="border-border-divider border-b">
      <div class="flex flex-col pt-6 pb-9 lg:px-3">
        <header class="mb-6 flex items-start gap-3">
          <p class="text-foreground-secondary text-style-body2Medium min-w-0 flex-1 leading-5">
            <.link
              :if={@list.user}
              navigate={profile_path(@list.user)}
              class="hover:text-text-link-hover"
            >
              {display_name(@list.user)}
            </.link>
            <span class="text-style-body2Regular font-normal">{@list.action_text}</span>
            <.link
              navigate={list_path(@list)}
              class="hover:text-text-link-hover text-foreground-primary"
            >
              {@list.name}
            </.link>
            <span
              :if={@list.likes_count > 0}
              class="ml-2 inline-flex items-center gap-[2px] align-middle whitespace-nowrap"
            >
              <Lucide.heart class="text-foreground-tertiary size-[14px] fill-current" aria-hidden />
              <span class="text-foreground-tertiary text-style-captionRegular">
                {short_count(@list.likes_count)}
              </span>
            </span>
          </p>

          <time
            datetime={datetime_attr(@list.activity_at)}
            title={datetime_title(@list.activity_at)}
            class="text-style-captionRegular shrink-0 whitespace-nowrap text-[#7a7a7a]"
          >
            {@list.activity_label}
          </time>
        </header>

        <.link navigate={list_path(@list)} class="block">
          <ListCards.stacked_covers
            items={@list.visual_novels}
            sizes="(max-width: 640px) 20vw, 100px"
            max_covers={11}
            responsive_max_covers={%{mobile: 5, desktop: 11}}
            cover_fallback_size={32}
            disable_cover_link
            container_class="flex -space-x-5 overflow-hidden rounded-none bg-transparent sm:-space-x-6 lg:-space-x-7"
            class="aspect-9/13! rounded-none"
            image_class="rounded-none"
            empty_slot_class="border border-border-divider"
          />
        </.link>
      </div>
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp follow_target(member) do
    metadata = member.metadata || %{}
    fp = member.followed_producer

    if (member.entity_type == "producer" or fp) || metadata["followed_producer_slug"] do
      slug = (fp && fp.slug) || metadata["followed_producer_slug"]
      name = (fp && fp.name) || metadata["followed_producer_name"] || "a producer"
      %{href: (slug && "/developer/#{slug}") || "#", label: name}
    else
      fu = member.followed_user
      username = (fu && fu.username) || metadata["followed_username"]

      label =
        (fu && (fu.display_name || fu.username)) ||
          metadata["followed_display_name"] ||
          metadata["followed_username"] ||
          "a user"

      %{href: (username && "/@#{username}") || "#", label: label}
    end
  end

  defp slug_or_hash(slug) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  defp slug_or_hash(_), do: "#"

  # Class for bold target links inside the home rail. Truncates long titles
  # and switches to the muted-secondary tone on collapsed (same-actor
  # follow-up) rows.
  # NOTE: do not add `truncate` here — it sets `white-space: nowrap` on
  # the title link, which would force the entire title onto a single
  # unbroken inline unit and defeat the sentence's `line-clamp-2`
  # paragraph reflow. Overflow at the row level is handled by the clamp
  # on the parent sentence block in `compact_row/1`.
  defp home_target_class(true),
    do:
      "font-medium text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"

  defp home_target_class(false),
    do:
      "font-medium text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"

  # Same-actor follow-up rule: both rows
  # must be compact (not a full review/list card) and share the same
  # actor id. Reviewed/created_list rows always start a new group.
  defp collapse_user?(nil, _), do: false
  defp collapse_user?(_item, nil), do: false

  defp collapse_user?(item, previous) do
    compact?(item) and compact?(previous) and
      not is_nil(item.actor) and not is_nil(previous.actor) and
      item.actor.id == previous.actor.id
  end

  defp compact?(%{action: action}), do: action not in [:reviewed, :created_list]

  defp profile_path(%{username: username}) when is_binary(username) and username != "",
    do: "/@#{username}"

  defp profile_path(_), do: "/"

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp datetime_attr(nil), do: nil
  defp datetime_attr(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp datetime_attr(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp datetime_title(value), do: SharedTime.format_datetime_tooltip(value)

  defp list_path(%{user: %{username: username}, slug: slug})
       when is_binary(username) and is_binary(slug),
       do: "/@#{username}/list/#{slug}"

  defp list_path(_), do: "/lists"

  defp short_count(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 1)}m"
  defp short_count(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 1)}k"
  defp short_count(value), do: to_string(value)
end

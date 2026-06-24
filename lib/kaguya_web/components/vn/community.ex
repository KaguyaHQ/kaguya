defmodule KaguyaWeb.VN.Community do
  @moduledoc """
  Social/community sections rendered below the header.

  Every section here is a flat list (no elevated cards):

  - `reviews_section/1` — paged community reviews with compact sort control.
  - `friend_reviews_section/1` — friends-only reviews reusing the same row.
  - `friend_activity_section/1` — avatar circles + status overlay badge.
  - `discussions_section/1` — flat divided list of recent posts.

  `review_item/1` is exported so friend_reviews and reviews share one row.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.AuthPromptComponents, only: [auth_button: 1]
  import KaguyaWeb.SharedComponents.Markdown, only: [markdown_inline: 1]
  import KaguyaWeb.UI.Menu

  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  import KaguyaWeb.VN.Icons, only: [activity_badge_icon: 1, display_ratings: 1]

  # ---------------------------------------------------------------------------
  # Reviews
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :reviews, :map, required: true
  attr :sort, :string, required: true
  attr :is_logged_in, :boolean, default: false
  attr :liked_review_ids, :list, default: []

  def reviews_section(assigns) do
    ~H"""
    <section id="reviews" class="scroll-mt-20 lg:rounded-[12px] lg:px-8 lg:py-6">
      <div class="mb-4 flex items-center justify-between gap-4 max-lg:px-4 max-lg:md:px-8">
        <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
          Reviews
          <span
            :if={@vn.reviews_count > 0}
            class="ml-0.5 text-sm font-normal text-[rgb(var(--foreground-primary))]/40 lg:hidden"
          >
            ({@vn.reviews_count})
          </span>
        </h2>
        <.sort_control :if={@vn.reviews_count > 3} slug={@vn.slug} sort={@sort} />
      </div>
      <div class="mt-3 mb-[30px] hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>

      <%= if @reviews.items == [] do %>
        <.empty_reviews is_logged_in={@is_logged_in} />
      <% else %>
        <div class="relative lg:space-y-5">
          <div
            :for={review <- @reviews.items}
            class="px-5 max-sm:border-b max-sm:border-b-[rgb(var(--border-divider))] max-sm:py-3 max-sm:first:pt-0 max-sm:last:border-b-0 max-sm:last:pb-0 md:px-0"
          >
            <.review_item
              review={stamp_liked(review, @liked_review_ids)}
              dom_id={"review-#{review.id}"}
              review_href={review_permalink(review.user, @vn.slug)}
            />
          </div>
        </div>
      <% end %>

      <.review_pagination
        :if={show_review_pagination?(@reviews)}
        slug={@vn.slug}
        sort={@sort}
        page={@reviews.pagination.page}
        total_pages={@reviews.pagination.total_pages}
      />
    </section>
    """
  end

  defp stamp_liked(review, ids) when is_list(ids) do
    %{review | liked_by_me: Enum.any?(ids, &(to_string(&1) == to_string(review.id)))}
  end

  defp stamp_liked(review, _), do: review

  attr :slug, :string, required: true
  attr :sort, :string, required: true

  defp sort_control(assigns) do
    ~H"""
    <.menu
      id={"vn-reviews-sort-#{@slug}"}
      align="end"
      class="flex h-full w-fit cursor-pointer items-center gap-1.5 rounded-none border-0 bg-transparent p-0 text-sm leading-none font-medium text-[rgb(var(--foreground-secondary))] transition hover:bg-transparent hover:text-[rgb(var(--foreground-primary))] max-sm:h-fit sm:gap-2"
    >
      <:trigger aria-label="Sort reviews">
        <span class="text-style-body2Regular max-sm:text-[15px] max-sm:leading-[18px]">
          {sort_label(@sort)}
        </span>
        <Lucide.chevron_down class="size-4 shrink-0" aria-hidden />
      </:trigger>
      <div class="w-auto min-w-fit overflow-hidden rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 text-[rgb(var(--foreground-primary))] shadow-lg">
        <.link
          data-menu-dismiss
          patch={review_patch(@slug, 1, "MOST_LIKED")}
          class={sort_option_class(@sort == "MOST_LIKED")}
          aria-current={if @sort == "MOST_LIKED", do: "true"}
        >
          Popular
        </.link>
        <.link
          data-menu-dismiss
          patch={review_patch(@slug, 1, "NEWEST")}
          class={sort_option_class(@sort == "NEWEST")}
          aria-current={if @sort == "NEWEST", do: "true"}
        >
          Newest
        </.link>
        <.link
          data-menu-dismiss
          patch={review_patch(@slug, 1, "OLDEST")}
          class={sort_option_class(@sort == "OLDEST")}
          aria-current={if @sort == "OLDEST", do: "true"}
        >
          Oldest
        </.link>
      </div>
    </.menu>
    """
  end

  attr :is_logged_in, :boolean, required: true

  defp empty_reviews(assigns) do
    ~H"""
    <div class="flex items-center justify-center px-5 py-10 text-center max-lg:mt-2 max-lg:mb-6 max-lg:h-full md:px-0 lg:rounded-[10px]">
      <span class="text-sm text-[rgb(var(--foreground-tertiary))]">No reviews yet.</span>
      <.auth_button
        event="open_review_dialog"
        is_logged_in={@is_logged_in}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to write a review"
        class="ml-1 inline text-sm font-medium text-[rgb(var(--foreground-secondary))] underline-offset-2 transition-colors hover:text-[rgb(var(--foreground-primary))] hover:underline"
      >
        Write one?
      </.auth_button>
    </div>
    """
  end

  defp show_review_pagination?(%{pagination: %{total_pages: total_pages}})
       when is_integer(total_pages),
       do: total_pages > 1

  defp show_review_pagination?(_reviews), do: false

  attr :slug, :string, required: true
  attr :sort, :string, required: true
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true

  defp review_pagination(assigns) do
    page = assigns.page || 1
    total_pages = assigns.total_pages || 1

    assigns =
      assigns
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:pages, pagination_pages(page, total_pages))

    ~H"""
    <div class="mt-5 flex flex-wrap items-center justify-center gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
      <span :if={@page == 1} class={pagination_disabled_class()}>Previous</span>
      <.link
        :if={@page > 1}
        patch={review_patch(@slug, @page - 1, @sort)}
        class={pagination_step_class()}
      >
        Previous
      </.link>

      <%= for page <- @pages do %>
        <span :if={page == :gap} class="px-1.5 text-[rgb(var(--foreground-quaternary))]">…</span>
        <span :if={page == @page} class={pagination_current_class()} aria-current="page">{page}</span>
        <.link
          :if={is_integer(page) and page != @page}
          patch={review_patch(@slug, page, @sort)}
          class={pagination_number_class()}
        >
          {page}
        </.link>
      <% end %>

      <span :if={@page == @total_pages} class={pagination_disabled_class()}>Next</span>
      <.link
        :if={@page < @total_pages}
        patch={review_patch(@slug, @page + 1, @sort)}
        class={pagination_step_class()}
      >
        Next
      </.link>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared review row (used by `reviews_section/1` and `friend_reviews_section/1`)
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :dom_id, :string, default: nil
  attr :review_href, :string, default: nil

  def review_item(assigns) do
    assigns =
      assigns
      |> assign(:display_name, display_name(assigns.review.user))
      |> assign(:user_href, user_href(assigns.review.user))
      |> assign(:dom_id, assigns.dom_id || "review-#{assigns.review.id}")
      |> assign(:review_date, review_date(assigns.review.inserted_at))

    ~H"""
    <article
      id={@dom_id}
      class="group relative -mx-2 -my-1.5 scroll-mt-24 rounded-lg px-2 py-1.5 transition-colors lg:hover:bg-white/2"
    >
      <%!--
        Stretched-link pattern: an absolutely-positioned overlay link
        makes the entire card a clickable target while interactive child
        elements (avatar, profile link, like button, comments link) are
        promoted above it with `relative z-10`.
      --%>
      <.link
        :if={@review_href}
        navigate={@review_href}
        aria-label={"Read review by #{@display_name}"}
        tabindex="-1"
        class="absolute inset-0 z-1 rounded-lg"
      >
        <span class="sr-only">Read review by {@display_name}</span>
      </.link>

      <div class="flex w-full gap-[11px]">
        <.review_avatar user={@review.user} href={@user_href} />

        <div class="w-full">
          <div class="relative z-10 flex w-fit max-w-full items-center gap-1 text-[rgb(var(--foreground-secondary))]">
            <.link
              :if={@user_href}
              navigate={@user_href}
              class="text-xs font-semibold text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))] max-lg:max-w-[120px] max-lg:truncate lg:text-sm"
            >
              {@display_name}
            </.link>
            <span
              :if={!@user_href}
              class="text-xs font-semibold text-[rgb(var(--foreground-secondary))] max-lg:max-w-[120px] max-lg:truncate lg:text-sm"
            >
              {@display_name}
            </span>
            <.dot />
            <%= if @review.rating do %>
              <.review_rating rating={@review.rating} />
              <.dot />
            <% end %>
            <.link
              :if={@review_href}
              navigate={@review_href}
              title={review_date_title(@review)}
              class="text-xs font-light text-[rgb(var(--foreground-primary))] transition hover:text-[rgb(var(--foreground-secondary))]"
            >
              {SharedTime.calendar_custom(@review.inserted_at)}
            </.link>
            <span
              :if={!@review_href}
              title={review_date_title(@review)}
              class="text-xs font-light text-[rgb(var(--foreground-primary))]"
            >
              {SharedTime.calendar_custom(@review.inserted_at)}
            </span>
            <span
              :if={Map.get(@review, :is_edited)}
              class="text-xs font-light text-[rgb(var(--foreground-primary))]"
            >
              (edited)
            </span>
            <span
              :if={Map.get(@review, :is_locked) == true}
              class="ml-0.5 inline-flex items-center text-amber-500"
              aria-label="Locked"
              title="Locked"
            >
              <Lucide.lock class="size-2.5" aria-hidden />
            </span>
          </div>

          <details
            :if={@review.is_spoiler && present?(@review.content)}
            id={"#{@dom_id}-spoiler"}
            phx-hook="SpoilerScope"
            data-spoiler-scope={"review:#{@review.id}"}
            class="group/spoiler pointer-events-none relative z-10 mt-3 text-sm text-[rgb(var(--foreground-primary))] md:text-base"
          >
            <summary class="pointer-events-auto relative z-10 inline cursor-pointer list-none text-sm/6 text-[rgb(var(--foreground-secondary))] italic md:text-base md:leading-[26px] [&::-webkit-details-marker]:hidden">
              <span class="group-open/spoiler:hidden">
                This review may contain spoilers.
                <span class="ml-1 cursor-pointer font-medium text-[rgb(var(--foreground-primary))] not-italic transition-colors hover:text-[rgb(var(--foreground-primary))]/80">
                  Show review
                </span>
              </span>
              <span class="hidden text-[11px] tracking-wide text-[rgb(var(--foreground-tertiary))] not-italic group-open/spoiler:block">
                Contains spoilers
              </span>
            </summary>
            <div class={review_content_class("mt-1")}>
              <.markdown_inline content={@review.content} />
            </div>
          </details>

          <div
            :if={!@review.is_spoiler && present?(@review.content)}
            class={review_content_class("mt-3")}
          >
            <.markdown_inline content={@review.content} />
          </div>

          <p
            :if={@review.is_spoiler && !present?(@review.content)}
            class={[
              "mt-3 text-[11px] tracking-wide text-[rgb(var(--foreground-tertiary))]"
            ]}
          >
            Contains spoilers
          </p>

          <%!--
            Action row: a like button with a
            hover-bg circle around the heart, and a comments shortcut that
            shows just the raw count (no noun) and deep-links to the
            review's #comments anchor.
          --%>
          <div class="relative z-10 mt-3 -ml-1.5 flex w-fit items-center gap-4 text-[rgb(var(--foreground-secondary))] lg:gap-6">
            <button
              type="button"
              id={"#{@dom_id}-like"}
              phx-hook="LikeButton"
              phx-click="toggle_review_like"
              phx-value-review-id={@review.id}
              data-like-count-number={@review.likes_count}
              aria-pressed={if @review.liked_by_me, do: "true", else: "false"}
              aria-label={if @review.liked_by_me, do: "Unlike", else: "Like"}
              class="group/like kaguya-like-button relative inline-flex cursor-pointer items-center rounded-full before:absolute before:-inset-2 before:content-['']"
            >
              <div class={[
                "flex items-center rounded-full",
                if(@review.likes_count > 0, do: "-space-x-0.5", else: "gap-0")
              ]}>
                <div
                  data-like-heart-wrap
                  class="kaguya-like-heart-wrap flex size-7 items-center justify-center rounded-full lg:group-hover/like:bg-white/4"
                >
                  <Lucide.heart
                    class={[
                      "kaguya-like-heart size-4 transition-colors duration-100",
                      @review.liked_by_me &&
                        "fill-[rgb(var(--like-heart))] text-[rgb(var(--like-heart))]",
                      !@review.liked_by_me &&
                        "text-[rgb(var(--foreground-secondary))] lg:group-hover/like:fill-[rgb(var(--like-heart))] lg:group-hover/like:text-[rgb(var(--like-heart))]"
                    ]}
                    aria-hidden
                  />
                </div>
                <span
                  data-like-count-display
                  class={[
                    "relative inline-block h-4 translate-y-[0.5px] text-xs/4 font-normal lg:translate-y-px",
                    @review.likes_count <= 0 && "hidden"
                  ]}
                >
                  <span data-like-count-spacer class="invisible" aria-hidden="true">
                    {format_count_short(@review.likes_count)}
                  </span>
                  <span
                    data-like-count
                    class={[
                      "absolute inset-0",
                      @review.liked_by_me && "text-[rgb(var(--like-heart))]",
                      !@review.liked_by_me &&
                        "text-foreground-secondary lg:group-hover/like:text-[rgb(var(--like-heart))]"
                    ]}
                  >
                    {format_count_short(@review.likes_count)}
                  </span>
                </span>
              </div>
            </button>

            <.link
              :if={@review.comments_count > 0 && @review_href}
              navigate={@review_href}
              class="flex items-center -space-x-0.5 text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
            >
              <div class="flex size-7 items-center justify-center rounded-full lg:hover:bg-white/4">
                <Lucide.message_circle_more class="size-4" aria-hidden />
              </div>
              <span class="translate-y-[0.5px] text-xs lg:translate-y-px">
                {@review.comments_count}
              </span>
            </.link>
            <span
              :if={@review.comments_count > 0 && !@review_href}
              class="flex items-center -space-x-0.5 text-xs"
            >
              <div class="flex size-7 items-center justify-center rounded-full">
                <Lucide.message_circle_more class="size-4" aria-hidden />
              </div>
              <span class="translate-y-[0.5px] lg:translate-y-px">{@review.comments_count}</span>
            </span>
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :user, :map, required: true
  attr :href, :string, default: nil

  defp review_avatar(assigns) do
    ~H"""
    <.link
      :if={@href}
      navigate={@href}
      class="relative z-10 size-[26px] shrink-0 rounded-full lg:size-[36px]"
    >
      <.review_avatar_image user={@user} />
    </.link>
    <div :if={!@href} class="size-[26px] shrink-0 rounded-full lg:size-[36px]">
      <.review_avatar_image user={@user} />
    </div>
    """
  end

  attr :user, :map, required: true

  defp review_avatar_image(assigns) do
    ~H"""
    <%= if @user.avatar_url do %>
      <img src={@user.avatar_url} alt="" class="size-full rounded-full object-cover" />
    <% else %>
      <div class="size-full rounded-full bg-[rgb(var(--surface-banner))]"></div>
    <% end %>
    """
  end

  attr :rating, :any, required: true

  defp review_rating(assigns) do
    ~H"""
    <.display_ratings
      rating={@rating}
      class="translate-y-0 lg:translate-y-[0.85px]"
      icon_class="size-[13px] fill-current text-[rgb(var(--icons-user-star))]"
      half_rating_class="text-xs leading-none text-[rgb(var(--icons-user-star))]"
    />
    """
  end

  defp dot(assigns) do
    ~H"""
    <span class="translate-y-[0.5px] text-[7px] text-[rgb(var(--foreground-primary))]/40 lg:translate-y-[1.5px]">
      •
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Friend Activity (avatar circles row with overlay badge)
  # ---------------------------------------------------------------------------

  attr :activity_items, :list, required: true
  attr :vn_slug, :string, default: nil

  def friend_activity_section(assigns) do
    read_count = Enum.count(assigns.activity_items, fn item -> item.reading_status == "READ" end)
    assigns = assign(assigns, :read_count, read_count)

    ~H"""
    <section
      :if={@activity_items != []}
      class="px-4 lg:px-8 lg:pt-5"
    >
      <div class="hidden h-px bg-[rgb(var(--border-divider))] lg:-mt-5 lg:mb-5 lg:block"></div>
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
          Activity from Friends
        </h2>
        <span :if={@read_count > 0} class="text-sm text-[rgb(var(--foreground-tertiary))]">
          {@read_count} Read
        </span>
      </div>
      <div class="mt-4 grid grid-cols-5 gap-2 sm:flex sm:flex-wrap sm:gap-3">
        <.friend_activity_avatar :for={item <- @activity_items} item={item} vn_slug={@vn_slug} />
      </div>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :vn_slug, :string, default: nil

  defp friend_activity_avatar(assigns) do
    assigns =
      assigns
      |> assign(:tooltip, activity_tooltip_text(assigns.item))
      |> assign(:href, activity_href(assigns.item, assigns.vn_slug))

    ~H"""
    <div id={"friend-activity-#{@item.user.id}"} class="group/activity relative w-full sm:w-auto">
      <.link navigate={@href} class="flex flex-col items-center">
        <div class="relative w-full sm:w-14 lg:w-10">
          <div class="relative aspect-square w-full">
            <%= if @item.user.avatar_url do %>
              <img
                src={@item.user.avatar_url}
                alt={@item.user.display_name || @item.user.username}
                class="size-full rounded-full object-cover"
              />
            <% else %>
              <div class="size-full rounded-full bg-[rgb(var(--surface-banner))]"></div>
            <% end %>
            <span class="absolute -top-px right-px flex size-[15px] items-center justify-center rounded-full border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-secondary))]">
              <.activity_badge_icon item={@item} />
            </span>
          </div>
          <div :if={@item.rating} class="mt-[5px] flex justify-center lg:mt-[3px]">
            <.display_ratings
              rating={@item.rating}
              class="w-fit! gap-[0.5px]!"
              icon_class="!size-[8px] lg:!size-[7px] !text-[rgb(var(--icons-star-muted))] lg:group-hover/activity:!text-[rgb(var(--icons-user-star))] transition-colors duration-150"
              half_rating_class="text-[8px] leading-none flex items-center h-[8px] lg:h-[7px] !text-[rgb(var(--icons-star-muted))] lg:group-hover/activity:!text-[rgb(var(--icons-user-star))] transition-colors duration-150"
            />
          </div>
        </div>
      </.link>

      <%!-- Tooltip: hidden by default, shown on hover/focus-within with a 200ms --%>
      <%!-- show delay to match prod's Radix tooltip `delayDuration={200}`. Mirrors --%>
      <%!-- prod's text exactly (see FriendActivitySection#getTooltipText). --%>
      <span
        role="tooltip"
        class="pointer-events-none absolute bottom-full left-1/2 z-30 mb-1.5 -translate-x-1/2 rounded-[4px] bg-[rgb(var(--button-background-neutral-inverse-default))] px-2 py-1 text-[11px] font-medium whitespace-nowrap text-[rgb(var(--button-text-on-neutral-inverse))] opacity-0 transition-opacity duration-200 group-focus-within/activity:opacity-100 group-focus-within/activity:delay-200 group-hover/activity:opacity-100 group-hover/activity:delay-200"
      >
        {@tooltip}
      </span>
    </div>
    """
  end

  # Verb mapping for friend status-activity tooltips.
  defp activity_tooltip_text(item) do
    name = item.user.display_name || item.user.username || "a friend"

    cond do
      item.has_review ->
        "Reviewed by #{name}"

      item.rating ->
        "Rated by #{name}"

      true ->
        case item.reading_status do
          "READ" -> "Read by #{name}"
          "WANT_TO_READ" -> "Wishlisted by #{name}"
          "CURRENTLY_READING" -> "#{name} is reading"
          "ON_HOLD" -> "Paused by #{name}"
          "DID_NOT_FINISH" -> "Dropped by #{name}"
          "NOT_INTERESTED" -> "#{name} is not interested"
          _ -> "Tracked by #{name}"
        end
    end
  end

  defp activity_href(%{has_review: true, user: user}, vn_slug)
       when is_binary(vn_slug) and vn_slug != "" do
    review_permalink(user, vn_slug) || user_href(user) || "#"
  end

  defp activity_href(%{rating: rating, user: user}, _vn_slug) when not is_nil(rating) do
    case user_href(user) do
      nil -> "#"
      href -> "#{href}/library?rating=#{rating}"
    end
  end

  defp activity_href(%{reading_status: status, user: user}, _vn_slug) do
    case user_href(user) do
      nil -> "#"
      href -> "#{href}/library/#{reading_status_path(status)}"
    end
  end

  defp reading_status_path("CURRENTLY_READING"), do: "reading"
  defp reading_status_path("READ"), do: "read"
  defp reading_status_path("WANT_TO_READ"), do: "wishlist"
  defp reading_status_path("ON_HOLD"), do: "paused"
  defp reading_status_path("DID_NOT_FINISH"), do: "did-not-finish"
  defp reading_status_path("NOT_INTERESTED"), do: "not-interested"
  defp reading_status_path(status) when is_binary(status), do: String.downcase(status)
  defp reading_status_path(_status), do: "all"

  # ---------------------------------------------------------------------------
  # Friend Reviews
  # ---------------------------------------------------------------------------

  attr :vn_slug, :string, required: true
  attr :review_items, :list, required: true
  attr :liked_review_ids, :list, default: []
  attr :viewer_username, :string, default: nil

  def friend_reviews_section(assigns) do
    assigns =
      assign(
        assigns,
        :more_href,
        friend_reviews_more_href(assigns.viewer_username, assigns.vn_slug)
      )

    ~H"""
    <section :if={@review_items != []} class="lg:rounded-[12px] lg:px-8 lg:py-6">
      <div class="mb-4 flex items-center justify-between gap-4 max-lg:px-4 max-lg:md:px-5 lg:mb-0">
        <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
          Reviews from Friends
        </h2>
        <.link
          :if={@more_href}
          navigate={@more_href}
          class="text-sm text-[rgb(var(--foreground-tertiary))] transition hover:text-[rgb(var(--foreground-primary))]"
        >
          More
        </.link>
      </div>
      <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>
      <div class="lg:space-y-5">
        <div
          :for={review <- @review_items}
          class="px-5 max-sm:border-b max-sm:border-b-[rgb(var(--border-divider))] max-sm:py-3 max-sm:first:pt-0 max-sm:last:border-b-0 max-sm:last:pb-0 md:px-0"
        >
          <.review_item
            review={stamp_liked(review, @liked_review_ids)}
            dom_id={"friend-review-#{review.id}"}
            review_href={review_permalink(review.user, @vn_slug)}
          />
        </div>
      </div>
    </section>
    """
  end

  defp friend_reviews_more_href(viewer_username, vn_slug)
       when is_binary(viewer_username) and viewer_username != "" and is_binary(vn_slug) and
              vn_slug != "",
       do: "/@#{viewer_username}/friends/vn/#{vn_slug}/reviews"

  defp friend_reviews_more_href(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Discussions (flat divided list, only shown when the async load finishes
  # with a non-empty list — or while loading.)
  # ---------------------------------------------------------------------------

  attr :discussions, :any, required: true
  attr :vn_slug, :string, default: nil

  def discussions_section(assigns) do
    ~H"""
    <section :if={show_discussions?(@discussions)} class="px-4 lg:px-8 lg:py-6">
      <div class="flex items-center justify-between gap-4">
        <%= if present?(@vn_slug) do %>
          <.link
            navigate={"/vn/#{@vn_slug}/discussions"}
            class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))] transition lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            Discussions
          </.link>
          <.link
            navigate={"/vn/#{@vn_slug}/discussions"}
            class="text-xs font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase transition hover:text-[rgb(var(--text-link-hover))]"
          >
            More
          </.link>
        <% else %>
          <h2 class="text-[18px] leading-[22px] font-normal text-[rgb(var(--foreground-primary))]">
            Discussions
          </h2>
        <% end %>
      </div>
      <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>
      <%= case @discussions do %>
        <% {:ok, discussions} -> %>
          <div class="mt-4 flex flex-col divide-y divide-[rgb(var(--border-divider))] lg:mt-0">
            <.discussion_row :for={post <- discussions} post={post} vn_slug={@vn_slug} />
          </div>
        <% :loading -> %>
          <p class="text-sm text-[rgb(var(--foreground-tertiary))]">Loading discussions…</p>
        <% _ -> %>
      <% end %>
    </section>
    """
  end

  attr :post, :map, required: true
  attr :vn_slug, :string, default: nil

  defp discussion_row(assigns) do
    assigns =
      assigns
      |> assign(:href, discussion_href(assigns.post, assigns.vn_slug))
      |> assign(:user_href, user_href(assigns.post.user))
      |> assign(:display_name, display_name(assigns.post.user))
      |> assign(
        :show_counts?,
        (assigns.post.comments_count || 0) > 0 or (assigns.post.likes_count || 0) > 0
      )

    ~H"""
    <article
      id={"vn-discussion-#{@post.id}"}
      class="relative -mx-3 rounded-lg px-3 py-3.5 transition-colors first:pt-0 lg:py-4 lg:hover:bg-white/2"
    >
      <.link
        :if={@href != "#"}
        navigate={@href}
        class="absolute inset-0 z-1 rounded-lg"
        tabindex="-1"
        aria-hidden="true"
      >
        <span class="sr-only">Open discussion</span>
      </.link>

      <div class="flex gap-3">
        <div class="relative z-10 w-8 shrink-0 lg:w-9">
          <.link :if={@user_href} navigate={@user_href} class="block size-7 lg:size-8">
            <.review_avatar_image user={@post.user} />
          </.link>
          <div :if={!@user_href} class="size-7 lg:size-8">
            <.review_avatar_image user={@post.user} />
          </div>
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex items-start gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-1.5">
                <Lucide.pin
                  :if={@post.is_pinned}
                  class="mt-0.5 size-[11px] shrink-0 text-[rgb(var(--foreground-tertiary))]"
                  aria-label="Pinned"
                  role="img"
                />
                <h3 class="line-clamp-2 text-[14px] leading-snug font-medium text-[rgb(var(--foreground-primary))]">
                  {@post.title}
                </h3>
                <Lucide.lock
                  :if={@post.is_locked}
                  class="size-3 shrink-0 text-amber-500"
                  aria-label="Locked"
                  role="img"
                />
              </div>
            </div>
          </div>

          <div class="mt-1.5 flex items-center gap-2 text-xs text-[rgb(var(--foreground-tertiary))]">
            <div class="flex min-w-0 items-center gap-1 truncate">
              <.link
                :if={@user_href}
                navigate={@user_href}
                class="relative z-10 truncate font-medium text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))]"
              >
                {@display_name}
              </.link>
              <span
                :if={!@user_href}
                class="truncate font-medium text-[rgb(var(--foreground-secondary))]"
              >
                {@display_name}
              </span>
              <span class="text-[rgb(var(--foreground-quaternary))]">·</span>
              <span title={review_date(@post.inserted_at)}>
                {SharedTime.calendar_custom(@post.inserted_at)}
              </span>
            </div>
          </div>
        </div>

        <div class="flex min-w-[72px] shrink-0 flex-col items-end justify-center gap-2">
          <div
            :if={@show_counts?}
            class="flex items-center justify-end gap-2 text-xs leading-none text-[rgb(var(--foreground-tertiary))] tabular-nums"
          >
            <div :if={(@post.likes_count || 0) > 0} class="flex h-4 items-center gap-1 text-current">
              <Lucide.heart class="size-[11px] shrink-0 stroke-current" aria-hidden />
              <span class="inline-block min-w-[1ch] text-left text-current">
                {format_count_short(@post.likes_count)}
              </span>
            </div>

            <div
              :if={(@post.comments_count || 0) > 0}
              class="flex h-4 items-center gap-1 text-current"
            >
              <Lucide.message_square class="size-[11px] shrink-0 stroke-current" aria-hidden />
              <span class="inline-block min-w-[1ch] text-left text-current">
                {format_count_short(@post.comments_count)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp review_patch(slug, page, sort), do: ~p"/vn/#{slug}?page=#{page}&sort=#{sort}"

  defp sort_label("NEWEST"), do: "Newest"
  defp sort_label("OLDEST"), do: "Oldest"
  defp sort_label(_), do: "Popular"

  defp sort_option_class(true) do
    "block h-auto bg-[rgb(var(--surface-menu-item-hover))] px-3.5 py-3 text-sm leading-[17px] font-medium text-[rgb(var(--foreground-primary))]"
  end

  defp sort_option_class(false) do
    "block h-auto bg-[rgb(var(--surface-menu-item-default))] px-3.5 py-3 text-sm leading-[17px] font-medium text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
  end

  defp pagination_pages(_page, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..total_pages)

  defp pagination_pages(page, total_pages) do
    middle_start = max(page - 1, 2)
    middle_end = min(page + 1, total_pages - 1)
    middle = Enum.to_list(middle_start..middle_end)

    [1]
    |> maybe_add_gap(List.first(middle))
    |> Kernel.++(middle)
    |> maybe_add_gap(total_pages, List.last(middle))
    |> Kernel.++([total_pages])
  end

  defp maybe_add_gap(pages, next_page) when is_integer(next_page) and next_page > 2,
    do: pages ++ [:gap]

  defp maybe_add_gap(pages, _next_page), do: pages

  defp maybe_add_gap(pages, total_pages, previous_page)
       when is_integer(previous_page) and previous_page < total_pages - 1 do
    pages ++ [:gap]
  end

  defp maybe_add_gap(pages, _total_pages, _previous_page), do: pages

  defp pagination_step_class do
    "rounded-full border border-[rgb(var(--chip-border-default))] px-3 py-1.5 transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_number_class do
    "flex size-8 items-center justify-center rounded-full border border-[rgb(var(--chip-border-default))] text-xs transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_current_class do
    "flex size-8 items-center justify-center rounded-full border border-[rgb(var(--foreground-secondary))] bg-white/[4%] text-xs font-medium text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_disabled_class do
    "rounded-full border border-[rgb(var(--border-divider))] px-3 py-1.5 text-[rgb(var(--foreground-quaternary))]"
  end

  defp review_content_class(margin_class) do
    [
      margin_class,
      "line-clamp-4 text-sm leading-6 font-normal text-[rgb(var(--foreground-primary))] md:text-base md:leading-[26px]",
      "lg:!text-base lg:!font-normal lg:!leading-[24px] lg:[&_p]:!leading-[24px]",
      "[&_blockquote]:my-0 [&_li]:my-0 [&_ol]:my-0 [&_p]:my-1 [&_ul]:my-0"
    ]
  end

  defp display_name(%{display_name: name, username: username}) do
    if present?(name), do: name, else: username
  end

  defp display_name(%{username: username}), do: username
  defp display_name(_), do: "Unknown user"

  defp user_href(%{username: username}) when is_binary(username) and username != "",
    do: "/@#{username}"

  defp user_href(_), do: nil

  defp review_permalink(%{username: username}, vn_slug)
       when is_binary(username) and username != "" and is_binary(vn_slug) and vn_slug != "",
       do: "/@#{username}/reviews/#{vn_slug}"

  defp review_permalink(_, _), do: nil

  defp review_date(nil), do: nil
  defp review_date(value), do: to_string(value)

  defp review_date_title(%{inserted_at: inserted_at, source: source})
       when is_binary(source) and source != "" do
    [review_date(inserted_at), source]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp review_date_title(%{inserted_at: inserted_at}), do: review_date(inserted_at)
  defp review_date_title(_review), do: nil

  defp discussion_href(%{short_id: short_id}, vn_slug)
       when is_binary(short_id) and short_id != "" and is_binary(vn_slug) and vn_slug != "",
       do: "/vn/#{vn_slug}/discussions/#{short_id}"

  defp discussion_href(_post, _vn_slug), do: "#"

  defp format_count_short(value) when is_integer(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 1)}M"
  end

  defp format_count_short(value) when is_integer(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 1)}K"
  end

  defp format_count_short(value) when is_integer(value), do: Integer.to_string(value)
  defp format_count_short(_value), do: "0"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp show_discussions?(:loading), do: true
  defp show_discussions?({:ok, discussions}), do: discussions != []
  defp show_discussions?(_), do: false
end

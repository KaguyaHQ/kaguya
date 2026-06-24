defmodule KaguyaWeb.Components.Profile.Activity do
  @moduledoc """
  Function components and helpers for the `/@:username/activity` feed.

  Mirrors `../personal/legacy-next-app/src/components/profile/activity/ActivityItem.tsx`. Each
  activity row picks a layout based on the action verb:

    * `:reviewed` — full VN review card.
    * `:created_list` — full activity list card.
    * `:liked_screenshot` / `:liked_cover` — verb row + inline media thumb.
    * `:recommended_similar` — verb row + paired covers.
    * everything else — `CompactActivityItem` verb row.

  Sidebar mirrors `ActivitySidebar.tsx`: 25-avatar following grid, or the
  "members worth following" empty-state when the profile owner follows
  nobody (and we have discover users seeded).
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Shared, only: [avatar: 1]
  import KaguyaWeb.VN.Icons, only: [display_ratings: 1]

  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  import KaguyaWeb.Components.Activity.Helpers,
    only: [
      normalize_metadata: 1,
      iso_string: 1,
      vn_href: 1,
      slug_href: 1,
      present?: 1,
      activity_verb: 5,
      target_href: 6
    ]

  import KaguyaWeb.Components.Activity.Verbs, only: [target_link: 1, verb_phrase: 1]

  alias KaguyaWeb.Components.VN.Cards

  # ---------------------------------------------------------------------------
  # Top-level item dispatch
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true
  attr :username, :string, required: true
  attr :display_name, :string, required: true

  def activity_item(%{item: item} = assigns) do
    metadata = normalize_metadata(item.metadata)
    assigns = assign(assigns, :metadata, metadata)

    case item.action do
      :reviewed ->
        reviewed_item(assigns)

      :created_list ->
        created_list_item(assigns)

      :liked_screenshot ->
        screenshot_item(assigns)

      :liked_cover ->
        cover_item(assigns)

      :recommended_similar ->
        recommended_similar_item(assigns)

      _ ->
        compact_item(assigns)
    end
  end

  # ---------------------------------------------------------------------------
  # Full-card activity rows
  # ---------------------------------------------------------------------------

  defp reviewed_item(assigns) do
    if assigns.item.review do
      ~H"""
      <div class="px-4 lg:px-3">
        <Cards.vn_review_card
          review={@item.review}
          full_width
          align_left
          like_event="toggle_review_like"
        />
      </div>
      """
    else
      compact_item(assigns)
    end
  end

  defp created_list_item(assigns) do
    if assigns.item.list do
      assigns =
        assigns
        |> assign(:list, assigns.item.list)
        |> assign(:date_label, SharedTime.calendar_custom(assigns.item.inserted_at))
        |> assign(:date_title, iso_string(assigns.item.inserted_at))

      ~H"""
      <article class="border-b border-[rgb(var(--border-divider))] px-4 lg:px-3">
        <div class="flex flex-col pt-6 pb-9">
          <header class="mb-6 flex items-start gap-3">
            <div class="min-w-0 flex-1">
              <p class="text-style-body2Medium leading-5 text-[rgb(var(--foreground-secondary))]">
                <.link
                  navigate={"/@" <> ((@list.user && @list.user.username) || @username)}
                  class="transition-colors hover:text-[rgb(var(--text-link-hover))]"
                >
                  {(@list.user && (@list.user.display_name || @list.user.username)) || @display_name}
                </.link>
                <span class="text-style-body2Regular font-normal"> listed </span>
                <.link
                  navigate={list_href(@list)}
                  class="text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"
                >
                  {truncate_name(@list.name)}
                </.link>
                <span
                  :if={(@list.likes_count || 0) > 0}
                  class="ml-2 inline-flex items-center gap-[2px] align-middle whitespace-nowrap"
                >
                  <Lucide.heart
                    class="size-[14px] fill-current text-[rgb(var(--foreground-tertiary))]"
                    aria-hidden
                  />
                  <span class="text-style-captionRegular text-[rgb(var(--foreground-tertiary))]">
                    {@list.likes_count}
                  </span>
                </span>
              </p>
            </div>

            <span
              title={@date_title}
              class="text-style-captionRegular shrink-0 whitespace-nowrap text-[#7a7a7a]"
            >
              {@date_label}
            </span>
          </header>

          <.link navigate={list_href(@list)} class="block" aria-label={@list.name}>
            <span :for={cover <- @list.cover_urls || []} class="sr-only">
              {cover.title}
            </span>
            <Cards.stacked_covers
              items={@list.cover_urls || []}
              max_covers={11}
              container_class="flex w-full overflow-hidden -space-x-5 rounded-none bg-transparent sm:-space-x-6 lg:-space-x-7"
              item_class="aspect-[9/13] w-[22%] max-w-[72px] !flex-none sm:w-[12%]"
              image_class="aspect-[9/13] h-full w-full rounded-none object-cover"
              empty_slot_class="border border-[rgb(var(--border-divider))] bg-transparent"
            />
          </.link>
        </div>
      </article>
      """
    else
      compact_item(assigns)
    end
  end

  # ---------------------------------------------------------------------------
  # Screenshot row
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true
  attr :metadata, :map, required: true
  attr :username, :string, required: true
  attr :display_name, :string, required: true

  defp screenshot_item(assigns) do
    url = assigns.metadata["screenshot_url"]

    if is_nil(url) or url == "" do
      compact_item(assigns)
    else
      vn_href = vn_href(assigns.metadata)
      vn_title = assigns.metadata["vn_title"] || "a visual novel"

      assigns =
        assigns
        |> assign(:vn_href, vn_href)
        |> assign(:vn_title, vn_title)
        |> assign(:screenshot_url, url)

      ~H"""
      <div class="border-t border-[rgb(var(--border-divider))] px-4 py-3 lg:px-3">
        <div class="flex items-start justify-between gap-2">
          <p class="min-w-0 flex-1 text-sm text-[rgb(var(--foreground-secondary))]">
            <.actor_link username={@username} display_name={@display_name} /> liked a screenshot from
            <.target_link href={@vn_href} text={@vn_title} />
          </p>
          <.activity_date inserted_at={@item.inserted_at} />
        </div>

        <.link navigate={@vn_href} class="mt-2.5 block w-fit">
          <div class="relative aspect-video w-[160px] overflow-hidden rounded-[4px]">
            <img
              src={@screenshot_url}
              alt={"Screenshot from " <> @vn_title}
              class="absolute inset-0 size-full object-cover"
              loading="lazy"
              decoding="async"
            />
          </div>
        </.link>
      </div>
      """
    end
  end

  # ---------------------------------------------------------------------------
  # Cover row
  # ---------------------------------------------------------------------------

  defp cover_item(assigns) do
    url = assigns.metadata["cover_url"]

    if is_nil(url) or url == "" do
      compact_item(assigns)
    else
      vn_href = vn_href(assigns.metadata)
      vn_title = assigns.metadata["vn_title"] || "a visual novel"

      assigns =
        assigns
        |> assign(:vn_href, vn_href)
        |> assign(:vn_title, vn_title)
        |> assign(:cover_url, url)

      ~H"""
      <div class="border-t border-[rgb(var(--border-divider))] px-4 py-3 lg:px-3">
        <div class="flex items-start justify-between gap-2">
          <p class="min-w-0 flex-1 text-sm text-[rgb(var(--foreground-secondary))]">
            <.actor_link username={@username} display_name={@display_name} /> liked a cover from
            <.target_link href={@vn_href} text={@vn_title} />
          </p>
          <.activity_date inserted_at={@item.inserted_at} />
        </div>

        <.link navigate={@vn_href} class="mt-2.5 block w-fit">
          <div class="relative aspect-2/3 w-[56px] overflow-hidden rounded-[3px]">
            <img
              src={@cover_url}
              alt={"Cover from " <> @vn_title}
              class="absolute inset-0 size-full object-cover"
              loading="lazy"
              decoding="async"
            />
          </div>
        </.link>
      </div>
      """
    end
  end

  # ---------------------------------------------------------------------------
  # Recommended similar row
  # ---------------------------------------------------------------------------

  defp recommended_similar_item(assigns) do
    source_href = slug_href(assigns.metadata["source_vn_slug"])
    similar_href = slug_href(assigns.metadata["similar_vn_slug"])

    assigns =
      assigns
      |> assign(:source_href, source_href)
      |> assign(:similar_href, similar_href)
      |> assign(:source_title, assigns.metadata["source_vn_title"] || "a visual novel")
      |> assign(:similar_title, assigns.metadata["similar_vn_title"] || "a visual novel")
      |> assign(:source_image, assigns.metadata["source_vn_image_url"])
      |> assign(:similar_image, assigns.metadata["similar_vn_image_url"])

    ~H"""
    <div class="border-t border-[rgb(var(--border-divider))] px-4 py-3 lg:px-3">
      <div class="flex items-start justify-between gap-2">
        <p class="min-w-0 flex-1 text-sm text-[rgb(var(--foreground-secondary))]">
          <.actor_link username={@username} display_name={@display_name} /> recommended
          <.target_link href={@similar_href} text={@similar_title} /> on
          <.target_link href={@source_href} text={@source_title} />
        </p>
        <.activity_date inserted_at={@item.inserted_at} />
      </div>

      <div class="mt-2.5 flex items-center gap-2.5">
        <.link :if={@similar_image} navigate={@similar_href} class="block shrink-0">
          <div class="relative aspect-2/3 w-[44px] overflow-hidden rounded-[3px]">
            <img
              src={@similar_image}
              alt={@similar_title}
              class="absolute inset-0 size-full object-cover"
              loading="lazy"
              decoding="async"
            />
          </div>
        </.link>
        <span class="shrink-0 text-xs text-[rgb(var(--foreground-quaternary))]">→</span>
        <.link :if={@source_image} navigate={@source_href} class="block shrink-0">
          <div class="relative aspect-2/3 w-[44px] overflow-hidden rounded-[3px]">
            <img
              src={@source_image}
              alt={@source_title}
              class="absolute inset-0 size-full object-cover"
              loading="lazy"
              decoding="async"
            />
          </div>
        </.link>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Compact verb row — covers every remaining action
  # ---------------------------------------------------------------------------

  defp compact_item(assigns) do
    metadata = assigns.metadata
    item = assigns.item

    verb =
      activity_verb(
        item.action,
        metadata,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    target_href =
      target_href(
        item.action,
        metadata,
        assigns.username,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    is_rated = item.action == :rated
    is_liked_review = item.action == :liked_review
    is_commented = item.action == :commented

    assigns =
      assigns
      |> assign(:verb, verb)
      |> assign(:target_href, target_href)
      |> assign(:is_rated, is_rated)
      |> assign(:is_liked_review, is_liked_review)
      |> assign(:is_commented, is_commented)

    ~H"""
    <div class="border-t border-[rgb(var(--border-divider))] px-4 py-2.5 lg:px-3">
      <div class="flex items-start justify-between gap-2">
        <p class="min-w-0 flex-1 text-sm text-[rgb(var(--foreground-secondary))]">
          <.actor_link username={@username} display_name={@display_name} />
          <.verb_phrase
            item={@item}
            metadata={@metadata}
            verb={@verb}
            target_href={@target_href}
            feed_username={@username}
          />
          <.display_ratings
            :if={@is_rated and is_number(@metadata["rating"]) and @metadata["rating"] > 0}
            rating={@metadata["rating"]}
            class="ml-1 inline-flex align-[-2px]"
            star_class="size-3"
          />
        </p>

        <.activity_date inserted_at={@item.inserted_at} />
      </div>

      <p
        :if={@is_commented and present?(@metadata["text_preview"])}
        class="mt-1 ml-0.5 line-clamp-2 text-xs text-[rgb(var(--foreground-tertiary))] italic"
      >
        “{@metadata["text_preview"]}”
      </p>

      <p
        :if={
          @item.action in [:added_quote, :liked_quote] and present?(@metadata["quote_text_preview"])
        }
        class="mt-1 ml-0.5 line-clamp-2 text-xs text-[rgb(var(--foreground-tertiary))] italic"
      >
        “{@metadata["quote_text_preview"]}”
      </p>

      <p
        :if={
          @item.action in [:edited_entity, :reverted_entity, :created_entity] and
            present?(@metadata["summary"])
        }
        class="mt-1 ml-0.5 line-clamp-2 text-xs text-[rgb(var(--foreground-tertiary))]"
      >
        {@metadata["summary"]}
      </p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Atoms: links + date
  # ---------------------------------------------------------------------------

  attr :username, :string, required: true
  attr :display_name, :string, required: true

  defp actor_link(assigns) do
    ~H"""
    <.link
      navigate={"/@" <> @username}
      class="text-sm font-medium text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"
    >
      {@display_name}
    </.link>
    """
  end

  attr :inserted_at, :any, required: true

  defp activity_date(assigns) do
    label = SharedTime.calendar_custom(assigns.inserted_at)
    title = iso_string(assigns.inserted_at)
    assigns = assigns |> assign(:label, label) |> assign(:title, title)

    ~H"""
    <span
      title={@title}
      class="shrink-0 text-xs whitespace-nowrap text-[rgb(var(--foreground-tertiary))]"
    >
      {@label}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Sidebar (desktop right rail)
  # ---------------------------------------------------------------------------

  attr :username, :string, required: true
  attr :following_users, :list, default: []
  attr :following_count, :integer, default: 0
  attr :discover_users, :list, default: []

  def sidebar(assigns) do
    has_following = assigns.following_users != []
    has_discover = assigns.discover_users != []

    assigns =
      assigns
      |> assign(:has_following, has_following)
      |> assign(:has_discover, has_discover)

    ~H"""
    <%= cond do %>
      <% @has_following -> %>
        <div>
          <div class="mb-4 flex items-center justify-between border-b border-[rgb(var(--border-divider))] pb-3">
            <.link
              navigate={"/@" <> @username <> "/following"}
              class="text-style-body2Medium tracking-wide text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
            >
              Following
            </.link>
            <.link
              navigate={"/@" <> @username <> "/following"}
              class="text-style-body2Medium text-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--text-link-hover))]"
            >
              {@following_count}
            </.link>
          </div>
          <div class="grid grid-cols-5 gap-1.5">
            <.link
              :for={user <- @following_users}
              navigate={"/@" <> (user.username || "")}
              class="size-10"
              title={user.display_name || user.username}
            >
              <.avatar user={user} class="size-10 rounded-full object-cover" sizes="40px" />
            </.link>
          </div>
        </div>
      <% @has_discover -> %>
        <div>
          <div class="mb-4 flex items-center justify-between border-b border-[rgb(var(--border-divider))] pb-3">
            <.link
              navigate="/members"
              class="text-style-body2Medium tracking-wide text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
            >
              Members worth following
            </.link>
          </div>
          <div class="grid grid-cols-5 gap-1.5">
            <.link
              :for={user <- @discover_users}
              navigate={"/@" <> (user.username || "")}
              class="size-10"
              title={user.display_name || user.username}
            >
              <.avatar user={user} class="size-10 rounded-full object-cover" sizes="40px" />
            </.link>
          </div>
        </div>
      <% true -> %>
        <span></span>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Empty / end-of-feed sentinels
  # ---------------------------------------------------------------------------

  def empty_feed(assigns) do
    ~H"""
    <p class="py-10 text-center text-sm text-[rgb(var(--foreground-tertiary))]">
      No recent activity
    </p>
    """
  end

  def end_of_feed(assigns) do
    ~H"""
    <p class="py-6 text-center text-xs text-[rgb(var(--foreground-quaternary))]">
      End of recent activity
    </p>
    """
  end

  # ---------------------------------------------------------------------------
  # File-local helpers
  # ---------------------------------------------------------------------------

  # Struct-arg list href used by the reviewed/created_list template
  # branches above. The string-arg variant lives in `Helpers.list_href/2`.
  defp list_href(%{user: %{username: username}, slug: slug})
       when is_binary(username) and username != "" and is_binary(slug) and slug != "" do
    "/@#{username}/list/#{slug}"
  end

  defp list_href(%{username: username, slug: slug})
       when is_binary(username) and username != "" and is_binary(slug) and slug != "" do
    "/@#{username}/list/#{slug}"
  end

  defp list_href(_), do: "#"

  defp truncate_name(name) when is_binary(name) do
    if String.length(name) > 100, do: String.slice(name, 0, 100) <> "...", else: name
  end

  defp truncate_name(_), do: "a list"
end

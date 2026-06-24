defmodule KaguyaWeb.Components.VN.Cards do
  @moduledoc """
  Shared VN/character/list/review render primitives reused across profile
  tabs (overview, reviews, lists, library) and the VN page.

  Provides:

    * `cover/1`
    * `character_image/1`
    * `stacked_covers/1`
    * `vn_review_card/1`

  These are function components: pure inputs in, HEEx out. No LiveView state.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.Markdown, only: [markdown_inline: 1]

  alias KaguyaWeb.SharedComponents.Cover, as: SharedCover
  alias KaguyaWeb.SharedComponents.LikeButton
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  # ---------------------------------------------------------------------------
  # VN cover (2:3 aspect)
  # ---------------------------------------------------------------------------

  @doc """
  Renders a VN cover image. Falls back to a neutral square when the VN has
  no primary image. Accepts a normalized VN map with `:images`, `:title`,
  `:slug`, `:id`.

  Delegates to `KaguyaWeb.SharedComponents.Cover.cover/1` so every caller gets
  the same srcset breakpoints, NSFW blur contract, and tooltip plumbing as
  the home-page / single-review covers. Local `class` / `fallback_class`
  defaults preserve the historical card look (rounded-[4px], 2:3 aspect).
  """
  attr :vn, :map, required: true
  attr :sizes, :string, default: "(max-width: 1024px) 25vw, 256px"
  attr :class, :string, default: "aspect-[1/1.5] w-full rounded-[4px] object-cover object-center"
  attr :fallback_class, :string, default: "rounded-[4px]"
  attr :link, :boolean, default: false
  attr :show_title_tooltip, :boolean, default: false

  def cover(assigns) do
    ~H"""
    <SharedCover.cover
      vn={@vn}
      sizes={@sizes}
      class={@class}
      fallback_class={@fallback_class}
      link={@link}
      show_title_tooltip={@show_title_tooltip}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Character image (1:1 aspect)
  # ---------------------------------------------------------------------------

  @doc """
  Shim that delegates to `KaguyaWeb.SharedComponents.CharacterImage`.
  Kept for back-compat with existing callsites — new code should call the
  shared component directly. See § 6 in
  `docs/migrations/nextjs-liveview/plans/component-parity-plan.md`.
  """
  attr :character, :map, required: true
  attr :sizes, :string, default: nil
  attr :class, :string, default: "aspect-square w-full object-cover"
  attr :rounded, :string, default: "rounded-[4px]"
  attr :show_name_tooltip, :boolean, default: false

  def character_image(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.CharacterImage.character_image
      character={@character}
      sizes={@sizes}
      class={@class}
      rounded={@rounded}
      show_name_tooltip={@show_name_tooltip}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Stacked covers (overlapping VN covers used in sidebar wishlist + list cards)
  # ---------------------------------------------------------------------------

  @doc """
  Stacked overlapping covers — shim that delegates to
  `KaguyaWeb.SharedComponents.StackedCovers`. Kept for back-compat with
  the existing call sites that pass the VN.Cards-shaped defaults
  (fixed 71×106 px sized items, `link` flag).

  New code should call `<.stacked_covers>` from the shared module
  directly. See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 12.
  """
  attr :items, :list, required: true
  attr :max_covers, :integer, default: 5
  attr :responsive_max_covers, :map, default: nil

  attr :container_class, :any,
    default:
      "flex w-fit items-stretch overflow-hidden -space-x-4 rounded-[3px] bg-[rgb(var(--surface-base))] p-0"

  attr :item_class, :any,
    default: "!flex-none h-[106px] w-[71px]",
    doc:
      "Forces fixed 71×106 px size to preserve the legacy VN.Cards look; pass a different class to override."

  attr :image_class, :any, default: "h-[106px] w-[71px]"
  attr :empty_slot_class, :any, default: "bg-[rgb(var(--surface-base))]"
  attr :sizes, :string, default: "71px"
  attr :link, :boolean, default: false

  def stacked_covers(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.StackedCovers.stacked_covers
      items={@items}
      sizes={@sizes}
      max_covers={@max_covers}
      responsive_max_covers={@responsive_max_covers}
      container_class={@container_class}
      item_class={@item_class}
      image_class={@image_class}
      empty_slot_class={@empty_slot_class}
      disable_cover_link={not @link}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # VN Review card
  # ---------------------------------------------------------------------------

  attr :review, :map,
    required: true,
    doc:
      "Normalized review map (see Kaguya.Profiles.Overview.profile_overview/2's decorate_review/1 output)."

  attr :full_width, :boolean, default: true
  attr :align_left, :boolean, default: true
  attr :hide_user, :boolean, default: false
  attr :muted_stars, :boolean, default: false
  attr :like_event, :string, default: nil
  attr :class, :any, default: nil
  attr :id_prefix, :string, default: "vn-review-card"

  def vn_review_card(assigns) do
    review = assigns.review
    vn = Map.get(review, :visual_novel)
    user = Map.get(review, :user)
    vn_href = vn && vn.slug && "/vn/#{vn.slug}"
    review_href = review_url(user, vn)

    assigns =
      assigns
      |> assign(:vn, vn)
      |> assign(:user, user)
      |> assign(:vn_href, vn_href)
      |> assign(:review_href, review_href)

    ~H"""
    <article class={["border-b border-[rgb(var(--border-divider))] last:border-b-0", @class]}>
      <div class={[
        "relative flex gap-[17px] rounded-lg py-5 transition-colors lg:py-7 lg:hover:bg-white/2",
        not @align_left && "mx-auto lg:px-3",
        not @full_width && "max-w-[548px]"
      ]}>
        <%= if @review_href do %>
          <.link
            navigate={@review_href}
            class="absolute inset-0 z-1 rounded-lg"
            tabindex="-1"
            aria-hidden="true"
          >
            <span class="sr-only">Open review</span>
          </.link>
        <% end %>

        <%= if @vn_href do %>
          <.link navigate={@vn_href} class="relative z-10 shrink-0">
            <div class="aspect-9/13 w-[100px] overflow-hidden rounded-[4px]">
              <.cover
                :if={@vn}
                vn={@vn}
                sizes="100px"
                class="size-full rounded-[4px] object-cover"
              />
            </div>
          </.link>
        <% else %>
          <div class="aspect-9/13 w-[100px] shrink-0 overflow-hidden rounded-[4px] bg-[rgb(var(--surface-elevated))]" />
        <% end %>

        <div class="flex min-w-0 flex-1 flex-col">
          <header class="flex flex-col">
            <div :if={!@hide_user} class="flex items-baseline justify-between gap-3">
              <p class="min-w-0 truncate text-sm text-[rgb(var(--foreground-secondary))]">
                <%= if @user do %>
                  <.link
                    navigate={"/@#{@user.username}"}
                    class="relative z-10 hover:text-[rgb(var(--text-link-hover))]"
                  >
                    {@user.display_name}
                  </.link>
                <% end %>
                <span class="font-normal"> reviewed</span>
              </p>
              <span
                title={SharedTime.format_datetime_tooltip(@review.inserted_at)}
                class="relative z-10 shrink-0 text-xs whitespace-nowrap text-[rgb(var(--foreground-tertiary))]"
              >
                {SharedTime.calendar_custom(@review.inserted_at)}
              </span>
            </div>

            <div :if={@hide_user} class="flex items-start justify-between gap-3">
              <%= if @vn_href do %>
                <.link navigate={@vn_href} class="relative z-10 min-w-0">
                  <h3
                    class="text-style-proseMedium line-clamp-2 text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"
                    style="font-family: var(--font-source-serif)"
                  >
                    {@vn && @vn.title}
                  </h3>
                </.link>
              <% else %>
                <h3
                  class="text-style-proseMedium line-clamp-2 text-[rgb(var(--foreground-primary))]"
                  style="font-family: var(--font-source-serif)"
                >
                  {@vn && @vn.title}
                </h3>
              <% end %>
              <span
                title={SharedTime.format_datetime_tooltip(@review.inserted_at)}
                class="text-style-captionRegular relative z-10 shrink-0 pt-0.5 whitespace-nowrap text-[#7a7a7a]"
              >
                {SharedTime.calendar_custom(@review.inserted_at)}
              </span>
            </div>

            <%= if !@hide_user do %>
              <%= if @vn_href do %>
                <.link navigate={@vn_href} class="relative z-10 mt-1 w-fit">
                  <h3
                    class="text-style-proseMedium line-clamp-2 text-[rgb(var(--foreground-primary))] transition-colors hover:text-[rgb(var(--text-link-hover))]"
                    style="font-family: var(--font-source-serif)"
                  >
                    {@vn && @vn.title}
                  </h3>
                </.link>
              <% else %>
                <h3
                  class="text-style-proseMedium mt-1 line-clamp-2 text-[rgb(var(--foreground-primary))]"
                  style="font-family: var(--font-source-serif)"
                >
                  {@vn && @vn.title}
                </h3>
              <% end %>
            <% end %>

            <div :if={@review.rating} class="mt-1">
              <KaguyaWeb.VN.Icons.display_ratings
                rating={@review.rating}
                class="gap-[2px]"
                star_class={[
                  "size-3 leading-none",
                  @muted_stars && "text-[rgb(var(--icons-star-muted))]",
                  !@muted_stars && "text-[rgb(var(--icons-user-star))]"
                ]}
                half_rating_class={[
                  "text-xs",
                  @muted_stars && "text-[rgb(var(--icons-star-muted))]",
                  !@muted_stars && "text-[rgb(var(--icons-user-star))]"
                ]}
              />
            </div>
          </header>

          <%= cond do %>
            <% @review.is_spoiler and present?(@review.content) -> %>
              <details
                id={"#{@id_prefix}-#{@review.id}-spoiler"}
                phx-hook="SpoilerScope"
                data-spoiler-scope={"review:#{@review.id}"}
                class="group/spoiler relative z-10 mt-3"
              >
                <summary class="cursor-pointer list-none text-sm/6 text-[rgb(var(--foreground-secondary))] italic group-open/spoiler:hidden marker:hidden [&::-webkit-details-marker]:hidden">
                  This review may contain spoilers.
                  <span class="ml-1 font-medium text-[rgb(var(--foreground-primary))] not-italic transition-colors">
                    Show review
                  </span>
                </summary>
                <p class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  Contains spoilers
                </p>
                <div class="mt-1 line-clamp-5 text-sm/6 text-[rgb(var(--foreground-secondary))] md:text-base md:leading-[26px] [&_p]:my-1 first:[&_p]:mt-0 last:[&_p]:mb-0">
                  <.markdown_inline content={@review.content} />
                </div>
              </details>
            <% @review.is_spoiler -> %>
              <p class="mt-3 text-xs text-[rgb(var(--foreground-tertiary))]">
                Contains spoilers
              </p>
            <% present?(@review.content) -> %>
              <div class="mt-3 line-clamp-5 text-sm/6 text-[rgb(var(--foreground-secondary))] md:text-base md:leading-[26px] [&_p]:my-1 first:[&_p]:mt-0 last:[&_p]:mb-0">
                <.markdown_inline content={@review.content} />
              </div>
            <% true -> %>
          <% end %>

          <div class="relative z-10 mt-3 -ml-1.5 flex items-center gap-1">
            <%= if @like_event do %>
              <LikeButton.like_button
                id={"#{@id_prefix}-#{@review.id}-like"}
                click={@like_event}
                value_review_id={@review.id}
                liked={@review.liked_by_me}
                likes_count={@review.likes_count || 0}
                size={:sm}
              />
            <% else %>
              <span class="inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs text-[rgb(var(--foreground-secondary))]">
                <Lucide.heart class="size-4" aria-hidden />
                <span :if={(@review.likes_count || 0) > 0}>{@review.likes_count}</span>
              </span>
            <% end %>
            <.link
              :if={(@review.comments_count || 0) > 0 and @review_href}
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
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp review_url(%{username: u}, %{slug: s})
       when is_binary(u) and is_binary(s) and u != "" and s != "",
       do: "/@#{u}/reviews/#{s}"

  defp review_url(_, _), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end

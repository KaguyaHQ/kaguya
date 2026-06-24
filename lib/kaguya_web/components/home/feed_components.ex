defmodule KaguyaWeb.Home.FeedComponents do
  @moduledoc """
  Components for the signed-in home feed.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.SharedComponents.SegmentedControl

  alias KaguyaWeb.Components.VN.Cards, as: VNCards
  alias KaguyaWeb.Home.ActivityComponents
  alias KaguyaWeb.SharedComponents.LikeButton

  attr :display_name, :string, default: ""
  attr :feed, :map, required: true
  attr :activity, :map, required: true
  attr :activity_type, :atom, default: :global
  attr :has_follows?, :boolean, default: false
  attr :mobile_tab, :atom, default: :feed
  attr :activity_can_top_up, :boolean, default: false

  def home(assigns) do
    ~H"""
    <div class="mx-auto min-h-[calc(100vh-172px)] max-w-[1168px] px-4 pt-8 pb-24 md:px-8 lg:pt-[49px]">
      <header
        id="home-greeting"
        class="mb-5 text-center lg:mb-8"
        phx-hook="HomeGreeting"
        phx-update="ignore"
        data-display-name={@display_name}
      >
        <%!-- Greeting text is filled client-side from local time (see
        home_greeting.js, applied on app.js load — not gated on the socket).
        phx-update="ignore" keeps that text through LiveView's connect patch;
        &nbsp; reserves the line height to prevent layout shift before fill. --%>
        <h1
          class="text-foreground-primary text-2xl font-light tracking-tight"
          data-home-greeting-text
        >
          &nbsp;
        </h1>
      </header>

      <div class="mb-4 flex justify-center lg:hidden">
        <.segmented_control label="Home sections" size={:md}>
          <:segment
            selected={@mobile_tab == :feed}
            on_select="set_mobile_home_tab"
            value={%{tab: "feed"}}
          >
            Feed
          </:segment>
          <:segment
            selected={@mobile_tab == :activity}
            on_select="set_mobile_home_tab"
            value={%{tab: "activity"}}
          >
            Activity
          </:segment>
        </.segmented_control>
      </div>

      <div class="flex justify-center lg:gap-10">
        <main class={["w-full max-w-[548px] shrink-0", @mobile_tab != :feed && "hidden lg:block"]}>
          <.feed_list feed={@feed} />
        </main>

        <div class={["w-full max-w-[548px] pt-5 lg:hidden", @mobile_tab != :activity && "hidden"]}>
          <ActivityComponents.activity_feed
            activity={@activity}
            active_type={@activity_type}
            has_follows?={@has_follows?}
            mobile
          />
        </div>

        <div class="border-border-divider hidden border-l lg:block"></div>
        <aside class="hidden w-[380px] shrink-0 lg:block">
          <div class="sticky top-6">
            <ActivityComponents.activity_feed
              activity={@activity}
              active_type={@activity_type}
              has_follows?={@has_follows?}
              bounded
              can_top_up={@activity_can_top_up}
            />
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :feed, :map, required: true

  def feed_list(assigns) do
    ~H"""
    <div>
      <%= if @feed.items == [] do %>
        <div class="py-16 text-center">
          <p class="text-foreground-secondary mb-2 text-lg">No recent activity</p>
          <p class="text-foreground-tertiary text-sm">
            Be the first to write a review, start a discussion, or create a list.
          </p>
        </div>
      <% else %>
        <div>
          <.feed_item :for={item <- @feed.items} item={item} />
        </div>

        <div :if={@feed.has_next} class="flex w-full items-center justify-center py-6">
          <.load_more phx-click="load_more_feed" />
        </div>
      <% end %>
    </div>
    """
  end

  attr :item, :any, required: true

  defp feed_item(%{item: {:review, review}} = assigns) do
    assigns = assign(assigns, :review, review)

    ~H"""
    <.review_card review={@review} />
    """
  end

  defp feed_item(%{item: {:list, list}} = assigns) do
    assigns = assign(assigns, :list, list)

    ~H"""
    <ActivityComponents.list_activity_card list={@list} />
    """
  end

  defp feed_item(%{item: {:post, post}} = assigns) do
    assigns = assign(assigns, :post, post)

    ~H"""
    <.post_card post={@post} />
    """
  end

  attr :review, :map, required: true

  defp review_card(assigns) do
    ~H"""
    <VNCards.vn_review_card
      review={@review}
      full_width
      align_left
      like_event="toggle_feed_review_like"
    />
    """
  end

  attr :post, :map, required: true

  defp post_card(assigns) do
    ~H"""
    <article class="border-border-divider border-b last:border-b-0">
      <div class="relative flex gap-[17px] rounded-lg py-5 transition-colors lg:px-3 lg:py-7 lg:hover:bg-white/2">
        <.link
          navigate={@post.url}
          class="absolute inset-0 z-1 rounded-lg"
          tabindex="-1"
          aria-hidden="true"
        >
        </.link>

        <.link :if={post_cover?(@post)} navigate={@post.entity.href} class="relative z-10 shrink-0">
          <.cover vn={@post.entity.visual_novel} class="w-[100px] rounded-[4px]" />
        </.link>

        <div class="flex min-w-0 flex-1 flex-col">
          <header class="flex flex-col">
            <div class="flex items-baseline justify-between gap-3">
              <p class="text-foreground-secondary text-style-body2Medium min-w-0 truncate">
                <.link
                  :if={@post.user}
                  navigate={profile_path(@post.user)}
                  class="hover:text-text-link-hover relative z-10"
                >
                  {display_name(@post.user)}
                </.link>
                <span class="font-normal">{post_verb(@post)}</span>
                <.link
                  :if={@post.entity}
                  navigate={@post.entity.href}
                  class="hover:text-text-link-hover relative z-10"
                >
                  {@post.entity.label}
                </.link>
              </p>
              <time
                datetime={datetime_attr(@post.activity_at)}
                title={datetime_title(@post.activity_at)}
                class="text-style-captionRegular relative z-10 shrink-0 whitespace-nowrap text-[#7a7a7a]"
              >
                {@post.activity_label}
              </time>
            </div>

            <div class="mt-1 flex min-w-0 items-start gap-1.5">
              <Lucide.pin
                :if={@post.is_pinned}
                class="text-foreground-tertiary mt-2 size-[13px] shrink-0"
                aria-hidden
              />
              <Lucide.lock
                :if={@post.is_locked}
                class="text-foreground-tertiary mt-2 size-[13px] shrink-0"
                aria-hidden
              />
              <.link navigate={@post.url} class="relative z-10 min-w-0">
                <h2 class="hover:text-text-link-hover text-foreground-primary line-clamp-2 text-[17px] leading-snug font-semibold transition-colors md:text-[18px]">
                  {@post.title}
                </h2>
              </.link>
            </div>
          </header>

          <p
            :if={@post.content_preview}
            class="text-foreground-secondary mt-0.5 line-clamp-5 text-sm/6 md:text-base md:leading-[26px]"
          >
            {@post.content_preview}
          </p>

          <div class="relative z-10 mt-3 -ml-1.5 flex items-center gap-1">
            <LikeButton.like_button
              id={"feed-post-#{@post.id}-like"}
              click="toggle_feed_post_like"
              value_id={@post.id}
              liked={@post.liked_by_me}
              likes_count={@post.likes_count || 0}
              size={:sm}
            />

            <.link
              :if={@post.comments_count > 0}
              navigate={@post.url}
              class="hover:text-foreground-primary text-foreground-secondary flex items-center -space-x-0.5 transition-colors"
            >
              <span class="flex size-7 items-center justify-center rounded-full lg:hover:bg-white/4">
                <Lucide.message_circle_more class="size-4" aria-hidden />
              </span>
              <span class="translate-y-[0.5px] text-xs lg:translate-y-px">
                {@post.comments_count}
              </span>
            </.link>
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :vn, :map, required: true
  attr :class, :any, default: nil

  defp cover(assigns) do
    assigns = assign(assigns, :nsfw_blur?, cover_needs_blur?(assigns.vn))

    ~H"""
    <%= if image_url(@vn) do %>
      <img
        src={image_url(@vn)}
        srcset={image_srcset(@vn)}
        sizes="100px"
        alt={@vn.title}
        loading="lazy"
        decoding="async"
        data-nsfw-blur={if @nsfw_blur?, do: "1"}
        style={if @nsfw_blur?, do: "--nsfw-blur-size: 100;"}
        class={["aspect-9/13 object-cover object-center", @class]}
      />
    <% else %>
      <span class={[
        "bg-surface-elevated text-foreground-tertiary flex aspect-9/13 items-center justify-center text-xs",
        @class
      ]}>
        No cover
      </span>
    <% end %>
    """
  end

  defp cover_needs_blur?(vn) when is_map(vn) do
    Map.get(vn, :is_image_nsfw) == true or Map.get(vn, :is_image_suggestive) == true
  end

  defp cover_needs_blur?(_), do: false

  defp post_cover?(%{entity: %{type: :visual_novel, visual_novel: %{}}}), do: true
  defp post_cover?(_post), do: false

  defp post_verb(%{entity: %{type: :user}}), do: "posted to"
  defp post_verb(%{entity: %{type: :category}}), do: "posted in"
  defp post_verb(_post), do: "posted about"

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_), do: "/"

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp image_url(%{images: %{medium: medium}}) when is_binary(medium), do: medium
  defp image_url(%{images: %{large: large}}) when is_binary(large), do: large
  defp image_url(%{images: %{small: small}}) when is_binary(small), do: small
  defp image_url(_), do: nil

  defp image_srcset(%{images: images}) when is_map(images) do
    [
      srcset_entry(images[:small], "128w"),
      srcset_entry(images[:medium], "256w"),
      srcset_entry(images[:large], "512w"),
      srcset_entry(images[:xl], "1024w")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      srcset -> srcset
    end
  end

  defp image_srcset(_), do: nil

  defp srcset_entry(nil, _width), do: nil
  defp srcset_entry(url, width), do: "#{url} #{width}"

  defp datetime_attr(nil), do: nil
  defp datetime_attr(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp datetime_attr(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp datetime_title(value),
    do: KaguyaWeb.SharedComponents.Time.format_datetime_tooltip(value)
end

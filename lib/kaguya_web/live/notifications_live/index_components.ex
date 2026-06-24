defmodule KaguyaWeb.NotificationsLive.IndexComponents do
  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.LoadMore

  @moduledoc false

  @kaguya_avatar_url "https://images.kaguya.io/ui/favicon-kaguya.png"

  attr :notifications, :list, required: true
  attr :load_more?, :boolean, required: true
  attr :load_more_disabled?, :boolean, default: false
  attr :unread_count, :integer, default: 0

  def notifications_page(assigns) do
    ~H"""
    <main
      id="notifications-page"
      phx-hook="NotificationsReadTracker"
      data-had-unread={@unread_count > 0}
      class="lg:bg-surface-base lg:border-border-divider text-foreground-primary min-h-dvh rounded-[12px] px-0 pb-[110px] sm:pt-8 sm:pb-32 lg:border lg:pt-14 lg:pb-8 dark:lg:bg-transparent"
    >
      <div class="md:bg-surface-elevated mx-auto max-w-[917px] rounded-[12px]">
        <div class="px-5 md:px-8">
          <div class="mt-5 pb-1.5 md:mt-0 md:pt-6 md:pb-2">
            <h1 class="md:text-style-heading2Medium text-foreground-primary text-style-heading3Medium">
              Notifications
            </h1>
          </div>

          <div :if={@notifications == []} class="py-20 md:py-28">
            <div class="mx-auto flex w-full max-w-[420px] flex-col items-center justify-center px-6 text-center">
              <div class="flex size-14 items-center justify-center rounded-full border border-white/5 bg-white/3 md:size-16">
                <Lucide.bell class="text-foreground-secondary/30 size-6 md:size-7" aria-hidden />
              </div>
              <p class="md:text-style-body1Regular text-foreground-secondary text-style-body2Regular mt-4">
                You're all caught up
              </p>
              <p class="md:text-style-body2Regular text-foreground-secondary/50 text-style-captionRegular mt-1">
                New activity will show up here
              </p>
            </div>
          </div>

          <div :if={@notifications != []}>
            <.notification_card
              :for={{notification, index} <- Enum.with_index(@notifications)}
              notification={notification}
              show_divider={index < length(@notifications) - 1}
            />
          </div>

          <div :if={@load_more?} class="flex w-full items-center justify-center py-6">
            <.load_more phx-click="load-more-notifications" disabled={@load_more_disabled?} />
          </div>
        </div>
      </div>
    </main>
    """
  end

  attr :notification, :map, required: true
  attr :show_divider, :boolean, default: false

  def notification_card(assigns) do
    assigns =
      assigns
      |> assign(:type_key, Map.get(assigns.notification, :type_key, ""))
      |> assign(:message_tokens, message_tokens(assigns.notification))

    ~H"""
    <article class={[
      "group hover:bg-surface-elevated -mx-5 flex items-stretch gap-2 px-5 transition-colors md:-mx-8 md:px-8 dark:hover:bg-white/2",
      !@notification.read && "bg-white/1"
    ]}>
      <button
        type="button"
        class="flex min-w-0 flex-1 cursor-pointer items-start gap-2 py-2.5 text-left md:gap-3.5 md:py-3.5"
        phx-click="open-notification"
        phx-value-id={@notification.id}
        phx-value-url={@notification.link}
      >
        <.actor_avatar_group notification={@notification} />

        <div class="flex min-w-0 flex-1 items-start justify-between gap-2 md:gap-3">
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <div class="min-w-0">
              <.notification_icon
                notification={@notification}
                type_key={@type_key}
                class="mr-2.5 hidden align-middle md:inline-flex"
              />
              <span class="text-foreground-secondary text-sm/snug">
                <%= for token <- @message_tokens do %>
                  <span class={token.class}>{token.text}</span>
                <% end %>
              </span>
              <span class="text-foreground-secondary/60 hidden text-xs md:inline">
                <span class="mx-1">·</span>
                <time title={inserted_title(@notification.inserted_at)}>
                  {@notification.inserted_label}
                </time>
              </span>
            </div>

            <time
              title={inserted_title(@notification.inserted_at)}
              class="text-foreground-secondary/50 text-[11px] md:hidden"
            >
              {@notification.inserted_label}
            </time>

            <p
              :if={@notification.text_preview}
              class="border-l-button-background-brand-default text-foreground-secondary mt-1.5 line-clamp-2 border-l-2 px-2 py-1 text-xs md:ml-[22px] md:line-clamp-none md:text-sm"
            >
              {@notification.text_preview}
            </p>
          </div>

          <.notification_media notification={@notification} type_key={@type_key} />
        </div>
      </button>
    </article>

    <div :if={@show_divider} class="border-border-divider mx-5 border-b md:mx-5" />
    """
  end

  attr :notification, :map, required: true

  defp actor_avatar_group(assigns) do
    assigns =
      assigns
      |> assign(:actors, Map.get(assigns.notification, :actors, []))
      |> assign(:read?, Map.get(assigns.notification, :read, true))

    ~H"""
    <div class="relative mt-px shrink-0 md:mt-0.5">
      <span
        :if={!@read?}
        class="absolute -top-0.5 -left-0.5 z-10 size-2 rounded-full bg-[#2e70e8]"
      />

      <%= cond do %>
        <% @actors == [] -> %>
          <span class="bg-surface-elevated flex size-7 items-center justify-center overflow-hidden rounded-full ring-1 ring-white/10 md:size-10">
            <img src={kaguya_avatar_url()} alt="Kaguya" class="size-full object-cover" />
          </span>
        <% length(@actors) == 1 -> %>
          <% actor = hd(@actors) %>
          <.actor_avatar actor={actor} class="size-7 md:size-10" />
        <% true -> %>
          <span class="flex -space-x-2 md:-space-x-2.5">
            <.actor_avatar
              :for={actor <- Enum.take(@actors, 3)}
              actor={actor}
              class="ring-surface-elevated size-6 ring-2 md:size-9"
            />
          </span>
      <% end %>
    </div>
    """
  end

  attr :actor, :map, required: true
  attr :class, :string, default: "size-8"

  defp actor_avatar(assigns) do
    ~H"""
    <span class={["bg-surface-menu-item-hover block overflow-hidden rounded-full", @class]}>
      <img
        :if={avatar_url(@actor)}
        src={avatar_url(@actor)}
        alt={@actor.username}
        class="size-full object-cover"
      />
      <span
        :if={!avatar_url(@actor)}
        class="text-foreground-secondary flex size-full items-center justify-center text-xs font-semibold"
      >
        {username_initial(@actor.username)}
      </span>
    </span>
    """
  end

  attr :notification, :map, required: true
  attr :type_key, :string, required: true

  defp notification_media(assigns) do
    ~H"""
    <div class="flex shrink-0 items-center gap-1 md:gap-1.5">
      <div
        :if={list_notification?(@type_key) && @notification.list_cover_urls != []}
        class="flex shrink-0 -space-x-2.5 overflow-hidden md:-space-x-4"
      >
        <img
          :for={{cover_url, index} <- Enum.with_index(@notification.list_cover_urls)}
          src={cover_url}
          alt="cover image"
          class="h-[48px] w-[32px] shrink-0 rounded-[2px] object-cover object-center ring-1 ring-black/30 md:h-20 md:w-[53.33px] md:rounded-[4px]"
          style={"z-index: #{3 - index};"}
        />
      </div>

      <img
        :if={!list_notification?(@type_key) && @notification.thumbnail_url}
        src={@notification.thumbnail_url}
        alt="notification thumbnail"
        class="h-[48px] w-[32px] shrink-0 rounded-[2px] object-cover object-center md:h-20 md:w-[53.33px] md:rounded-[6px]"
      />
    </div>
    """
  end

  attr :notification, :map, required: true
  attr :type_key, :string, required: true
  attr :class, :string, default: nil

  defp notification_icon(assigns) do
    ~H"""
    <span class={["size-5 shrink-0 items-center justify-center", @class]}>
      <%= case @type_key do %>
        <% "follow_user" -> %>
          <.follow_icon />
        <% "like_review" -> %>
          <.like_heart_icon />
        <% "like_post" -> %>
          <.like_heart_icon />
        <% "like_comment" -> %>
          <.like_comment_icon />
        <% "reply_comment" -> %>
          <.reply_comment_icon />
        <% "new_comment_review" -> %>
          <.new_comment_review_icon />
        <% "new_comment_post" -> %>
          <.new_comment_review_icon />
        <% "mention_post" -> %>
          <.new_comment_review_icon />
        <% "new_comment_vn_list" -> %>
          <.list_comment_icon />
        <% "new_comment_list" -> %>
          <.list_comment_icon />
        <% "like_vn_list" -> %>
          <.like_list_icon />
        <% "like_list" -> %>
          <.like_list_icon />
        <% "report_reviewed_report" -> %>
          <.shield_status_icon status={meta_string(@notification, :report_status)} kind={:report} />
        <% _ -> %>
          <Lucide.message_square class="text-foreground-secondary size-5" aria-hidden />
      <% end %>
    </span>
    """
  end

  defp follow_icon(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M7.11111 5.88889C7.11111 4.59227 7.62619 3.34877 8.54303 2.43192C9.45988 1.51508 10.7034 1 12 1C13.2966 1 14.5401 1.51508 15.457 2.43192C16.3738 3.34877 16.8889 4.59227 16.8889 5.88889C16.8889 7.1855 16.3738 8.42901 15.457 9.34586C14.5401 10.2627 13.2966 10.7778 12 10.7778C10.7034 10.7778 9.45988 10.2627 8.54303 9.34586C7.62619 8.42901 7.11111 7.1855 7.11111 5.88889ZM7.11111 13.2222C5.49034 13.2222 3.93596 13.8661 2.7899 15.0121C1.64385 16.1582 1 17.7126 1 19.3333C1 20.3058 1.38631 21.2384 2.07394 21.9261C2.76158 22.6137 3.69421 23 4.66667 23H19.3333C20.3058 23 21.2384 22.6137 21.9261 21.9261C22.6137 21.2384 23 20.3058 23 19.3333C23 17.7126 22.3562 16.1582 21.2101 15.0121C20.064 13.8661 18.5097 13.2222 16.8889 13.2222H7.11111Z"
        fill="rgb(155, 1, 61)"
      />
    </svg>
    """
  end

  attr :class, :string, default: nil

  defp like_heart_icon(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M11.4441 24L9.78474 22.4894C3.89101 17.145 0 13.6087 0 9.29428C0 5.75804 2.76948 3 6.29428 3C8.28556 3 10.1967 3.92698 11.4441 5.38038C12.6916 3.92698 14.6027 3 16.594 3C20.1188 3 22.8883 5.75804 22.8883 9.29428C22.8883 13.6087 18.9973 17.145 13.1035 22.4894L11.4441 24Z"
        class="fill-[#E947C6] dark:fill-[#F91880]"
      />
    </svg>
    """
  end

  attr :class, :string, default: nil

  defp reply_comment_icon(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
      aria-hidden="true"
    >
      <g>
        <path
          d="M12.0025 23C14.4016 22.9995 16.7348 22.2146 18.6465 20.765C20.5581 19.3154 21.9435 17.2805 22.5913 14.9705C23.2392 12.6605 23.1141 10.202 22.2351 7.96971C21.356 5.7374 19.7713 3.85369 17.7224 2.60562C15.6734 1.35755 13.2726 0.813577 10.8858 1.05659C8.49901 1.2996 6.2571 2.31627 4.50173 3.95167C2.74636 5.58707 1.57378 7.75152 1.1627 10.1152C0.75161 12.4788 1.12455 14.9121 2.22469 17.0441L1.00247 23L6.95835 21.7778C8.46902 22.5588 10.185 23 12.0025 23Z"
          stroke-width="1.33333"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="stroke-[#21A9BD] dark:stroke-[#50DDF2]"
          fill="none"
        />
        <path
          d="M6.75 12.5H6.76278V12.5128H6.75V12.5ZM12.5 12.5H12.5128V12.5128H12.5V12.5ZM18.25 12.5H18.2628V12.5128H18.25V12.5Z"
          stroke-width="2"
          stroke-linejoin="round"
          class="stroke-[#21A9BD] dark:stroke-[#50DDF2]"
          fill="none"
        />
      </g>
    </svg>
    """
  end

  defp like_comment_icon(assigns) do
    ~H"""
    <span class="relative inline-flex size-5">
      <.reply_comment_icon />
      <.like_heart_icon class="absolute -top-1 -right-1.5 size-[10px]" />
    </span>
    """
  end

  attr :class, :string, default: nil

  defp new_comment_review_icon(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
      aria-hidden="true"
    >
      <g>
        <path
          d="M10.0199 23.1125H8.97782C5.21701 23.1125 3.33545 23.1125 2.16715 21.9257C0.998842 20.7389 1 18.8283 1 15.0073V9.21791C1 5.3969 1 3.48639 2.16946 2.30071C3.33545 1.11157 5.21701 1.11157 8.97782 1.11157H12.397C16.159 1.11157 18.3567 1.17641 19.525 2.36208C20.6944 3.55007 20.6829 5.39574 20.6829 9.21675V10.5912M16.5677 0V2.31577M10.7783 0V2.31577M4.98891 0V2.31577M6.21048 15.0525H10.842M6.21048 9.26307H15.4735"
          stroke="#8465FF"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <path
          opacity="0.93"
          d="M22.1426 14.9158C21.0936 13.7405 20.4649 13.8112 19.7666 14.0208C19.2769 14.0902 17.6002 16.0471 16.9009 16.6723C15.7534 17.8047 14.6002 18.9719 14.5249 19.1247C14.3072 19.4779 14.1058 20.1031 14.0073 20.8025C13.8255 21.8515 13.5639 23.0314 13.895 23.1333C14.2262 23.2352 15.1536 23.0407 16.2015 22.8867C16.9009 22.7593 17.3895 22.6204 17.7392 22.4108C18.229 22.1167 19.1368 21.0827 20.7034 19.5439C21.6841 18.5099 22.6313 17.7955 22.9115 17.0973C23.1905 16.0482 22.7725 15.489 22.1426 14.9158Z"
          stroke="#8465FF"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </g>
    </svg>
    """
  end

  attr :class, :string, default: nil

  defp list_comment_icon(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      class={@class}
      aria-hidden="true"
    >
      <path
        d="M1 6.85714C1 6.62981 1.09301 6.4118 1.25856 6.25105C1.42411 6.09031 1.64865 6 1.88278 6H27.7777C28.0118 6 28.2364 6.09031 28.4019 6.25105C28.5675 6.4118 28.6605 6.62981 28.6605 6.85714C28.6605 7.08447 28.5675 7.30249 28.4019 7.46323C28.2364 7.62398 28.0118 7.71428 27.7777 7.71428H1.88278C1.64865 7.71428 1.42411 7.62398 1.25856 7.46323C1.09301 7.30249 1 7.08447 1 6.85714ZM1.88278 16.8571H10.1221C10.3562 16.8571 10.5807 16.7668 10.7463 16.6061C10.9119 16.4453 11.0049 16.2273 11.0049 16C11.0049 15.7726 10.9119 15.5546 10.7463 15.3939C10.5807 15.2331 10.3562 15.1428 10.1221 15.1428H1.88278C1.64865 15.1428 1.42411 15.2331 1.25856 15.3939C1.09301 15.5546 1 15.7726 1 16C1 16.2273 1.09301 16.4453 1.25856 16.6061C1.42411 16.7668 1.64865 16.8571 1.88278 16.8571ZM12.4762 24.2857H1.88278C1.64865 24.2857 1.42411 24.376 1.25856 24.5367C1.09301 24.6975 1 24.9155 1 25.1428C1 25.3701 1.09301 25.5882 1.25856 25.7489C1.42411 25.9096 1.64865 25.9999 1.88278 25.9999H12.4762C12.7103 25.9999 12.9348 25.9096 13.1004 25.7489C13.2659 25.5882 13.3589 25.3701 13.3589 25.1428C13.3589 24.9155 13.2659 24.6975 13.1004 24.5367C12.9348 24.376 12.7103 24.2857 12.4762 24.2857ZM30.6938 18.0343L27.2377 20.8042L28.2912 24.9371C28.3329 25.1009 28.3239 25.273 28.2653 25.4319C28.2067 25.5908 28.1011 25.7293 27.9617 25.8302C27.8224 25.931 27.6554 25.9896 27.4819 25.9987C27.3084 26.0079 27.1359 25.967 26.9862 25.8814L23.0695 23.6428L19.1529 25.8814C19.0032 25.967 18.8307 26.0079 18.6572 25.9987C18.4836 25.9896 18.3167 25.931 18.1774 25.8302C18.038 25.7293 17.9324 25.5908 17.8738 25.4319C17.8152 25.273 17.8062 25.1009 17.8479 24.9371L18.9013 20.8042L15.4453 18.0343C15.3095 17.9255 15.2103 17.7798 15.1605 17.6159C15.1107 17.452 15.1124 17.2773 15.1656 17.1144C15.2187 16.9515 15.3208 16.8077 15.4587 16.7015C15.5966 16.5953 15.7641 16.5316 15.9396 16.5185L20.5006 16.1757L22.253 12.2314C22.3216 12.0785 22.4348 11.9483 22.5785 11.8569C22.7223 11.7655 22.8904 11.7168 23.0622 11.7168C23.234 11.7168 23.4021 11.7655 23.5458 11.8569C23.6896 11.9483 23.8027 12.0785 23.8714 12.2314L25.6237 16.1757L30.1848 16.5185C30.3603 16.5316 30.5277 16.5953 30.6657 16.7015C30.8036 16.8077 30.9057 16.9515 30.9588 17.1144C31.0119 17.2773 31.0137 17.452 30.9639 17.6159C30.914 17.7798 30.8149 17.9255 30.6791 18.0343H30.6938ZM27.8836 18.0643L24.9661 17.8457C24.8068 17.8324 24.6543 17.7774 24.5248 17.6866C24.3952 17.5958 24.2935 17.4725 24.2304 17.33L23.0695 14.7343L21.916 17.33C21.853 17.4725 21.7512 17.5958 21.6217 17.6866C21.4921 17.7774 21.3396 17.8324 21.1804 17.8457L18.2628 18.0643L20.4609 19.8257C20.5891 19.9286 20.6848 20.0646 20.7369 20.218C20.7889 20.3715 20.7953 20.536 20.7552 20.6928L20.074 23.37L22.6282 21.91C22.7637 21.8326 22.9182 21.7918 23.0754 21.7918C23.2327 21.7918 23.3871 21.8326 23.5227 21.91L26.0784 23.37L25.3971 20.6928C25.3571 20.536 25.3634 20.3715 25.4155 20.218C25.4675 20.0646 25.5632 19.9286 25.6914 19.8257L27.8836 18.0643Z"
        fill="#64CB93"
      />
    </svg>
    """
  end

  defp like_list_icon(assigns) do
    ~H"""
    <span class="relative inline-flex size-5">
      <.list_comment_icon />
      <.like_heart_icon class="absolute -top-1 -right-1.5 size-[10px]" />
    </span>
    """
  end

  attr :status, :string, default: nil
  attr :kind, :atom, required: true

  defp shield_status_icon(assigns) do
    ~H"""
    <Lucide.shield_check
      class={["inline-block size-5 align-[-0.2em]", shield_color(@kind, @status)]}
      aria-hidden
    />
    """
  end

  defp shield_color(:report, "resolved"), do: "text-emerald-300"
  defp shield_color(:report, _), do: "text-zinc-400"

  defp actor_tokens(actors, actors_count) when is_list(actors) do
    shown_actors = Enum.take(actors, 2)
    shown_count = length(shown_actors)
    count = max(actors_count || shown_count, shown_count)
    remaining = max(count - shown_count, 0)

    case {shown_count, count} do
      {0, 0} ->
        [%{text: "System", class: "font-medium text-foreground-primary"}]

      {0, 1} ->
        [%{text: "Someone", class: "font-medium text-foreground-primary"}]

      {0, _} ->
        [
          %{text: "Someone", class: "font-medium text-foreground-primary"},
          %{text: " and #{remaining} #{plural_other(remaining)}", class: ""}
        ]

      {1, 1} ->
        [%{text: actor_username(hd(shown_actors)), class: "font-medium text-foreground-primary"}]

      {1, _} ->
        [
          %{text: actor_username(hd(shown_actors)), class: "font-medium text-foreground-primary"},
          %{text: ", and #{remaining} #{plural_other(remaining)}", class: ""}
        ]

      {2, _} ->
        [
          %{
            text: actor_username(Enum.at(shown_actors, 0)),
            class: "font-medium text-foreground-primary"
          },
          %{text: " and ", class: ""},
          %{
            text: actor_username(Enum.at(shown_actors, 1)),
            class: "font-medium text-foreground-primary"
          }
        ] ++ remaining_tokens(remaining)
    end
  end

  defp actor_tokens(_actors, _actors_count),
    do: [%{text: "System", class: "font-medium text-foreground-primary"}]

  defp remaining_tokens(0), do: []
  defp remaining_tokens(1), do: [%{text: ", and 1 other", class: ""}]
  defp remaining_tokens(n), do: [%{text: ", and #{n} others", class: ""}]

  defp actor_username(%{username: username}) when is_binary(username) and username != "",
    do: username

  defp actor_username(_), do: "Someone"

  defp plural_other(1), do: "other"
  defp plural_other(_), do: "others"

  defp message_tokens(notification) do
    actors = Map.get(notification, :actors, [])
    actors_count = Map.get(notification, :actors_count, 0)
    type_key = Map.get(notification, :type_key, "")
    target = Map.get(notification, :target_name)

    case type_key do
      "follow_user" ->
        actor_tokens(actors, actors_count) ++ [verb(" started following you")]

      "like_review" ->
        actor_tokens(actors, actors_count) ++
          [verb(" liked your review of "), target_name_token(target || "this VN")]

      "like_comment" ->
        actor_tokens(actors, actors_count) ++
          [
            verb(" liked your #{comment_type_word(notification)}comment on "),
            target_name_token(target || "this VN")
          ]

      "reply_comment" ->
        actor_tokens(actors, actors_count) ++
          [verb(" replied to your comment on "), target_name_token(target || "this VN")]

      "new_comment_review" ->
        actor_tokens(actors, actors_count) ++
          [verb(" commented on your review of "), target_name_token(target || "this VN")]

      t when t in ["like_list", "like_vn_list"] ->
        actor_tokens(actors, actors_count) ++
          [verb(" liked your list, "), target_name_token(target || "this list")]

      t when t in ["new_comment_list", "new_comment_vn_list"] ->
        actor_tokens(actors, actors_count) ++
          [verb(" commented on your list, "), target_name_token(target || "this list")]

      "new_comment_post" ->
        actor_tokens(actors, actors_count) ++
          post_target_tokens(target, " commented on your discussion")

      "like_post" ->
        actor_tokens(actors, actors_count) ++ post_target_tokens(target, " liked your post")

      "mention_post" ->
        actor_tokens(actors, actors_count) ++ post_target_tokens(target, " posted")

      "report_reviewed_report" ->
        report_reviewed_tokens(notification)

      _ ->
        actor_tokens(actors, actors_count) ++ [verb(" has a notification")]
    end
  end

  defp verb(text), do: %{text: text, class: ""}

  defp target_name_token(target),
    do: %{text: target, class: "font-medium text-foreground-primary"}

  defp post_target_tokens(target, verb_text) do
    if is_binary(target) and target != "" do
      [verb(verb_text <> ", "), target_name_token(target)]
    else
      [verb(verb_text)]
    end
  end

  defp comment_type_word(notification) do
    case meta_string(notification, :parent_entity_type) do
      "post" -> "discussion "
      "review" -> "review "
      "list" -> "list "
      _ -> ""
    end
  end

  defp report_reviewed_tokens(notification) do
    status =
      case meta_string(notification, :report_status) do
        nil -> "reviewed"
        s -> humanize_status(s)
      end

    target = Map.get(notification, :target_name) || "your report"

    [verb("Kaguya #{status} your report about "), target_name_token(target)]
  end

  defp humanize_status(status) when is_binary(status), do: String.replace(status, "_", " ")
  defp humanize_status(_), do: "reviewed"

  defp meta_string(%{metadata: meta}, key) when is_map(meta) do
    case Map.get(meta, key) || Map.get(meta, to_string(key)) do
      s when is_binary(s) -> s
      s when is_atom(s) and not is_nil(s) -> Atom.to_string(s)
      _ -> nil
    end
  end

  defp meta_string(_, _), do: nil

  defp list_notification?(type_key) do
    type_key in ["like_vn_list", "new_comment_vn_list", "like_list", "new_comment_list"]
  end

  defp avatar_url(%{avatar_url: url}) when is_binary(url) and url != "", do: url
  defp avatar_url(_), do: nil

  defp username_initial(username) when is_binary(username) and username != "" do
    username |> String.first() |> String.upcase()
  end

  defp username_initial(_), do: "?"

  defp inserted_title(value),
    do: KaguyaWeb.SharedComponents.Time.format_datetime_tooltip(value)

  defp kaguya_avatar_url, do: @kaguya_avatar_url
end

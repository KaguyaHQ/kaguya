defmodule KaguyaWeb.Components.Discussions.PostList do
  @moduledoc """
  Reusable discussion post list components ported from the Next
  `PostList` / `PostListItem` pair.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.SharedComponents.LoadMore

  alias KaguyaWeb.Components.Profile.Shared
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  attr :posts, :list, required: true
  attr :has_more, :boolean, default: false
  attr :loading_more, :boolean, default: false
  attr :show_removal_notice, :boolean, default: false

  def post_list(assigns) do
    ~H"""
    <div class="divide-y divide-[rgb(var(--border-divider)/0.6)]">
      <.post_list_item
        :for={post <- @posts}
        post={post}
        show_removal_notice={@show_removal_notice}
      />
    </div>

    <%= if @has_more do %>
      <div
        id="profile-discussions-auto-loader"
        phx-viewport-bottom="load_more_discussions"
        aria-hidden="true"
        class="h-px w-full"
      />
      <div class="flex justify-center py-6">
        <.load_more
          phx-click="load_more_discussions"
          disabled={@loading_more}
          label="Load more"
          loading_label="Loading…"
          class="px-6"
        />
      </div>
    <% end %>
    """
  end

  attr :post, :map, required: true
  attr :compact, :boolean, default: false
  attr :show_removal_notice, :boolean, default: false

  def post_list_item(assigns) do
    assigns =
      assigns
      |> assign(:removed?, not is_nil(assigns.post[:hidden_at]))
      |> assign(:display_title, display_title(assigns.post))
      |> assign(:preview, content_preview(assigns.post[:content]))
      |> assign(:activity_date, activity_date(assigns.post))
      |> assign(:activity_users, activity_users(assigns.post))
      |> assign(:show_comments_count, (assigns.post[:comments_count] || 0) > 0)
      |> assign(:show_likes_count, (assigns.post[:likes_count] || 0) > 0)
      |> assign(:href, assigns.post[:href] || "#")
      |> assign(:entity_tag, assigns.post[:entity_tag])

    ~H"""
    <div class="relative -mx-3 rounded-lg px-3 py-3.5 transition-colors lg:py-4 lg:hover:bg-white/2">
      <.link
        navigate={@href}
        class="absolute inset-0 z-1 rounded-lg"
        tabindex="-1"
        aria-hidden="true"
      >
      </.link>

      <div class="flex gap-3">
        <div class="relative z-10 w-8 shrink-0 lg:w-9">
          <.link navigate={"/@" <> (@post.user.username || "")}>
            <Shared.avatar
              user={@post.user}
              class="size-7 rounded-full object-cover lg:size-8"
              sizes="32px"
            />
          </.link>
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex items-start gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-1.5">
                <Lucide.pin
                  :if={@post.is_pinned}
                  class="mt-0.5 size-[11px] shrink-0 text-[rgb(var(--foreground-tertiary))]"
                  aria-hidden
                />
                <h3 class="line-clamp-2 text-[14px] leading-snug font-medium text-[rgb(var(--foreground-primary))]">
                  {@display_title}
                </h3>
              </div>
            </div>
          </div>

          <p
            :if={!@compact and present?(@preview)}
            class="mt-0.5 line-clamp-1 text-[13px] text-[rgb(var(--foreground-tertiary))]"
          >
            {@preview}
          </p>

          <.removal_notice :if={@show_removal_notice and @removed?} class="mt-3" />

          <div class="mt-1.5 flex items-center gap-2 text-xs text-[rgb(var(--foreground-tertiary))]">
            <div class="flex min-w-0 items-center gap-1 truncate">
              <.link
                navigate={"/@" <> (@post.user.username || "")}
                class="relative z-10 font-medium text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
              >
                {@post.user.display_name || @post.user.username}
              </.link>

              <%= if @post.last_comment_user do %>
                <span class="text-[rgb(var(--foreground-quaternary))]">·</span>
                <.link
                  navigate={"/@" <> (@post.last_comment_user.username || "")}
                  class="relative z-10 text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
                >
                  {@post.last_comment_user.display_name || @post.last_comment_user.username}
                </.link>
                <span class="relative z-10" title={datetime_title(@post.last_comment_at)}>
                  {@activity_date}
                </span>
              <% else %>
                <span class="relative z-10" title={datetime_title(@post.inserted_at)}>
                  {@activity_date}
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <div class="flex min-w-[72px] shrink-0 flex-col items-end justify-center gap-2">
          <Lucide.lock
            :if={@post.is_locked and @show_removal_notice and @removed?}
            class="size-3 shrink-0 text-[rgb(var(--foreground-tertiary))]"
            aria-hidden
          />

          <div
            :if={@activity_users != [] or @show_comments_count or @show_likes_count}
            class="flex items-center justify-end gap-2 text-xs leading-none text-[rgb(var(--foreground-tertiary))] tabular-nums"
          >
            <div :if={@activity_users != []} class="flex -space-x-1.5">
              <.link
                :for={{user, index} <- Enum.with_index(@activity_users)}
                navigate={"/@" <> (user.username || "")}
                class="relative z-10 transition-transform hover:-translate-y-0.5"
                style={"z-index: #{length(@activity_users) - index};"}
                aria-label={user.display_name || user.username || "Commenter"}
              >
                <Shared.avatar
                  user={user}
                  class="size-5 rounded-full object-cover ring-2 ring-[rgb(var(--surface-base))]"
                  sizes="20px"
                />
              </.link>
            </div>

            <div :if={@show_likes_count} class="flex h-4 items-center gap-1 text-current">
              <Lucide.heart class="size-[11px] shrink-0 stroke-current" aria-hidden />
              <span class="inline-block min-w-[1ch] text-left text-current">
                {Shared.format_short_number(@post.likes_count || 0)}
              </span>
            </div>

            <div :if={@show_comments_count} class="flex h-4 items-center gap-1 text-current">
              <Lucide.message_square class="size-[11px] shrink-0 stroke-current" aria-hidden />
              <span class="inline-block min-w-[1ch] text-left text-current">
                {Shared.format_short_number(@post.comments_count || 0)}
              </span>
            </div>
          </div>

          <.link
            :if={@entity_tag}
            navigate={@entity_tag.href}
            class="relative z-10 inline-flex max-w-[140px] truncate rounded bg-white/6 px-1.5 py-0.5 text-[10px] font-medium text-[rgb(var(--foreground-tertiary))] transition-colors hover:bg-white/10"
          >
            {@entity_tag.label}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil

  defp removal_notice(assigns) do
    ~H"""
    <div class={[
      "rounded-[6px] border border-[rgb(var(--border-divider))] bg-white/3 px-3 py-2 text-xs text-[rgb(var(--foreground-tertiary))]",
      @class
    ]}>
      This post was removed.
    </div>
    """
  end

  defp display_title(%{hidden_at: hidden_at, title: title})
       when not is_nil(hidden_at) and title in [nil, ""],
       do: "Removed post"

  defp display_title(%{title: title}) when is_binary(title), do: title
  defp display_title(_post), do: "Untitled post"

  defp content_preview(nil), do: nil

  defp content_preview(content) when is_binary(content) do
    content
    |> String.replace(~r/\|\|[\s\S]*?\|\|/u, "[spoiler]")
    |> String.replace(~r/```[\s\S]*?```/u, " ")
    |> String.replace(~r/`([^`]+)`/u, "\\1")
    |> String.replace(~r/!\[([^\]]*)\]\([^)]*\)/u, "\\1")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/u, "\\1")
    |> String.replace(~r/(\*\*|__)(.+?)\1/u, "\\2")
    |> String.replace(~r/(\*|_)(.+?)\1/u, "\\2")
    |> String.replace(~r/~~(.+?)~~/u, "\\1")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, 160)
  end

  defp activity_date(post),
    do: SharedTime.calendar_custom(post[:last_comment_at] || post[:inserted_at])

  defp activity_users(%{recent_comment_users: users, user: %{id: user_id}}) when is_list(users) do
    users
    |> Enum.reject(&(Map.get(&1, :id) == user_id))
    |> Enum.take(3)
  end

  defp activity_users(_post), do: []

  defp datetime_title(value), do: SharedTime.format_datetime_tooltip(value)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

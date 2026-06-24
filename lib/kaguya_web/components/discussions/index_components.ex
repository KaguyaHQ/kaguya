defmodule KaguyaWeb.Discussions.IndexComponents do
  @moduledoc """
  Rendering components for migrated discussion browse pages.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.AuthPromptComponents, only: [auth_button: 1]
  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.UI.ConfirmDialog, only: [confirm_dialog: 1]

  import KaguyaWeb.UI.Menu, only: [menu: 1]

  attr :posts, :list, required: true
  attr :pinned_posts, :list, default: []
  attr :categories, :list, required: true
  attr :current_user, :map, default: nil
  attr :sort, :string, default: "recent"
  attr :has_next, :boolean, default: false
  attr :loading_more, :boolean, default: false
  attr :can_discuss, :boolean, default: false
  attr :can_moderate_discussions, :boolean, default: false
  attr :active_slug, :string, default: nil

  def discussions_index(assigns) do
    ~H"""
    <.browse_shell
      categories={@categories}
      active_slug={@active_slug}
      sort={@sort}
      current_user={@current_user}
      can_discuss={@can_discuss}
      can_moderate_discussions={@can_moderate_discussions}
    >
      <.feed
        posts={@posts}
        pinned_posts={@pinned_posts}
        has_next={@has_next}
        loading_more={@loading_more}
      />
    </.browse_shell>
    """
  end

  attr :posts, :list, required: true
  attr :pinned_posts, :list, default: []
  attr :category, :map, required: true
  attr :categories, :list, required: true
  attr :current_user, :map, default: nil
  attr :sort, :string, default: "recent"
  attr :has_next, :boolean, default: false
  attr :loading_more, :boolean, default: false
  attr :can_discuss, :boolean, default: false
  attr :can_moderate_discussions, :boolean, default: false

  def discussions_category(assigns) do
    ~H"""
    <.browse_shell
      categories={@categories}
      active_slug={@category.slug}
      sort={@sort}
      current_user={@current_user}
      can_discuss={@can_discuss}
      can_moderate_discussions={@can_moderate_discussions}
    >
      <.feed
        posts={@posts}
        pinned_posts={@pinned_posts}
        has_next={@has_next}
        loading_more={@loading_more}
      />
    </.browse_shell>
    """
  end

  attr :categories, :list, required: true
  attr :active_slug, :string, default: nil
  attr :sort, :string, default: "recent"
  attr :current_user, :map, default: nil
  attr :can_discuss, :boolean, default: false
  attr :can_moderate_discussions, :boolean, default: false
  slot :inner_block, required: true

  defp browse_shell(assigns) do
    ~H"""
    <div class="mx-auto mt-6 max-w-[768px] px-4 pb-20 lg:mt-10">
      <div class="mb-5 flex items-center justify-between gap-4">
        <h1 class="font-newsreader text-foreground-primary text-2xl font-medium tracking-[-0.01em]">
          Conversations
        </h1>
        <div class="flex shrink-0 items-center gap-2">
          <.sort_links active_slug={@active_slug} sort={@sort} />
          <.new_post_button
            :if={can_post_in_active_category?(@categories, @active_slug, @can_moderate_discussions)}
            current_user={@current_user}
            can_discuss={@can_discuss}
            mobile
          />
        </div>
      </div>

      <div class="border-border-divider/50 mb-5 border-b pb-3">
        <.category_filter categories={@categories} active_slug={@active_slug} />
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :categories, :list, required: true
  attr :active_slug, :string, default: nil

  defp category_filter(assigns) do
    ~H"""
    <nav class="no-scrollbar flex w-full items-center gap-1 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      <.link
        patch="/discussions"
        class={[
          "shrink-0 rounded-full px-2.5 py-1.5 text-[13px] transition-colors",
          is_nil(@active_slug) && "text-foreground-primary bg-white/8 font-medium",
          @active_slug &&
            "hover:text-foreground-primary text-foreground-tertiary hover:bg-white/4"
        ]}
      >
        All
      </.link>
      <.link
        :for={category <- @categories}
        patch={"/discussions/#{category.slug}"}
        class={[
          "shrink-0 rounded-full px-2.5 py-1.5 text-[13px] transition-colors",
          category.slug == @active_slug && "text-foreground-primary bg-white/8 font-medium",
          category.slug != @active_slug &&
            "hover:text-foreground-primary text-foreground-tertiary hover:bg-white/4"
        ]}
      >
        {category.name}
      </.link>
    </nav>
    """
  end

  attr :can_discuss, :boolean, default: false
  attr :current_user, :map, default: nil
  attr :mobile, :boolean, default: false

  defp new_post_button(assigns) do
    ~H"""
    <.auth_button
      event="open_new_post"
      is_logged_in={!!@current_user}
      modal_id="discussions-auth-prompt"
      auth_message="Sign in to start a discussion"
      class={[
        "bg-button-background-brand-default hover:bg-button-background-brand-default/90 flex h-8 items-center justify-center gap-1.5 rounded-md text-[13px] font-medium text-white transition-colors",
        @mobile && "px-3",
        !@mobile && "mb-5 w-full"
      ]}
    >
      <Lucide.plus class="size-3.5" aria-hidden /> New Post
    </.auth_button>
    """
  end

  attr :open, :boolean, default: false
  attr :discard_open, :boolean, default: false
  attr :form, :map, required: true
  attr :errors, :map, default: %{}
  attr :selected_target, :map, default: nil
  attr :target_query, :string, default: ""
  attr :target_results, :list, default: []
  attr :target_picker_open, :boolean, default: false
  attr :creating, :boolean, default: false
  attr :error_message, :string, default: nil
  attr :show_errors?, :boolean, default: false

  def new_post_dialog(assigns) do
    assigns =
      assign(assigns, :visible_errors, if(assigns.show_errors?, do: assigns.errors, else: %{}))

    ~H"""
    <div
      :if={@open}
      id="new-post-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-120 flex items-end justify-center bg-black/80 backdrop-blur-md sm:items-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-post-dialog-title"
        class="bg-surface-base text-foreground-primary max-h-full w-full overflow-y-auto outline-hidden sm:max-h-[80vh] sm:max-w-[720px] sm:rounded-lg"
      >
        <div class="border-border-divider flex items-center justify-between border-b px-5 py-3 sm:border-b-0 sm:px-6 sm:pt-6 sm:pb-0">
          <h2 id="new-post-dialog-title" class="text-foreground-primary text-lg font-semibold">
            New Post
          </h2>
          <button
            type="button"
            phx-click="close_new_post"
            data-modal-cancel
            class="sm:hover:text-foreground-primary sm:text-foreground-secondary text-foreground-primary flex size-11 items-center justify-center rounded-full transition-colors hover:bg-white/6 sm:size-8"
            aria-label="Close"
          >
            <Lucide.x class="size-5 sm:size-4" aria-hidden />
          </button>
        </div>

        <div class="p-5 sm:px-6 sm:pt-4 sm:pb-6">
          <form phx-change="validate_new_post" phx-submit="submit_new_post" class="flex flex-col">
            <div class="mb-4">
              <.target_picker
                selected_target={@selected_target}
                query={@target_query}
                results={@target_results}
                open={@target_picker_open}
              />
            </div>

            <p :if={@error_message} class="text-semantic-error mb-3 text-sm">{@error_message}</p>

            <div class="bg-text-field-bg border-text-field-border overflow-hidden rounded-lg border">
              <div class="px-3 pt-3 pb-2">
                <input
                  name="title"
                  value={@form["title"] || ""}
                  placeholder="Title"
                  maxlength="200"
                  data-modal-initial-focus
                  class={[
                    "placeholder:text-text-field-placeholder-text text-foreground-primary w-full bg-transparent text-base font-semibold focus:outline-hidden",
                    @visible_errors[:title] && "placeholder:text-semantic-error/60"
                  ]}
                />
                <p :if={@visible_errors[:title]} class="text-semantic-error mt-1 text-xs">
                  {@visible_errors[:title]}
                </p>
              </div>

              <div class="border-border-divider/40 mx-3 border-t"></div>

              <textarea
                name="content"
                rows="6"
                maxlength="20000"
                placeholder="Write something..."
                class={[
                  "placeholder:text-text-field-placeholder-text text-foreground-primary max-h-[400px] min-h-[150px] w-full resize-y rounded-none border-0 bg-transparent p-3 text-base focus:outline-hidden",
                  @visible_errors[:content] && "border-semantic-error"
                ]}
              ><%= @form["content"] || "" %></textarea>
              <p :if={@visible_errors[:content]} class="text-semantic-error px-3 pb-2 text-xs">
                {@visible_errors[:content]}
              </p>
            </div>

            <div class="flex justify-end gap-3 pt-4">
              <button
                type="button"
                phx-click="close_new_post"
                class="text-foreground-primary h-9 rounded-[4px] bg-white/6 px-4 text-sm font-medium transition-colors hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={@creating || is_nil(@selected_target)}
                class="bg-button-background-brand-default hover:bg-button-background-brand-hover h-9 rounded-[4px] px-5 text-sm font-medium text-white transition-colors disabled:cursor-not-allowed disabled:opacity-50"
                style="text-shadow: 0px 3.04px 3.04px rgba(0, 0, 0, 0.25)"
              >
                {if @creating, do: "Creating...", else: "Create Post"}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>

    <.confirm_dialog
      :if={@discard_open}
      id="new-post-discard"
      title="Discard changes?"
      tone={:guard}
      confirm_label="Discard"
      confirm_event="discard_new_post"
      cancel_label="Keep editing"
      cancel_event="keep_editing_new_post"
    >
      Your changes haven't been saved.
    </.confirm_dialog>
    """
  end

  attr :selected_target, :map, default: nil
  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :open, :boolean, default: false

  defp target_picker(assigns) do
    ~H"""
    <div class="relative" data-category-target-picker>
      <%= if @selected_target do %>
        <span class="text-foreground-primary inline-flex items-center gap-0.5 rounded-md bg-white/8 text-sm font-medium">
          <button
            type="button"
            phx-click="clear_category_target"
            class="px-2.5 py-1.5 transition-colors hover:text-white"
            aria-label={"Change topic: #{@selected_target.name}"}
          >
            {@selected_target.name}
          </button>
          <button
            type="button"
            phx-click="clear_category_target"
            class="mr-1.5 rounded-full p-0.5 transition-colors hover:bg-white/12"
            aria-label="Clear selected topic"
          >
            <Lucide.x class="size-3" aria-hidden />
          </button>
        </span>
      <% else %>
        <div class="relative">
          <.search_icon
            class="text-foreground-tertiary pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2"
            aria-hidden
          />
          <input
            type="text"
            name="target_query"
            value={@query}
            phx-focus="open_category_target_picker"
            phx-change="search_category_targets"
            phx-debounce="250"
            placeholder="Search topics, VNs, characters..."
            class="bg-text-field-bg border-text-field-border focus:border-text-field-border-focus placeholder:text-text-field-placeholder-text text-foreground-primary w-full rounded-lg border px-9 py-2.5 text-sm focus:outline-hidden"
          />
        </div>

        <div
          :if={@open}
          class="bg-surface-elevated border-border-divider absolute z-50 mt-1 max-h-[240px] w-full overflow-y-auto rounded-lg border p-1 shadow-md"
        >
          <div :if={@results == []} class="text-foreground-tertiary py-4 text-center text-sm">
            No results found.
          </div>

          <button
            :for={target <- @results}
            type="button"
            phx-click="select_category_target"
            phx-value-category_type={target.category_type}
            phx-value-entity_id={target.entity_id}
            phx-value-name={target.name}
            phx-value-slug={target.slug}
            class="flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left text-sm transition-colors hover:bg-white/4"
          >
            <%= if target.image_url do %>
              <img
                src={target.image_url}
                alt=""
                class="size-7 shrink-0 rounded object-cover"
                data-nsfw-blur={if target_cover_needs_blur?(target), do: "1"}
                style={if target_cover_needs_blur?(target), do: "--nsfw-blur-size: 28;"}
              />
            <% else %>
              <span class="flex size-7 shrink-0 items-center justify-center rounded bg-white/6">
                <.category_icon
                  category_type={target.category_type}
                  class="text-foreground-tertiary size-3.5"
                />
              </span>
            <% end %>
            <span class="text-foreground-primary truncate font-medium">{target.name}</span>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :posts, :list, required: true
  attr :pinned_posts, :list, default: []
  attr :has_next, :boolean, default: false
  attr :loading_more, :boolean, default: false

  defp feed(assigns) do
    ~H"""
    <.pinned_posts posts={@pinned_posts} />

    <.post_list posts={@posts} />

    <div :if={@has_next} class="flex w-full items-center justify-center py-6">
      <.load_more
        phx-click="load_more_posts"
        disabled={@loading_more}
        loading_label="Loading..."
      />
    </div>
    """
  end

  attr :posts, :list, required: true

  defp pinned_posts(assigns) do
    ~H"""
    <div :if={@posts != []} class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
      <.link
        :for={post <- @posts}
        navigate={post.url}
        class="border-border-divider/40 flex items-center gap-2.5 rounded-lg border bg-white/2 px-3 py-2.5 transition-colors hover:bg-white/4"
      >
        <Lucide.pin class="text-button-background-brand-default size-[13px] shrink-0" aria-hidden />
        <span class="text-foreground-primary flex-1 truncate text-sm font-medium">{post.title}</span>
        <span
          :if={post.comments_count > 0}
          class="text-foreground-tertiary flex shrink-0 items-center gap-0.5 text-xs"
        >
          <Lucide.message_square class="size-[11px]" aria-hidden />
          {format_short_count(post.comments_count)}
        </span>
      </.link>
    </div>
    """
  end

  attr :active_slug, :string, default: nil
  attr :sort, :string, required: true

  defp sort_links(assigns) do
    assigns = assign(assigns, :current_label, sort_label(assigns.sort))

    ~H"""
    <.menu
      id="discussions-sort"
      align="end"
      class="text-foreground-primary inline-flex h-[34px] cursor-pointer items-center gap-1.5 rounded-full border border-white/7 bg-white/4 px-3.5 text-[13px] font-medium transition-colors duration-150 outline-none hover:border-white/12 hover:bg-white/7 focus:outline-none focus-visible:outline-none"
    >
      <:trigger aria-label="Sort discussions">
        <Lucide.arrow_down_wide_narrow class="text-foreground-tertiary size-4" aria-hidden />
        <span>{@current_label}</span>
        <Lucide.chevron_down
          class="text-foreground-tertiary size-3.5 transition-transform duration-150 data-[state=open]:rotate-180"
          aria-hidden
        />
      </:trigger>
      <div class="bg-surface-base border-border-divider text-foreground-primary w-[184px] rounded-[12px] border p-1 shadow-xl outline-none">
        <.link
          :for={option <- sort_options()}
          patch={sort_href(@active_slug, option.url)}
          rel="nofollow"
          data-menu-dismiss
          class={[
            "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-[13px] transition outline-none focus:outline-none",
            @sort == option.url && "text-foreground-primary bg-white/5 font-medium",
            @sort != option.url &&
              "hover:text-foreground-primary text-foreground-secondary hover:bg-white/4"
          ]}
        >
          <span class="flex-1">{option.label}</span>
          <Lucide.check
            :if={@sort == option.url}
            class="text-foreground-primary size-4 shrink-0"
            aria-hidden
          />
        </.link>
      </div>
    </.menu>
    """
  end

  defp sort_label(sort) do
    Enum.find_value(sort_options(), "Recent Activity", fn
      %{url: ^sort, label: label} -> label
      _option -> false
    end)
  end

  attr :posts, :list, required: true

  defp post_list(assigns) do
    ~H"""
    <p :if={@posts == []} class="text-foreground-tertiary text-style-body2Regular py-16 text-center">
      No discussions yet.
    </p>

    <div :if={@posts != []} class="flex flex-col">
      <.post_list_item
        :for={{post, index} <- Enum.with_index(@posts)}
        post={post}
        index={index}
      />
    </div>
    """
  end

  attr :post, :map, required: true
  attr :index, :integer, default: 0
  attr :compact, :boolean, default: false

  defp post_list_item(assigns) do
    assigns = assign(assigns, :live?, recently_active?(assigns.post))

    ~H"""
    <article
      class="group kaguya-thread-enter relative border-t border-white/6 py-4 transition-colors first:border-t-0 lg:-mx-3 lg:px-3 lg:py-5 lg:hover:bg-white/2"
      style={"animation-delay: #{rem(@index, 12) * 35}ms"}
    >
      <.link
        navigate={@post.url}
        class="absolute inset-0 z-1 rounded-lg"
        tabindex="-1"
        aria-hidden="true"
      >
      </.link>

      <div class="flex gap-3.5 lg:gap-4">
        <div class="relative z-10 mt-0.5 shrink-0">
          <.user_avatar
            user={@post.user}
            class="size-8 lg:size-9"
            sizes="(max-width: 1023px) 32px, 36px"
          />
        </div>

        <div class="min-w-0 flex-1">
          <%!-- Title — the star, first --%>
          <div class="flex items-start gap-1.5">
            <Lucide.pin
              :if={@post.is_pinned}
              class="text-foreground-quaternary mt-[7px] size-3 shrink-0"
              aria-hidden
            />
            <Lucide.lock
              :if={@post.is_locked && @post.is_removed}
              class="text-foreground-quaternary mt-[7px] size-3 shrink-0"
              aria-hidden
            />
            <h3 class="line-clamp-2 text-[20px] leading-[1.3] font-medium tracking-[-0.02em] text-[#EBF7FD] transition-colors group-hover:text-white">
              {@post.title}
            </h3>
          </div>

          <%!-- Author + what it's about --%>
          <div class="text-foreground-tertiary mt-1 flex min-w-0 items-center gap-1.5 text-[13px]">
            <span :if={@post.user} class="inline-flex min-w-0 items-center gap-1">
              <span class="text-foreground-quaternary">started by</span>
              <.link
                navigate={"/@#{@post.user.username}"}
                class="hover:text-foreground-primary text-foreground-tertiary relative z-10 truncate font-medium transition-colors"
              >
                {@post.user.display_name}
              </.link>
            </span>
            <.link
              :if={@post.entity_tag}
              navigate={@post.entity_tag.href}
              class="hover:text-foreground-secondary text-foreground-tertiary relative z-10 inline-flex max-w-[200px] shrink-0 truncate rounded bg-white/5 px-1.5 py-0.5 font-medium transition-colors hover:bg-white/9"
            >
              {@post.entity_tag.label}
            </.link>
          </div>

          <p
            :if={!@compact && @post.content_preview}
            class="text-foreground-secondary mt-1.5 line-clamp-2 text-[15px] leading-normal"
          >
            {@post.content_preview}
          </p>

          <%!-- Object footer: the activity — who's here, how much, how recent --%>
          <div class="text-foreground-tertiary mt-2.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-[13px] tabular-nums">
            <div :if={@post.recent_comment_users != []} class="relative z-10 mr-0.5 flex -space-x-1.5">
              <.link
                :for={{user, i} <- Enum.with_index(Enum.take(@post.recent_comment_users, 3))}
                navigate={"/@#{user.username}"}
                class="relative z-10 transition-transform hover:-translate-y-0.5"
                style={"z-index: #{3 - i}"}
                aria-label={user.display_name}
              >
                <.avatar_image user={user} class="ring-surface-base size-5 ring-2" sizes="20px" />
              </.link>
            </div>

            <span :if={@post.comments_count > 0}>
              {format_short_count(@post.comments_count)} {if @post.comments_count == 1,
                do: "reply",
                else: "replies"}
            </span>

            <span :if={@post.likes_count > 0} class="text-foreground-quaternary">·</span>
            <span :if={@post.likes_count > 0}>
              {format_short_count(@post.likes_count)} {if @post.likes_count == 1,
                do: "like",
                else: "likes"}
            </span>

            <span class="text-foreground-quaternary">·</span>
            <span class="inline-flex items-center gap-1.5">
              <span
                :if={@live?}
                class="size-1.5 rounded-full bg-[#34D399]"
                title="Active recently"
                aria-hidden
              >
              </span>
              <time
                datetime={datetime_attr(@post.activity_at)}
                title={datetime_title(@post.activity_at)}
                class={["relative z-10", @live? && "text-foreground-secondary font-medium"]}
              >
                {@post.activity_from_now}
              </time>
            </span>
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :user, :map, required: true
  attr :class, :any, default: nil
  attr :sizes, :string, required: true

  defp user_avatar(%{user: nil} = assigns) do
    ~H"""
    <span class={["bg-surface-elevated block rounded-full", @class]}></span>
    """
  end

  defp user_avatar(assigns) do
    ~H"""
    <.link navigate={"/@#{@user.username}"}>
      <.avatar_image user={@user} class={@class} sizes={@sizes} />
    </.link>
    """
  end

  attr :user, :map, required: true
  attr :class, :any, default: nil
  attr :sizes, :string, required: true

  defp avatar_image(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
      user={@user}
      size={@class}
      sizes={@sizes}
      fallback={:empty}
    />
    """
  end

  # A thread is "live" if its last activity was within the past 48 hours — drives
  # the small presence dot and the warmer timestamp in the activity rail.
  defp recently_active?(%{activity_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at, :hour) <= 48

  defp recently_active?(%{activity_at: %NaiveDateTime{} = at}),
    do: NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :hour) <= 48

  defp recently_active?(_), do: false

  defp format_short_count(value) when value >= 1_000_000,
    do: "#{Float.round(value / 1_000_000, 1)}m"

  defp format_short_count(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 1)}k"
  defp format_short_count(value), do: to_string(value)

  defp datetime_attr(nil), do: nil
  defp datetime_attr(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp datetime_attr(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp datetime_title(value),
    do: KaguyaWeb.SharedComponents.Time.format_datetime_tooltip(value)

  defp can_post_in_active_category?(_categories, nil, _can_moderate_discussions), do: true

  defp can_post_in_active_category?(categories, active_slug, can_moderate_discussions) do
    case Enum.find(categories, &(&1.slug == active_slug)) do
      %{admin_only: true} -> can_moderate_discussions
      _category -> true
    end
  end

  defp sort_options do
    [
      %{label: "Recent Activity", url: "recent"},
      %{label: "Newest", url: "newest"},
      %{label: "Most Liked", url: "most-liked"}
    ]
  end

  defp sort_href(nil, "recent"), do: "/discussions"
  defp sort_href(nil, sort), do: "/discussions?sort=#{sort}"
  defp sort_href(%{slug: slug}, sort), do: sort_href(slug, sort)
  defp sort_href(category_slug, "recent"), do: "/discussions/#{category_slug}"
  defp sort_href(category_slug, sort), do: "/discussions/#{category_slug}?sort=#{sort}"

  attr :category_type, :any, required: true
  attr :class, :any, default: nil

  defp category_icon(%{category_type: type} = assigns)
       when type in [:visual_novel, "visual_novel"] do
    ~H"""
    <Lucide.book_open class={@class} aria-hidden />
    """
  end

  defp category_icon(%{category_type: type} = assigns) when type in [:producer, "producer"] do
    ~H"""
    <Lucide.building_2 class={@class} aria-hidden />
    """
  end

  defp category_icon(%{category_type: type} = assigns) when type in [:character, "character"] do
    ~H"""
    <Lucide.user class={@class} aria-hidden />
    """
  end

  defp category_icon(%{category_type: type} = assigns) when type in [:user, "user"] do
    ~H"""
    <Lucide.at_sign class={@class} aria-hidden />
    """
  end

  defp category_icon(assigns) do
    ~H"""
    <Lucide.message_square class={@class} aria-hidden />
    """
  end

  defp target_cover_needs_blur?(target) when is_map(target) do
    Map.get(target, :is_image_nsfw) == true or
      Map.get(target, "is_image_nsfw") == true or
      Map.get(target, :is_image_suggestive) == true or
      Map.get(target, "is_image_suggestive") == true
  end

  defp target_cover_needs_blur?(_), do: false
end

defmodule KaguyaWeb.DeveloperLive.Show do
  use KaguyaWeb, :live_view
  import KaguyaWeb.UI.Menu, only: [menu: 1]

  alias Kaguya.Producers
  alias Kaguya.Social
  alias Kaguya.Sync.VndbStorefrontMapper
  alias KaguyaWeb.AuthPromptComponents
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.Components.Shared.SocialIcons
  alias KaguyaWeb.DeveloperLive.Data
  alias KaguyaWeb.SEO
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       slug: nil,
       page_title: "Developer",
       producer: nil,
       visual_novels: [],
       pagination: %{page: 1, page_size: Data.works_page_size(), total_pages: 1, total_count: 0},
       discussions: [],
       page: 1,
       loading: true,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    case Data.load_show_page(slug, params, socket.assigns.current_user) do
      {:ok, page} ->
        first_vn_title = first_visual_novel_title(page.visual_novels)

        {:noreply,
         socket
         |> assign(
           SEO.developer(page.producer,
             total_count: page.pagination.total_count,
             first_vn_title: first_vn_title
           )
         )
         |> assign(
           slug: page.slug,
           producer: page.producer,
           visual_novels: page.visual_novels,
           pagination: page.pagination,
           discussions: page.discussions,
           page: page.page,
           loading: false
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(SEO.developer_not_found())
         |> assign(
           slug: slug,
           not_found?: true,
           loading: false
         )}
    end
  end

  defp first_visual_novel_title([]), do: nil

  defp first_visual_novel_title([%{visual_novel: %{title: title}} | _]) when is_binary(title),
    do: title

  defp first_visual_novel_title(_), do: nil

  @impl true
  def handle_event("toggle_follow", _params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         %{id: producer_id, is_followed_by_me: followed?} = producer <- socket.assigns.producer do
      optimistic_producer =
        producer
        |> Map.put(:is_followed_by_me, !followed?)
        |> Map.put(
          :follower_count,
          (producer.follower_count || 0) + if(followed?, do: -1, else: 1)
        )

      socket = assign(socket, :producer, optimistic_producer)

      case if(followed?,
             do: Social.unfollow_producer(user_id, producer_id),
             else: Social.follow_producer(user_id, producer_id)
           ) do
        {:ok, %{follower_count: follower_count}} ->
          {:noreply,
           assign(
             socket,
             :producer,
             Map.put(optimistic_producer, :follower_count, follower_count)
           )}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:producer, producer)
           |> put_flash(:error, "Could not update follow state.")}
      end
    else
      _ -> {:noreply, push_navigate(socket, to: "/login")}
    end
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="lg:bg-surface-base pt-8 pb-[110px] sm:pb-32 md:pt-10 md:pb-20 dark:lg:bg-transparent">
      <div class="flex flex-col md:px-8 lg:mx-auto lg:max-w-[810px] lg:px-0">
        <div
          :if={Data.can_moderate_db?(@current_user) && @producer.hidden_at}
          class="mx-4 mb-4 rounded-lg border border-red-500/20 bg-red-500/10 px-4 py-2.5 text-sm text-red-400 md:mx-0"
        >
          This entry is hidden from public view.
        </div>

        <div class="flex flex-col gap-4">
          <div class="relative flex h-fit flex-col items-center gap-4 rounded-[12px] pb-0 md:flex-row md:items-start md:gap-5">
            <div
              :if={producer_image_url(@producer)}
              class="w-[112px] shrink-0 sm:w-[132px] md:w-[120px] lg:w-[136px]"
            >
              <img
                src={producer_image_url(@producer)}
                alt={@producer.name}
                class="aspect-square w-full rounded-[8px] border border-white/8 object-cover"
              />
            </div>

            <div class="flex min-w-0 flex-1 flex-col items-center gap-2 md:items-start">
              <div class="flex w-full flex-col items-center gap-2 lg:flex-row lg:items-start lg:justify-between lg:gap-3">
                <div class="flex min-w-0 flex-1 flex-col items-center gap-1 text-center md:items-start md:text-left">
                  <h1 class="text-[22px] leading-[27px] font-normal text-[rgb(var(--foreground-primary))] sm:text-[30px]/10 md:text-[28px]/9 md:font-semibold">
                    {@producer.name}
                  </h1>
                  <.producer_meta producer={@producer} />
                </div>

                <div class="flex flex-wrap items-center justify-center gap-1.5 lg:shrink-0 lg:justify-end">
                  <.follow_button producer={@producer} is_logged_in={!is_nil(@current_user)} />
                  <span
                    :if={@producer.is_locked}
                    class="hidden h-[25px] items-center justify-center gap-1 rounded-[4px] border border-amber-500/20 bg-amber-500/15 px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-amber-400 lg:flex"
                  >
                    Locked
                  </span>
                  <.developer_actions producer={@producer} current_user={@current_user} />
                </div>
              </div>

              <div class="md:text-style-body2Regular mt-2 px-4 text-sm leading-[22px] text-[rgb(var(--foreground-secondary))] md:px-0">
                <KaguyaWeb.SharedComponents.Markdown.markdown
                  :if={@producer.description}
                  content={@producer.description}
                  variant="plain"
                  class="[&_a]:text-[rgb(var(--text-link-default))] [&_a:hover]:text-[rgb(var(--text-link-hover))] [&_p]:my-2"
                  read_more
                  read_more_id={"producer-desc-#{@producer.slug}"}
                  read_more_lines={12}
                  read_more_mobile_limit={330}
                  read_more_desktop_limit={794}
                />
              </div>
            </div>
          </div>

          <div
            :if={external_links(@producer) != []}
            class="mt-2 px-4 md:px-0"
          >
            <.producer_social_links links={external_links(@producer)} />
          </div>
        </div>

        <section class="mt-6 px-4 md:px-0" id="vns">
          <div class="h-px bg-[rgb(var(--border-divider))]"></div>
          <div class="mt-5 flex scroll-mt-24 items-center gap-2">
            <h2 class="text-base font-medium text-[rgb(var(--foreground-primary))]">
              Works
            </h2>
            <span
              :if={@pagination.total_count > 0}
              class="text-sm text-[rgb(var(--foreground-secondary))]"
            >
              {format_count(@pagination.total_count)}
            </span>
          </div>

          <div
            :if={@visual_novels == []}
            class="flex items-center justify-center py-12 text-[rgb(var(--foreground-secondary))]"
          >
            No visual novels listed for this developer.
          </div>

          <div
            :if={@visual_novels != []}
            class="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-4 sm:gap-2 md:mt-4 md:grid-cols-5"
          >
            <.producer_work_card
              :for={work <- @visual_novels}
              vn={work.visual_novel}
              role={work.role}
              rating={work.visual_novel.average_rating}
              rating_count={work.visual_novel.ratings_count}
            />
          </div>

          <div :if={@pagination.total_pages > 1} class="mt-4">
            <.pagination_nav page={@page} total_pages={@pagination.total_pages} slug={@producer.slug} />
          </div>
        </section>

        <.discussions_section discussions={@discussions} />
      </div>
    </div>

    <AuthPromptComponents.auth_prompt_modal
      id="developer-auth-prompt"
      message={@auth_prompt_message}
      return_to={@current_path}
    />
    """
  end

  attr :producer, :map, required: true
  attr :is_logged_in, :boolean, required: true
  attr :class, :string, default: nil

  defp follow_button(assigns) do
    ~H"""
    <AuthPromptComponents.auth_button
      event="toggle_follow"
      is_logged_in={@is_logged_in}
      modal_id="developer-auth-prompt"
      auth_message="Sign in to follow this developer"
      aria-pressed={if @producer.is_followed_by_me, do: "true", else: "false"}
      class={[
        "group flex h-[26px] w-fit min-w-[78px] items-center justify-center rounded-[4px] px-3 text-xs font-medium transition-colors duration-200",
        @producer.is_followed_by_me &&
          "bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-primary))] hover:bg-white/6",
        !@producer.is_followed_by_me &&
          "bg-[rgb(var(--button-background-neutral-inverse-default))] text-[rgb(var(--surface-base))]",
        @class
      ]}
    >
      <%= if @producer.is_followed_by_me do %>
        <span class="lg:hidden">Following</span>
        <span class="hidden group-hover:hidden lg:inline">Following</span>
        <span class="hidden group-hover:inline">Unfollow</span>
      <% else %>
        Follow
      <% end %>
    </AuthPromptComponents.auth_button>
    """
  end

  attr :producer, :map, required: true

  defp producer_meta(assigns) do
    ~H"""
    <div
      :if={@producer.producer_type || (@producer.follower_count || 0) > 0}
      class="flex items-center gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]"
    >
      <span :if={@producer.producer_type} class="capitalize">
        {if @producer.producer_type == "amateur",
          do: "Indie",
          else: String.replace(@producer.producer_type, "_", " ") |> String.capitalize()}
      </span>
      <span
        :if={@producer.producer_type && (@producer.follower_count || 0) > 0}
        aria-hidden="true"
      >
        ·
      </span>
      <.link
        :if={(@producer.follower_count || 0) > 0}
        navigate={"/developer/#{@producer.slug}/followers"}
        class="text-[rgb(var(--foreground-secondary))] tabular-nums transition-colors hover:text-[rgb(var(--foreground-primary))]"
      >
        {format_short_count(@producer.follower_count)} {if @producer.follower_count == 1,
          do: "follower",
          else: "followers"}
      </.link>
    </div>
    """
  end

  attr :links, :list, required: true

  defp producer_social_links(assigns) do
    links = normalize_social_links(assigns.links)
    icon_links = Enum.filter(links, &social_icon?/1)
    overflow_links = Enum.reject(links, &social_icon?/1)

    assigns = assign(assigns, :icon_links, icon_links)
    assigns = assign(assigns, :overflow_links, overflow_links)

    ~H"""
    <div class="flex flex-wrap items-center gap-1">
      <a
        :for={link <- @icon_links}
        href={link.url}
        target="_blank"
        rel="noopener noreferrer"
        class="flex h-8 items-center gap-1.5 rounded-md px-2.5 text-xs text-[rgb(var(--foreground-tertiary))] transition hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
      >
        <SocialIcons.icon site={link.site} class="size-[15px] shrink-0" />
        {social_link_label(link)}
      </a>

      <.menu
        :if={@overflow_links != []}
        id="producer-external-links-overflow"
        align="start"
        class="hover:text-foreground-primary text-foreground-tertiary flex h-8 cursor-pointer items-center justify-center rounded-md px-2.5 text-xs transition hover:bg-white/6"
      >
        <:trigger>
          +{length(@overflow_links)} more
        </:trigger>
        <div class="bg-surface-menu-item-default w-auto min-w-[160px] rounded-[12px] border-none p-1 shadow-[0_4px_24px_rgba(0,0,0,0.5)]">
          <div class="flex flex-col py-0.5">
            <a
              :for={link <- @overflow_links}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              class="hover:bg-surface-menu-item-hover hover:text-foreground-primary text-foreground-secondary flex items-center gap-2 rounded-md px-2.5 py-1.5 text-xs transition"
            >
              <Lucide.external_link class="size-3 shrink-0" />
              {social_link_label(link)}
            </a>
          </div>
        </div>
      </.menu>
    </div>
    """
  end

  attr :producer, :map, required: true
  attr :current_user, :any, default: nil

  defp developer_actions(assigns) do
    ~H"""
    <%= if @producer.can_edit do %>
      <.link
        :if={!@producer.is_locked}
        navigate={"/developer/#{@producer.slug}/edit"}
        class={action_chip_class()}
      >
        <Lucide.pencil class="size-2.5" aria-hidden /> Edit
      </.link>
      <span
        :if={@producer.is_locked}
        title="Entry is locked for editing"
        class="flex h-[25px] cursor-not-allowed items-center justify-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-quaternary))] opacity-50"
      >
        <Lucide.pencil class="size-2.5" aria-hidden /> Edit
      </span>
    <% end %>

    <.link navigate={"/developer/#{@producer.slug}/history"} class={action_chip_class()}>
      <Lucide.history class="size-2.5" aria-hidden /> History
    </.link>
    """
  end

  attr :vn, :map, required: true
  attr :role, :string, default: nil
  attr :rating, :float, default: nil
  attr :rating_count, :integer, default: 0

  defp producer_work_card(assigns) do
    ~H"""
    <.link :if={@vn && @vn.slug} navigate={"/vn/#{@vn.slug}"} class="group flex flex-col gap-1">
      <KaguyaWeb.SharedComponents.Cover.cover
        vn={@vn}
        sizes="(min-width: 1024px) 160px, 25vw"
        enable_nsfw_reveal
        class="aspect-2/3 w-full rounded-[4px]"
        fallback_class="rounded-[4px] text-[10px]"
      />
      <div :if={show_rating?(@rating, @rating_count)} class="mt-1 flex items-center gap-1 text-[11px]">
        <span class="text-[rgb(var(--foreground-secondary))]">{format_rating(@rating)}</span>
        <span class="text-[rgb(var(--foreground-tertiary))]">({short_count(@rating_count)})</span>
      </div>
    </.link>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :slug, :string, required: true

  defp pagination_nav(assigns) do
    ~H"""
    <nav class="border-border-divider relative mx-5 flex items-center justify-center gap-3 border-t py-5 text-sm">
      <.link
        :if={@page > 1}
        patch={"/developer/#{@slug}?page=#{@page - 1}"}
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Previous
      </.link>

      <span class="text-[rgb(var(--foreground-secondary))]">Page {@page} of {@total_pages}</span>

      <.link
        :if={@page < @total_pages}
        patch={"/developer/#{@slug}?page=#{@page + 1}"}
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Next
      </.link>
    </nav>
    """
  end

  attr :discussions, :list, required: true

  defp discussions_section(assigns) do
    ~H"""
    <section :if={@discussions != []} class="mt-6 px-4 md:px-0">
      <div class="h-px bg-[rgb(var(--border-divider))]"></div>
      <h2 class="mt-5 text-base font-medium text-[rgb(var(--foreground-primary))]">Discussions</h2>
      <div class="mt-3 flex flex-col">
        <.link
          :for={post <- @discussions}
          id={"developer-discussion-#{post.id}"}
          navigate={post.url}
          class="flex items-start gap-3 border-b border-[rgb(var(--border-divider))] py-3 last:border-b-0"
        >
          <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
            user={post.user || %{}}
            size="size-9"
            sizes="36px"
            class="mt-0.5"
            fallback={:empty}
          />
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-2 text-sm text-[rgb(var(--foreground-secondary))]">
              <span class="line-clamp-1 font-medium text-[rgb(var(--foreground-primary))]">
                {post.title}
              </span>
              <span
                :if={post.is_pinned}
                class="rounded-[3px] border border-[rgb(var(--chip-border-default))] px-1.5 py-0.5 text-[10px] tracking-wider text-[rgb(var(--foreground-tertiary))] uppercase"
              >
                Pinned
              </span>
              <span
                :if={post.is_locked}
                class="rounded-[3px] border border-amber-500/20 px-1.5 py-0.5 text-[10px] tracking-wider text-amber-300 uppercase"
              >
                Locked
              </span>
            </div>
            <p class="mt-1 text-xs text-[rgb(var(--foreground-tertiary))]">
              by {(post.user && post.user.display_name) || "Unknown"} · {SharedTime.calendar_custom(
                post.inserted_at
              )} · {format_count(post.comments_count, "comment")}
            </p>
          </div>
        </.link>
      </div>
    </section>
    """
  end

  defp producer_image_url(producer) do
    Producers.build_image_urls(producer)
    |> Map.get(:large)
  end

  defp show_rating?(rating, count) when is_number(rating) and is_integer(count), do: count >= 10
  defp show_rating?(_, _), do: false

  defp format_rating(rating) when is_float(rating),
    do: :erlang.float_to_binary(rating, decimals: 1)

  defp format_rating(rating) when is_integer(rating), do: "#{rating}.0"
  defp format_rating(_), do: nil

  defp short_count(count) when is_integer(count) and count >= 1_000,
    do: "#{Float.round(count / 1_000, 1)}K"

  defp short_count(count) when is_integer(count), do: Integer.to_string(count)
  defp short_count(_), do: "0"

  defp format_count(count) when is_integer(count) and count >= 1_000_000,
    do: "#{Float.round(count / 1_000_000, 1)}M"

  defp format_count(count) when is_integer(count) and count >= 1_000,
    do: "#{Float.round(count / 1_000, 1)}K"

  defp format_count(count) when is_integer(count), do: Integer.to_string(count)
  defp format_count(_), do: "0"

  defp external_links(producer) when is_map(producer) do
    vndb_links =
      case vndb_url(producer) do
        nil -> []
        url -> [%{label: "VNDB", url: url, site: "vndb"}]
      end

    ext_links =
      producer
      |> Map.get(:external_links, [])
      |> Enum.map(fn
        %{site: site, value: value} when is_binary(site) and is_binary(value) and value != "" ->
          label = VndbStorefrontMapper.label(site)
          url = VndbStorefrontMapper.build_url(site, value)

          if is_binary(url) and label do
            %{label: label, url: url, site: site}
          end

        _ ->
          nil
      end)
      |> Enum.filter(&(&1 != nil))

    (vndb_links ++ ext_links)
    |> Enum.uniq_by(&{&1.site, &1.url})
  end

  defp external_links(_), do: []

  defp vndb_url(%{vndb_id: vndb_id}) when is_binary(vndb_id) and vndb_id != "" do
    normalized = String.trim_leading(vndb_id, "p")

    if normalized == "" do
      nil
    else
      "https://vndb.org/p#{normalized}"
    end
  end

  defp vndb_url(_), do: nil

  defp social_icon?(%{site: site}), do: social_icon?(site)
  defp social_icon?(site), do: SocialIcons.glyph?(site)

  defp social_link_label(%{label: label}) when is_binary(label) and label != "", do: label

  defp social_link_label(%{site: site}) when is_binary(site) and site != "",
    do: normalize_social_link_label(site)

  defp social_link_label(_), do: "Link"

  @site_label_overrides %{
    "vndb" => "VNDB",
    "gog" => "GOG",
    "appstore" => "App Store",
    "googplay" => "Google Play"
  }

  defp normalize_social_link_label(site) when is_binary(site) do
    Map.get(@site_label_overrides, site) ||
      site
      |> String.replace("_", " ")
      |> String.split(" ")
      |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp normalize_social_links(links) when is_list(links) do
    links
    |> Enum.map(fn
      %{site: site, url: url} when is_binary(site) and is_binary(url) and url != "" ->
        %{site: String.downcase(site), url: url, label: social_link_label(%{site: site})}

      %{site: site, value: url} when is_binary(site) and is_binary(url) and url != "" ->
        %{site: String.downcase(site), url: url, label: social_link_label(%{site: site})}

      %{"site" => site, "url" => url} when is_binary(site) and is_binary(url) and url != "" ->
        %{site: String.downcase(site), url: url, label: social_link_label(%{site: site})}

      %{"site" => site, "value" => url} when is_binary(site) and is_binary(url) and url != "" ->
        %{site: String.downcase(site), url: url, label: social_link_label(%{site: site})}

      _ ->
        nil
    end)
    |> Enum.filter(&is_map/1)
    |> Enum.reject(&is_nil(&1.url))
    |> Enum.uniq_by(&{&1.site, &1.url})
  end

  defp normalize_social_links(_), do: []

  defp format_short_count(count) when is_integer(count) and count >= 1_000_000,
    do: "#{Float.round(count / 1_000_000, 1)}M"

  defp format_short_count(count) when is_integer(count) and count >= 1_000,
    do: "#{Float.round(count / 1_000, 1)}K"

  defp format_short_count(count) when is_integer(count), do: Integer.to_string(count)
  defp format_short_count(_), do: "0"

  defp action_chip_class do
    "flex h-[25px] items-center justify-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition-colors duration-200 hover:border-[rgb(var(--chip-border-hover))]"
  end

  defp format_count(count, singular) do
    "#{format_count(count)} #{if count == 1, do: singular, else: singular <> "s"}"
  end
end

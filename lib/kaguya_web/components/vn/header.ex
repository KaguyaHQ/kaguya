defmodule KaguyaWeb.VN.Header do
  @moduledoc """
  Title block above the fold — desktop and mobile variants — plus the
  tabs strip and per-tab panels (Tags / Covers / Screens / Releases /
  Quotes) anchored to it.

  Tabs dispatch `switch_tab` to the LiveView; the panel reads `@tabs[tab]`
  using the four-state convention from
  `KaguyaWeb.VNLive.Show`: `:not_loaded | :loading | {:ok, data} | {:error, _}`.

  The mobile header also renders the shared `viewer_controls_card/1` so
  signed-in users get the same status/rating affordances inline.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.VN.Panels

  import KaguyaWeb.Components.Shared.RatingsChart, only: [ratings_chart: 1]
  import KaguyaWeb.VN.Formatters
  import KaguyaWeb.VN.PanelHelpers
  import KaguyaWeb.VN.Sidebar, only: [mobile_action_trigger: 1]

  @min_ratings_to_display 3

  # ---------------------------------------------------------------------------
  # Desktop header
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :active_tab, :atom, required: true
  attr :tabs, :map, required: true
  attr :release_filters, :map, default: %{language: nil, platform: nil}
  attr :release_filter_options, :map, default: %{languages: [], platforms: []}
  attr :expanded_tag_kinds, :list, default: []
  attr :current_user, :map, default: nil
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  def vn_desktop_header(assigns) do
    ~H"""
    <section class="hidden px-5 pb-5 lg:block lg:px-8 lg:pb-6">
      <p
        :if={vn_hidden?(@vn)}
        class="mb-3 rounded-md border border-red-500/30 bg-red-500/15 px-3 py-1.5 text-xs font-medium text-red-400"
      >
        This entry is hidden from public view.
      </p>
      <div class="flex w-full items-start justify-between gap-4">
        <h1 class="max-w-[760px] min-w-0">
          <span
            class="text-[32px] leading-[32px] font-semibold tracking-[-0.01em] text-[rgb(var(--foreground-primary))]"
            style="font-family: var(--font-source-serif)"
          >
            {@vn.title}
          </span>
          <span
            :if={year(@vn.release_date)}
            class="ml-3 align-baseline text-[20px] font-light text-[rgb(var(--foreground-tertiary))]"
          >
            {year(@vn.release_date)}
          </span>
        </h1>
        <.meta_pills vn={@vn} user_can_edit={@user_can_edit} />
      </div>

      <.producer_links
        producers={@vn.producers}
        class="mt-1.5 text-[16px]/6 font-normal text-[rgb(var(--foreground-secondary))]"
      />

      <.rating_summary vn={@vn} />

      <.description_read_more
        id={"vn-desc-desktop-#{@vn.slug}"}
        description={@vn.description}
        limit={794}
        class="text-style-body1Regular mt-3 text-[rgb(var(--foreground-secondary))] [&_a]:text-[rgb(var(--text-link-default))] [&_a:hover]:text-[rgb(var(--text-link-hover))] [&_blockquote]:my-0 [&_li]:my-0 [&_ol]:my-0 [&_p]:my-2 [&_ul]:my-0"
      />

      <.vn_tabs active_tab={@active_tab} user_can_edit={@user_can_edit} />
      <.vn_tab_panel
        vn={@vn}
        active_tab={@active_tab}
        tabs={@tabs}
        release_filters={@release_filters}
        release_filter_options={@release_filter_options}
        expanded_tag_kinds={@expanded_tag_kinds}
        id_prefix="desktop"
        current_user={@current_user}
        is_logged_in={@is_logged_in}
        user_can_edit={@user_can_edit}
      />
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Mobile header
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :active_tab, :atom, required: true
  attr :tabs, :map, required: true
  attr :viewer, :map, default: nil
  attr :viewer_vn, :map, default: nil
  attr :auth, :map, default: nil
  attr :current_path, :string, required: true
  attr :release_filters, :map, default: %{language: nil, platform: nil}
  attr :release_filter_options, :map, default: %{languages: [], platforms: []}
  attr :expanded_tag_kinds, :list, default: []
  attr :current_user, :map, default: nil
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  def vn_mobile_header(assigns) do
    ~H"""
    <section class="relative -mt-10 px-4 lg:hidden">
      <p
        :if={vn_hidden?(@vn)}
        class="mb-3 rounded-md border border-red-500/30 bg-red-500/15 px-3 py-1.5 text-xs font-medium text-red-400"
      >
        This entry is hidden from public view.
      </p>
      <div class="flex items-end gap-4">
        <div class="min-w-0 flex-1 pb-1">
          <h1
            class="text-[24px] leading-tight font-semibold tracking-[-0.01em] text-[rgb(var(--foreground-primary))]"
            style="font-family: var(--font-source-serif)"
          >
            {@vn.title}
          </h1>
          <.producer_links
            producers={@vn.producers}
            class="mt-2 text-[13px] leading-none text-[rgb(var(--foreground-secondary))]"
          />
          <div class="mt-2 flex items-baseline gap-1.5 text-sm text-[rgb(var(--foreground-tertiary))]">
            <%= if show_ratings?(@vn) do %>
              <span class="text-[14px] leading-none text-[rgb(var(--icons-global-star))]">★</span>
              <span class="text-[15px] font-medium text-[rgb(var(--foreground-primary))] tabular-nums">
                {format_rating(@vn.average_rating)}
              </span>
              <span class="text-[rgb(var(--foreground-tertiary))]">·</span>
            <% end %>
            <span :if={year(@vn.release_date)}>{year(@vn.release_date)}</span>
          </div>
        </div>

        <div class="relative w-[105px] shrink-0 sm:w-[140px]">
          <KaguyaWeb.SharedComponents.Cover.cover
            vn={@vn}
            sizes="(min-width: 640px) 140px, 105px"
            shadow
            enable_nsfw_reveal
            class="aspect-2/3 w-[105px] rounded-[4px] sm:w-[140px]"
          />
        </div>
      </div>

      <.description_read_more
        id={"vn-desc-mobile-#{@vn.slug}"}
        description={@vn.description}
        limit={330}
        class="mt-6 text-[14px] leading-[22px] text-[rgb(var(--foreground-secondary))] [&_a]:text-[rgb(var(--text-link-default))] [&_blockquote]:my-0 [&_li]:my-0 [&_ol]:my-0 [&_p]:my-2 [&_ul]:my-0"
      />

      <.mobile_action_trigger
        viewer={@viewer}
        viewer_vn={@viewer_vn}
        auth={@auth}
        class="mt-6"
      />

      <.vn_tabs active_tab={@active_tab} user_can_edit={@user_can_edit} mobile />
      <.vn_tab_panel
        vn={@vn}
        active_tab={@active_tab}
        tabs={@tabs}
        release_filters={@release_filters}
        release_filter_options={@release_filter_options}
        expanded_tag_kinds={@expanded_tag_kinds}
        id_prefix="mobile"
        current_user={@current_user}
        is_logged_in={@is_logged_in}
        user_can_edit={@user_can_edit}
        mobile
      />
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Title-row sub-pieces (broken out so the header reads as a sequence of
  # readable pieces, not a 100-line template).
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true
  attr :user_can_edit, :boolean, default: false

  def meta_pills(assigns) do
    ~H"""
    <div class="mt-1 flex shrink-0 items-center gap-2.5 text-[10px] tracking-[0.06em]">
      <span
        :if={@vn.is_locked}
        class="flex items-center gap-1 rounded-[4px] border border-amber-500/20 bg-amber-500/15 px-2 py-[3px] text-amber-400"
      >
        <Lucide.lock class="size-3" aria-hidden /> Locked
      </span>
      <%= if label = length_label(@vn) do %>
        <span class="text-[12px] font-normal text-[rgb(var(--foreground-tertiary))]">{label}</span>
        <span class="text-[rgb(var(--foreground-tertiary))]/30">|</span>
      <% end %>
      <%= if @user_can_edit do %>
        <%= if @vn.is_locked do %>
          <span
            class="flex h-[25px] cursor-not-allowed items-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 text-[10px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-quaternary))] opacity-50"
            title="Entry is locked for editing"
          >
            <Lucide.pencil class="size-3" aria-hidden /> Edit
          </span>
        <% else %>
          <.link
            navigate={"/vn/#{@vn.slug}/edit"}
            class="flex h-[25px] items-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 text-[10px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
          >
            <Lucide.pencil class="size-3" aria-hidden /> Edit
          </.link>
        <% end %>
      <% end %>
      <.link
        navigate={"/vn/#{@vn.slug}/history"}
        class="flex h-[25px] items-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 text-[10px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
      >
        <Lucide.history class="size-3" aria-hidden /> History
      </.link>
      <.link
        :if={@vn.vndb_url}
        href={@vn.vndb_url}
        target="_blank"
        rel="noopener noreferrer"
        class="flex h-[25px] items-center rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 text-[10px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition hover:border-[rgb(var(--chip-border-hover))]"
      >
        VNDB
      </.link>
      <button
        type="button"
        data-share-button
        aria-label="Share visual novel"
        title="Share visual novel"
        class="flex h-[25px] items-center rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 text-[10px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
      >
        <Lucide.link_2 class="size-3.5" aria-hidden />
      </button>
    </div>
    """
  end

  attr :vn, :map, required: true

  def rating_summary(assigns) do
    ~H"""
    <div :if={show_ratings?(@vn)} class="mt-3 flex items-baseline gap-1.5">
      <span class="text-[16px] leading-none text-[rgb(var(--icons-global-star))]">★</span>
      <span class="text-[20px] leading-none font-normal text-[rgb(var(--foreground-primary))] tabular-nums">
        {format_rating(@vn.average_rating)}
      </span>
      <span class="text-[13px] text-[rgb(var(--foreground-tertiary))]">
        {format_count(@vn.ratings_count, "rating")}
      </span>
    </div>
    """
  end

  attr :producers, :list, required: true
  attr :class, :string, default: nil

  defp producer_links(assigns) do
    assigns = assign(assigns, :producers, display_producers(assigns.producers))

    ~H"""
    <p :if={@producers != []} class={@class}>
      <%= for {producer, index} <- Enum.with_index(@producers) do %>
        <span :if={index > 0}>, </span>
        <.link
          :if={producer.slug}
          navigate={"/developer/#{producer.slug}"}
          class="text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
        >
          {producer.name}
        </.link>
        <span :if={!producer.slug}>{producer.name}</span>
      <% end %>
    </p>
    """
  end

  defp display_producers(producers) when is_list(producers) do
    producers
    |> Enum.filter(&developer_producer?/1)
    |> Enum.map(&normalize_producer_link/1)
    |> Enum.reject(&is_nil/1)
  end

  defp display_producers(_), do: []

  defp developer_producer?(%{role: role}) when role in ["developer", "developer_publisher"],
    do: true

  defp developer_producer?(_), do: false

  defp normalize_producer_link(%{producer: producer}), do: normalize_producer_link(producer)
  defp normalize_producer_link(%{name: name, slug: slug}), do: %{name: name, slug: slug}
  defp normalize_producer_link(%{name: name}), do: %{name: name, slug: nil}
  defp normalize_producer_link(_), do: nil

  attr :id, :string, required: true, doc: "Stable DOM id for the read-more toggle hook."
  attr :description, :string, default: ""
  attr :lines, :integer, default: 8, doc: "Lines to clamp to when collapsed."
  attr :limit, :integer, default: 794, doc: "Character budget before inline more is shown."
  attr :class, :any, default: nil

  defp description_read_more(assigns) do
    ~H"""
    <KaguyaWeb.SharedComponents.Markdown.markdown
      :if={present?(@description)}
      content={@description}
      variant="user"
      class={@class}
      read_more
      read_more_id={@id}
      read_more_lines={@lines}
      read_more_limit={@limit}
    />
    """
  end

  defp vn_hidden?(vn), do: Map.get(vn, :is_hidden) == true or not is_nil(Map.get(vn, :hidden_at))

  defp present?(value), do: value not in [nil, ""]

  defp show_ratings?(vn), do: (vn.ratings_count || 0) >= @min_ratings_to_display

  # ---------------------------------------------------------------------------
  # Reading stats + ratings histogram. Slots into the desktop header
  # between the tabs/tags block and any subsequent friend activity, the
  # same place prod's `VNHeaderDesktop` renders ReadingStats + RatingsChart.
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true

  def reading_stats_row(assigns) do
    show_stats? = (assigns.vn.readers_count || 0) > 0 and (assigns.vn.want_to_read_count || 0) > 0
    show_chart? = (assigns.vn.ratings_count || 0) >= @min_ratings_to_display
    assigns = assign(assigns, show_stats?: show_stats?, show_chart?: show_chart?)

    ~H"""
    <div
      :if={@show_stats? and @show_chart?}
      class="max-lg:hidden lg:px-8"
    >
      <div class="h-px bg-[rgb(var(--border-divider))]"></div>
    </div>
    <div
      :if={@show_stats? and @show_chart?}
      class="mt-5 flex items-center pt-0 max-lg:hidden lg:px-8"
    >
      <div class="flex flex-col gap-3">
        <.reader_count_row
          label="reading"
          count={@vn.readers_count}
          avatars={Enum.take(@vn.readers, 4)}
        />
        <.reader_count_row
          label="wishlisted"
          count={@vn.want_to_read_count}
          avatars={Enum.take(@vn.want_to_readers, 4)}
        />
      </div>

      <div class="mx-8 w-px shrink-0 self-stretch bg-[rgb(var(--border-divider))]"></div>

      <.ratings_histogram vn={@vn} />
    </div>

    <div :if={@show_stats? and @show_chart?} class="mx-4 mt-2 flex items-center lg:hidden">
      <div class="min-w-0 flex-1">
        <.ratings_histogram vn={@vn} mobile />
      </div>
      <div class="mx-5 w-px shrink-0 self-stretch bg-[rgb(var(--border-divider))]"></div>
      <div class="flex shrink-0 flex-col gap-3">
        <.reader_count_row
          label="reading"
          count={@vn.readers_count}
          avatars={Enum.take(@vn.readers, 4)}
        />
        <.reader_count_row
          label="wishlisted"
          count={@vn.want_to_read_count}
          avatars={Enum.take(@vn.want_to_readers, 4)}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :avatars, :list, default: []

  defp reader_count_row(assigns) do
    assigns = assign(assigns, :avatars, Enum.filter(assigns.avatars || [], &user_profile_path/1))

    ~H"""
    <div :if={(@count || 0) > 0} class="flex items-center">
      <div :if={@avatars != []} class="flex -space-x-2.5">
        <%= for {user, index} <- Enum.with_index(@avatars) do %>
          <.link
            navigate={user_profile_path(user)}
            class="relative rounded-full transition hover:z-10 focus:z-10 focus:outline-none"
            style={"z-index: #{length(@avatars) - index}"}
            aria-label={user_profile_label(user)}
          >
            <.reader_avatar user={user} />
          </.link>
        <% end %>
      </div>
      <p class={["text-[13px] text-[rgb(var(--foreground-secondary))]", @avatars != [] && "ml-2"]}>
        <span class="font-medium text-[rgb(var(--foreground-tertiary))] tabular-nums">
          {with_commas(@count)}
        </span>
        <span class="ml-1">{@label}</span>
      </p>
    </div>
    """
  end

  attr :user, :map, required: true

  defp reader_avatar(assigns) do
    ~H"""
    <%= if avatar_url = user_avatar_url(@user) do %>
      <img
        src={avatar_url}
        alt={user_avatar_alt(@user)}
        class="size-7 rounded-full border-2 border-[rgb(var(--surface-base))] object-cover"
      />
    <% else %>
      <div class="flex size-7 items-center justify-center rounded-full border-2 border-[rgb(var(--surface-base))] bg-[rgb(var(--surface-banner))] text-[10px] font-medium text-[rgb(var(--foreground-tertiary))]">
        {user_initial(@user)}
      </div>
    <% end %>
    """
  end

  defp user_profile_path(user) do
    case map_value(user, :username) do
      username when is_binary(username) and username != "" -> "/@#{username}"
      _ -> nil
    end
  end

  defp user_profile_label(user) do
    case map_value(user, :username) do
      username when is_binary(username) and username != "" -> "#{username}'s profile"
      _ -> "User profile"
    end
  end

  defp user_avatar_alt(user) do
    case map_value(user, :username) do
      username when is_binary(username) and username != "" -> "#{username}'s avatar"
      _ -> "User avatar"
    end
  end

  defp user_avatar_url(user) do
    avatar_urls = map_value(user, :avatar_urls) || map_value(user, :avatarUrls) || %{}
    map_value(user, :avatar_url) || map_value(avatar_urls, :small)
  end

  defp user_initial(user) do
    user
    |> map_value(:username)
    |> case do
      username when is_binary(username) and username != "" ->
        username |> String.first() |> String.upcase()

      _ ->
        "?"
    end
  end

  attr :vn, :map, required: true
  attr :mobile, :boolean, default: false

  defp ratings_histogram(assigns) do
    assigns =
      assigns
      |> assign(:card_class, if(assigns.mobile, do: "h-[120px]", else: "h-[90px]"))
      |> assign(:rating_count, assigns.vn.ratings_count || 0)
      |> assign(:average_rating, assigns.vn.average_rating || 0.0)

    ~H"""
    <div class={[@mobile && "w-full", !@mobile && "w-[220px] shrink-0"]}>
      <.ratings_chart
        dist={@vn.ratings_dist}
        count={@rating_count}
        average={@average_rating}
        vn_slug={@vn.slug}
        hide_title
        card_class={@card_class}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Tabs + panel + tags-section. Tabs dispatch `switch_tab` to the LiveView.
  # ---------------------------------------------------------------------------

  attr :active_tab, :atom, required: true
  attr :mobile, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  def vn_tabs(assigns) do
    ~H"""
    <div class={[
      "mt-4",
      @mobile && "overflow-x-auto border-b border-[rgb(var(--border-divider))]",
      !@mobile && "flex items-end justify-between pt-2 pb-3"
    ]}>
      <div class={[
        "flex gap-4 px-3",
        @mobile && "min-w-max",
        !@mobile && "border-b border-[rgb(var(--border-divider))]"
      ]}>
        <button
          :for={{tab, label} <- tab_options()}
          type="button"
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "cursor-pointer rounded-none border-b-2 px-0 py-2 text-[13px] font-normal tracking-wide uppercase transition",
            tab_button_class(@active_tab == tab)
          ]}
        >
          {label}
        </button>
      </div>

      <.tab_action_bar
        :if={!@mobile}
        active_tab={@active_tab}
        user_can_edit={@user_can_edit}
      />
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :active_tab, :atom, required: true
  attr :tabs, :map, required: true
  attr :release_filters, :map, default: %{language: nil, platform: nil}
  attr :release_filter_options, :map, default: %{languages: [], platforms: []}
  attr :expanded_tag_kinds, :list, default: []
  attr :id_prefix, :string, default: "vn"
  attr :mobile, :boolean, default: false
  attr :current_user, :map, default: nil
  attr :is_logged_in, :boolean, default: false
  attr :user_can_edit, :boolean, default: false

  def vn_tab_panel(assigns) do
    ~H"""
    <div class="mt-2">
      <%= case Map.fetch!(@tabs, @active_tab) do %>
        <% {:ok, tags} when @active_tab == :tags -> %>
          <Panels.Tags.panel
            tags={tags}
            visual_novel_id={@vn.id}
            available_on_links={@vn.available_on_links}
            id_prefix={@id_prefix}
            is_logged_in={@is_logged_in}
            user_can_edit={@user_can_edit}
            expanded_kinds={@expanded_tag_kinds}
          />
        <% :not_loaded -> %>
          <.tab_skeleton tab={@active_tab} />
        <% :loading -> %>
          <.tab_skeleton tab={@active_tab} />
        <% {:error, _reason} -> %>
          <.tab_message text="This section could not be loaded right now." />
        <% {:ok, []} when @active_tab == :covers -> %>
          <.tab_message text="No covers yet" />
        <% {:ok, []} when @active_tab == :screenshots -> %>
          <.tab_message text="No screenshots yet" />
        <% {:ok, []} when @active_tab == :releases -> %>
          <.tab_message text="No releases available." />
        <% {:ok, []} when @active_tab == :quotes -> %>
          <.tab_message text="No quotes found for this visual novel." />
        <% {:ok, items} when @active_tab == :covers -> %>
          <Panels.Covers.panel items={items} is_logged_in={@is_logged_in} />
        <% {:ok, items} when @active_tab == :screenshots -> %>
          <Panels.Screenshots.panel
            items={items}
            show_nsfw={Map.get(@current_user || %{}, :show_nsfw_screenshots, false)}
            show_brutal={Map.get(@current_user || %{}, :show_brutal_screenshots, false)}
            is_logged_in={@is_logged_in}
          />
        <% {:ok, items} when @active_tab == :releases -> %>
          <Panels.Releases.panel
            items={items}
            filters={@release_filters}
            filter_options={@release_filter_options}
            mobile={@mobile}
          />
        <% {:ok, items} when @active_tab == :quotes -> %>
          <Panels.Quotes.panel items={items} />
      <% end %>
    </div>
    """
  end

  attr :active_tab, :atom, required: true
  attr :user_can_edit, :boolean, default: false

  defp tab_action_bar(assigns) do
    ~H"""
    <div :if={@user_can_edit and @active_tab in [:tags, :quotes]} class="shrink-0 pb-2">
      <button
        :if={@active_tab == :tags}
        type="button"
        phx-click="open_tag_dialog"
        class={tab_action_class()}
      >
        <Lucide.plus class="size-3" aria-hidden /> Add
      </button>
      <button
        :if={@active_tab == :quotes}
        type="button"
        phx-click="open_quote_dialog"
        class={tab_action_class()}
      >
        <Lucide.plus class="size-3" aria-hidden /> Add
      </button>
    </div>
    """
  end

  defp tab_action_class do
    "flex items-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-2 py-1 text-xs font-normal text-[rgb(var(--foreground-secondary))] transition-colors hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
  end

  attr :text, :string, required: true

  defp tab_message(assigns) do
    ~H"""
    <p class="py-8 text-center text-sm text-[rgb(var(--foreground-tertiary))]">{@text}</p>
    """
  end

  # ---------------------------------------------------------------------------
  # Skeletons matched to each tab's eventual layout, so the user sees the
  # *shape* of the data while it loads instead of a generic "Loading…".
  # ---------------------------------------------------------------------------

  attr :tab, :atom, required: true

  defp tab_skeleton(%{tab: :tags} = assigns), do: Panels.Tags.skeleton(assigns)

  defp tab_skeleton(%{tab: :covers} = assigns), do: Panels.Covers.skeleton(assigns)
  defp tab_skeleton(%{tab: :screenshots} = assigns), do: Panels.Screenshots.skeleton(assigns)
  defp tab_skeleton(%{tab: :releases} = assigns), do: Panels.Releases.skeleton(assigns)
  defp tab_skeleton(%{tab: :quotes} = assigns), do: Panels.Quotes.skeleton(assigns)

  defp tab_skeleton(assigns) do
    ~H"""
    <p class="py-8 text-sm text-[rgb(var(--foreground-tertiary))]">Loading…</p>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp tab_options do
    [
      tags: "Tags",
      covers: "Covers",
      screenshots: "Screens",
      releases: "Releases",
      quotes: "Quotes"
    ]
  end

  defp tab_button_class(true) do
    "border-[rgb(var(--foreground-secondary))] text-[rgb(var(--foreground-secondary))]"
  end

  defp tab_button_class(false) do
    "border-transparent text-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-secondary))]"
  end
end

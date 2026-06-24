defmodule KaguyaWeb.ProfileLive.Show do
  @moduledoc """
  `/@:username` — main profile (overview) tab.

  Owns:

    * The two-column grid body (left content / right sidebar) the
      overview tab renders below the shared header.
    * The mod-panel dialogs (manage permissions / suppress ratings / delete
      user). The header is mounted here in its un-collapsed form, so this
      LiveView is the natural home for the dialogs that overlay it.

  Header + nav stay in `KaguyaWeb.Components.Profile.Header.header/1` —
  this module does not re-implement them.
  """

  use KaguyaWeb.ProfileLive, tab: :overview

  alias Kaguya.Profiles.Overview
  alias Kaguya.Reviews
  alias Kaguya.Users

  alias KaguyaWeb.Components.Profile.{
    ActivitySnapshot,
    ModPanel,
    Placeholder,
    Shared,
    SocialLinks
  }

  alias KaguyaWeb.Components.Shared.RatingsChart
  alias KaguyaWeb.Components.VN.Cards
  alias KaguyaWeb.Lists.Cards, as: ListCards
  alias KaguyaWeb.ProfileLive.{Data, Events}
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @permission_fields ~w(can_edit can_discuss can_review can_list mod_db mod_discussions mod_reviews mod_lists mod_users)a

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Phoenix.Component.assign(:state, :loading)
     |> Phoenix.Component.assign(:profile, nil)
     |> Phoenix.Component.assign(:overview, nil)
     |> Phoenix.Component.assign(:permissions, %{any?: false})
     |> Phoenix.Component.assign(:page_title, "Profile · Kaguya")
     |> Phoenix.Component.assign(:current_tab, :overview)
     |> Phoenix.Component.assign(:root?, true)
     |> Phoenix.Component.assign(:mod_dialog, nil)
     |> Phoenix.Component.assign(:mod_state, default_mod_state())
     |> Phoenix.Component.assign(:mod_draft, default_mod_state())
     |> Phoenix.Component.assign(:mod_saved, default_mod_state())
     |> Phoenix.Component.assign(:mod_busy, false)}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    with {:ok, profile} <- Data.load_header(username, viewer),
         {:ok, user} <- Users.get_user(profile.id) do
      overview = Overview.profile_overview(user, viewer)
      mod_state = mod_state_from_user(user)

      {:noreply,
       socket
       |> Phoenix.Component.assign(:state, :ready)
       |> Phoenix.Component.assign(:profile, profile)
       |> Phoenix.Component.assign(:overview, overview)
       |> Phoenix.Component.assign(:permissions, Data.viewer_permissions(viewer))
       |> Phoenix.Component.assign(:page_title, Data.page_title(profile))
       |> Phoenix.Component.assign(:mod_state, mod_state)
       |> Phoenix.Component.assign(:mod_saved, mod_state)
       |> Phoenix.Component.assign(:mod_draft, mod_state)}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:state, :not_found)
         |> Phoenix.Component.assign(:page_title, "User not found · Kaguya")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <KaguyaWeb.Components.Profile.Header.header
        profile={@profile}
        current_tab={@current_tab}
        permissions={@permissions}
        mod_state={@mod_state}
        root?={true}
      />

      <.overview_body profile={@profile} overview={@overview} />

      <ModPanel.permissions_dialog
        open={@mod_dialog == :permissions}
        profile={@profile}
        permissions={@permissions}
        draft={@mod_draft}
        saved={@mod_saved}
        busy={@mod_busy}
      />

      <ModPanel.suppress_dialog
        open={@mod_dialog == :suppress}
        profile={@profile}
        ratings_suppressed={Map.get(@mod_state, :ratings_suppressed, false)}
        busy={@mod_busy}
      />

      <ModPanel.delete_dialog
        open={@mod_dialog == :delete}
        profile={@profile}
        busy={@mod_busy}
      />
    </main>
    """
  end

  attr :profile, :map, required: true
  attr :overview, :map, required: true

  defp overview_body(assigns) do
    profile = assigns.profile
    is_mine = profile.viewer.is_mine
    username = profile.username

    assigns =
      assigns
      |> assign(:is_mine, is_mine)
      |> assign(:username, username)
      |> assign(:has_bio, present?(profile.bio))
      |> assign(:has_socials, has_socials?(profile.social_links))

    ~H"""
    <section class="mt-8 lg:mx-auto lg:mt-6 lg:max-w-[988px]">
      <div class="lg:grid lg:grid-cols-[minmax(0,652px)_1fr] lg:gap-20">
        <%!-- LEFT COLUMN --%>
        <div class="flex flex-col gap-8 max-lg:px-4 lg:gap-3">
          <%!-- Mobile bio --%>
          <div :if={@has_bio} class="flex flex-col gap-2 lg:hidden">
            <span class="text-style-body1Medium text-[rgb(var(--foreground-secondary))]">Bio</span>
            <KaguyaWeb.SharedComponents.Markdown.markdown
              content={@profile.bio}
              variant="bio"
              class="bio-content text-sm text-[rgb(var(--foreground-secondary))]"
            />
          </div>

          <.favorite_visual_novels items={@overview.favorite_visual_novels} is_mine={@is_mine} />

          <.favorite_characters_mobile items={@overview.favorite_characters} />

          <.recently_read items={@overview.vn_finished} username={@username} />

          <.currently_reading items={@overview.vn_currently_reading} username={@username} />

          <%!-- Mobile ratings chart --%>
          <div :if={@overview.ratings.count > 0} class="lg:hidden">
            <RatingsChart.ratings_chart
              dist={@overview.ratings.dist}
              count={@overview.ratings.count}
              average={@overview.ratings.average}
              username={@username}
              compact
            />
          </div>

          <.popular_lists items={@overview.popular_lists} username={@username} />
          <.popular_reviews items={@overview.popular_reviews} username={@username} />
          <.recent_reviews items={@overview.recent_reviews} username={@username} />
        </div>

        <%!-- RIGHT SIDEBAR (desktop only at lg+) --%>
        <div class="h-fit rounded-[12px] max-lg:mt-8 lg:max-w-[300px]">
          <.sidebar_bio profile={@profile} is_mine={@is_mine} has_bio={@has_bio} />
          <.sidebar_favorite_characters items={@overview.favorite_characters} is_mine={@is_mine} />
          <.sidebar_ratings profile={@profile} overview={@overview} />
          <.sidebar_wishlist
            items={@overview.vn_want_to_read}
            count={@overview.want_to_read_count}
            username={@username}
          />
          <.sidebar_shelves shelves={@overview.shelves} username={@username} />
          <.sidebar_following
            profile={@profile}
            items={@overview.following_preview}
            username={@username}
          />

          <div class="max-lg:hidden">
            <ActivitySnapshot.activity_snapshot
              items={@overview.recent_activity}
              username={@username}
              display_name={@profile.display_name}
            />
          </div>

          <.member_since inserted_at={@profile.inserted_at} />
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Left-column sections
  # ---------------------------------------------------------------------------

  attr :items, :list, required: true
  attr :is_mine, :boolean, required: true

  defp favorite_visual_novels(assigns) do
    items = assigns.items || []

    if assigns.is_mine == false and items == [] do
      ~H""
    else
      assigns = assign(assigns, :items, items)

      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <div class="lg:text-style-body1Regular max-lg:text-style-body1Medium max-lg:text-[rgb(var(--foreground-secondary))] lg:py-2 lg:text-[rgb(var(--foreground-primary))]">
          Favorite Visual Novels
        </div>
        <div class="mb-[14px] hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>

        <KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider id="profile-favorite-vn-tooltips">
          <div class="mt-2.5 grid grid-cols-4 gap-x-1 lg:mt-0 lg:gap-x-[12px]">
            <Cards.cover
              :for={vn <- @items}
              vn={vn}
              link
              show_title_tooltip
              sizes="(max-width: 768px) 106px, 131px"
              class="aspect-1/1.5 w-full rounded-[4px] object-cover object-center"
            />
            <.empty_favorite_slot
              :for={_ <- empty_slot_range(@items, 4)}
              is_mine={@is_mine}
              href="/account/edit/profile#favorite-visual-novels"
            />
          </div>
        </KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider>
      </div>
      """
    end
  end

  attr :is_mine, :boolean, required: true
  attr :href, :string, required: true

  defp empty_favorite_slot(assigns) do
    ~H"""
    <%= if @is_mine do %>
      <.link
        navigate={@href}
        class="group flex aspect-1/1.5 size-full items-center justify-center rounded-[4px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] transition-colors hover:border-[rgb(var(--border-strong-divider,var(--foreground-tertiary)))] lg:rounded-[6px]"
      >
        <Lucide.plus
          class="size-6 text-[rgb(var(--border-divider))] transition-colors group-hover:text-[rgb(var(--foreground-secondary))] max-sm:size-5"
          stroke-width="1.5"
          aria-hidden
        />
      </.link>
    <% else %>
      <span class="flex aspect-1/1.5 size-full items-center justify-center rounded-[4px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] lg:rounded-[6px]" />
    <% end %>
    """
  end

  defp empty_slot_range(items, total) do
    1..max(total - length(items), 0)//1
  end

  attr :items, :list, required: true

  defp favorite_characters_mobile(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="flex flex-col gap-2.5 lg:hidden">
        <span class="text-style-body1Medium text-[rgb(var(--foreground-secondary))]">
          Favorite characters
        </span>
        <KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider
          id="profile-mobile-character-tooltips"
          data_attribute="data-character-name"
        >
          <div class="grid grid-cols-4 gap-x-1">
            <.link
              :for={c <- Enum.take(@items, 4)}
              navigate={c.slug && "/character/#{c.slug}"}
            >
              <Cards.character_image
                character={c}
                sizes="(max-width: 768px) 25vw, 120px"
                show_name_tooltip
              />
            </.link>
          </div>
        </KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :username, :string, required: true

  defp recently_read(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <.section_header_link
          label="Recently Read"
          href={"/@#{@username}/library/read"}
        />
        <KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider id="profile-recently-read-tooltips">
          <div class="grid grid-cols-4 gap-x-1 lg:gap-x-[12px]">
            <div :for={item <- Enum.take(@items, 4)} class="flex flex-col gap-0.5 sm:gap-1">
              <div class="aspect-1/1.5 w-full overflow-hidden rounded-[4px]">
                <Cards.cover
                  vn={item}
                  sizes="(max-width: 1024px) 82px, 256px"
                  link
                  show_title_tooltip
                />
              </div>
              <div class="flex items-center gap-1.5">
                <KaguyaWeb.VN.Icons.display_ratings
                  rating={item[:rating] || 0}
                  class="gap-[3px] max-sm:gap-0.5"
                  star_class="size-[13px] !text-[rgb(var(--component-rating-distribution-bar-default,var(--icons-user-star)))] max-sm:size-2"
                  half_rating_class="max-sm:!-mb-[2px] max-sm:!text-[9px] max-sm:!leading-[11px] !text-[rgb(var(--component-rating-distribution-bar-default,var(--icons-user-star)))]"
                />
                <.link
                  :if={item[:review_id]}
                  navigate={"/@#{@username}/reviews/#{item.slug}"}
                  class="-m-1.5 p-1.5"
                  aria-label="Read review"
                >
                  <Lucide.menu
                    class="size-[13px] translate-y-px text-[rgb(var(--component-rating-distribution-bar-default,var(--foreground-secondary)))]"
                    aria-hidden
                  />
                </.link>
              </div>
            </div>
          </div>
        </KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :username, :string, required: true

  defp currently_reading(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <.section_header_link
          label="Currently Reading"
          href={"/@#{@username}/library/reading"}
        />
        <KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider id="profile-currently-reading-tooltips">
          <div class="grid grid-cols-4 gap-x-1 lg:gap-x-[12px]">
            <div :for={vn <- Enum.take(@items, 4)} class="flex flex-col gap-0.5 sm:gap-1">
              <div class="aspect-1/1.5 w-full overflow-hidden rounded-[4px]">
                <Cards.cover
                  vn={vn}
                  sizes="(max-width: 1024px) 82px, 256px"
                  link
                  show_title_tooltip
                />
              </div>
            </div>
          </div>
        </KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :username, :string, required: true

  defp popular_lists(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <.section_header_link
          label="Popular Lists"
          href={"/@#{@username}/lists"}
        />
        <div class="grid gap-6 sm:grid-cols-2 sm:gap-[37px]">
          <ListCards.list_card
            :for={list <- @items}
            list={list}
            sizes="(max-width: 640px) 82px, (max-width: 768px) 106px, 131px"
            responsive_max_covers={%{mobile: 5, desktop: 4}}
            container_class="flex w-full -space-x-[15px] overflow-hidden rounded-[3px] sm:-space-x-[85px]"
            grid_class="rounded-[3px]"
            image_class="rounded-[3px]"
            title_class="mt-2"
          />
        </div>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :username, :string, required: true

  defp popular_reviews(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <.section_header_link
          label="Popular Reviews"
          href={"/@#{@username}/reviews?sort=MOST_LIKED"}
        />
        <div class="[&>*:first-child>div]:pt-0 [&>*:last-child>div]:pb-0">
          <Cards.vn_review_card
            :for={review <- @items}
            review={review}
            full_width
            align_left
            like_event="toggle_review_like"
            id_prefix="profile-popular-review-card"
          />
        </div>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :username, :string, required: true

  defp recent_reviews(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="rounded-[12px] lg:py-3">
        <.section_header_link
          label="Recent Reviews"
          href={"/@#{@username}/reviews?sort=NEWEST"}
        />
        <div class="[&>*:first-child>div]:pt-0 [&>*:last-child>div]:pb-0">
          <Cards.vn_review_card
            :for={review <- @items}
            review={review}
            full_width
            align_left
            like_event="toggle_review_like"
            id_prefix="profile-recent-review-card"
          />
        </div>
      </div>
      """
    end
  end

  attr :label, :string, required: true
  attr :href, :string, required: true

  defp section_header_link(assigns) do
    ~H"""
    <div class="flex items-center justify-between max-lg:mb-2.5 lg:py-2">
      <.link
        navigate={@href}
        class="lg:text-style-body1Regular max-lg:text-style-body1Medium flex cursor-pointer items-center gap-1 max-lg:text-[rgb(var(--foreground-secondary))] lg:text-[rgb(var(--foreground-primary))] lg:hover:text-[rgb(var(--text-link-hover))]"
      >
        {@label}
        <Lucide.chevron_right
          class="mt-px size-4 text-[rgb(var(--foreground-tertiary))] lg:hidden"
          aria-hidden
        />
      </.link>
    </div>
    <div class="mb-[14px] hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>
    """
  end

  # ---------------------------------------------------------------------------
  # Right sidebar sections (desktop)
  # ---------------------------------------------------------------------------

  attr :profile, :map, required: true
  attr :is_mine, :boolean, required: true
  attr :has_bio, :boolean, required: true

  defp sidebar_bio(assigns) do
    if not assigns.is_mine and not assigns.has_bio do
      ~H""
    else
      ~H"""
      <div class="flex flex-col max-lg:hidden lg:py-[18px]">
        <span class="text-style-body2Regular border-b border-[rgb(var(--border-divider))] py-2 text-[rgb(var(--foreground-primary))]">
          Bio
        </span>
        <%= if @has_bio do %>
          <KaguyaWeb.SharedComponents.Markdown.markdown
            content={@profile.bio}
            variant="bio"
            class="bio-content pt-4 text-sm text-[rgb(var(--foreground-primary))]"
          />
        <% else %>
          <p class="pt-4 text-sm text-[rgb(var(--foreground-secondary))]">
            <.link
              navigate="/account/edit/profile#basic-information"
              class="text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
            >
              Write something about yourself
            </.link>
          </p>
        <% end %>
        <SocialLinks.social_links
          instagram={@profile.social_links.instagram}
          website={@profile.social_links.website}
          twitter={@profile.social_links.twitter}
          tiktok={@profile.social_links.tiktok}
          compact
        />
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :is_mine, :boolean, required: true

  defp sidebar_favorite_characters(assigns) do
    if assigns.items == [] and not assigns.is_mine do
      ~H""
    else
      ~H"""
      <div class="flex flex-col max-lg:hidden lg:py-[18px]">
        <span class="text-style-body2Regular border-b border-[rgb(var(--border-divider))] py-2 text-[rgb(var(--foreground-primary))]">
          Favorite Characters
        </span>
        <%= if @items != [] do %>
          <KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider
            id="profile-sidebar-character-tooltips"
            data_attribute="data-character-name"
          >
            <div class="grid grid-cols-2 gap-3 pt-4">
              <.link
                :for={c <- Enum.take(@items, 4)}
                navigate={c.slug && "/character/#{c.slug}"}
                class="flex w-full min-w-0 flex-col gap-2"
              >
                <Cards.character_image character={c} sizes="140px" show_name_tooltip />
              </.link>
            </div>
          </KaguyaWeb.SharedComponents.Cover.cover_tooltip_provider>
        <% else %>
          <p class="pt-4 text-sm text-[rgb(var(--foreground-secondary))]">
            <%= if @is_mine do %>
              <.link
                navigate="/account/edit/profile#favorite-characters"
                class="text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
              >
                Pin your favorite characters
              </.link>
            <% else %>
              No favorite characters added
            <% end %>
          </p>
        <% end %>
      </div>
      """
    end
  end

  attr :profile, :map, required: true
  attr :overview, :map, required: true

  defp sidebar_ratings(assigns) do
    if assigns.overview.ratings.count == 0 do
      ~H""
    else
      ratings = assigns.overview.ratings
      assigns = assign(assigns, :ratings, ratings)

      ~H"""
      <div class="flex flex-col max-lg:hidden lg:py-[18px]">
        <div class="flex items-center justify-between border-b border-[rgb(var(--border-divider))] py-2">
          <span class="text-style-body2Regular text-[rgb(var(--foreground-primary))]">Ratings</span>
          <div class="flex items-center gap-0.5">
            <span class="text-[rgb(var(--component-rating-distribution-bar-default,var(--icons-user-star)))]">
              ★
            </span>
            <span class="text-style-captionMedium text-[rgb(var(--foreground-primary))]">
              {Float.round(@ratings.average || 0.0, 1)}
            </span>
            <span class="text-style-captionRegular text-[rgb(var(--foreground-secondary))]">
              ({@ratings.count})
            </span>
          </div>
        </div>
        <div class="pt-4">
          <RatingsChart.ratings_chart
            dist={@ratings.dist}
            count={@ratings.count}
            average={@ratings.average}
            username={@profile.username}
            class="h-[100px]"
            hide_title
          />
        </div>
      </div>
      """
    end
  end

  attr :items, :list, required: true
  attr :count, :integer, required: true
  attr :username, :string, required: true

  defp sidebar_wishlist(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="flex flex-col px-0 max-lg:mb-8 max-lg:gap-2.5 max-lg:pl-4 lg:py-[18px]">
        <div class="flex w-full items-center justify-between max-lg:pr-5 lg:border-b lg:border-[rgb(var(--border-divider))] lg:py-2">
          <.link
            navigate={"/@#{@username}/library/wishlist"}
            class="flex items-center gap-1 lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            <span class="lg:text-style-body2Regular text-style-body1Medium text-[rgb(var(--foreground-secondary))] lg:text-[rgb(var(--foreground-primary))]">
              Wishlist
              <span
                :if={@count > 0}
                class="font-normal max-lg:text-sm max-lg:text-[rgb(var(--foreground-primary))]/40 lg:text-[rgb(var(--foreground-secondary))]"
              >
                ({@count})
              </span>
            </span>
            <Lucide.chevron_right
              class="mt-px size-4 text-[rgb(var(--foreground-tertiary))] lg:hidden"
              aria-hidden
            />
          </.link>
        </div>
        <div class="lg:pt-4">
          <Cards.stacked_covers
            items={Enum.take(@items, 5)}
            max_covers={5}
            container_class="hidden lg:flex w-fit overflow-hidden -space-x-[25px] rounded-[3px] bg-[rgb(var(--surface-elevated))]"
            link
          />
          <div class="grid grid-cols-4 gap-1 lg:hidden">
            <Cards.cover
              :for={vn <- Enum.take(@items, 8)}
              vn={vn}
              sizes="(max-width: 1024px) 25vw, 100px"
              class="aspect-1/1.5 w-full rounded-[4px] object-cover"
              link
            />
          </div>
        </div>
      </div>
      """
    end
  end

  attr :shelves, :list, required: true
  attr :username, :string, required: true

  defp sidebar_shelves(assigns) do
    if assigns.shelves == [] do
      ~H""
    else
      ~H"""
      <div class="flex flex-col max-lg:hidden lg:py-[18px]">
        <div class="border-b border-[rgb(var(--border-divider))] py-2">
          <.link
            navigate={"/@#{@username}/library"}
            class="text-style-body2Medium text-[rgb(var(--foreground-primary))] lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            Labels
          </.link>
        </div>
        <div class="flex flex-wrap gap-1 pt-4">
          <.link
            :for={shelf <- Enum.take(@shelves, 11)}
            navigate={"/@#{@username}/library/#{shelf.slug}"}
            class="text-style-captionMedium flex items-center rounded-[4px] bg-[rgb(var(--chip-border-default,var(--surface-elevated)))] px-2 py-1 text-[rgb(var(--foreground-primary))] transition-colors duration-200 hover:bg-[rgb(var(--chip-border-hover,var(--surface-elevated-2)))]"
          >
            {shelf.name}
          </.link>
        </div>
      </div>
      """
    end
  end

  attr :profile, :map, required: true
  attr :items, :list, required: true
  attr :username, :string, required: true

  defp sidebar_following(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="flex flex-col px-0 max-lg:gap-2.5 max-lg:px-4 lg:py-[18px]">
        <div class="flex w-full items-center justify-between lg:border-b lg:border-[rgb(var(--border-divider))] lg:py-2">
          <.link
            navigate={"/@#{@username}/following"}
            class="lg:text-style-body2Medium max-lg:text-style-body1Medium text-[rgb(var(--foreground-secondary))] lg:text-[rgb(var(--foreground-primary))] lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            Following
            <span class="font-normal max-lg:text-sm max-lg:text-[rgb(var(--foreground-primary))]/40 lg:text-[rgb(var(--foreground-secondary))]">
              ({Shared.format_short_number(@profile.counts.following)})
            </span>
          </.link>
        </div>
        <div class="grid grid-cols-6 gap-2 lg:grid-cols-4 lg:gap-x-1.5 lg:gap-y-5 lg:pt-4">
          <.link
            :for={u <- Enum.take(@items, 12)}
            navigate={"/@#{u.username}"}
            class="aspect-square"
            title={u.display_name}
          >
            <Shared.avatar
              user={u}
              class="size-full rounded-full object-cover"
              sizes="(max-width: 1024px) 15vw, 57px"
            />
          </.link>
        </div>
      </div>
      """
    end
  end

  attr :inserted_at, :any, required: true

  defp member_since(assigns) do
    ~H"""
    <div :if={@inserted_at} class="max-lg:hidden lg:py-3">
      <div class="flex items-center justify-center gap-1.5 rounded-[4px] border border-[rgb(var(--border-divider))] py-2">
        <Lucide.castle class="size-[13px] text-[rgb(var(--foreground-secondary))]" aria-hidden />
        <span class="text-style-captionRegular text-[rgb(var(--foreground-primary))]">
          {SharedTime.format_long_date(@inserted_at)}
        </span>
      </div>
    </div>
    """
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp has_socials?(%{} = links) do
    Enum.any?(Map.values(links), fn v -> is_binary(v) and v != "" end)
  end

  defp has_socials?(_), do: false

  # ---------------------------------------------------------------------------
  # Moderation events — overrides the Stream-0 stub.
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def handle_event("toggle_follow", params, socket) do
    case Events.toggle_follow(socket, params) do
      {:noreply, new_socket} -> {:noreply, refresh_overview(new_socket)}
      other -> other
    end
  end

  def handle_event("toggle_review_like", %{"review-id" => review_id}, socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} ->
        toggle_review_like_optimistic(socket, review_id, user_id)

      _ ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Sign in to like reviews.")}
    end
  end

  def handle_event("mod_open_permissions", _params, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:mod_dialog, :permissions)
     |> Phoenix.Component.assign(:mod_draft, socket.assigns.mod_saved)}
  end

  def handle_event("mod_open_suppress", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :mod_dialog, :suppress)}
  end

  def handle_event("mod_open_delete", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :mod_dialog, :delete)}
  end

  def handle_event("mod_close", _params, socket) do
    {:noreply, Phoenix.Component.assign(socket, :mod_dialog, nil)}
  end

  def handle_event("mod_toggle_permission", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    current = Map.get(socket.assigns.mod_draft, field_atom, false)
    new_draft = Map.put(socket.assigns.mod_draft, field_atom, not current)
    {:noreply, Phoenix.Component.assign(socket, :mod_draft, new_draft)}
  end

  def handle_event("mod_save_permissions", _params, socket) do
    viewer = socket.assigns[:current_user]
    profile = socket.assigns.profile

    if is_nil(viewer) or not socket.assigns.permissions.any? do
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Not authorized.")}
    else
      {user_fields, mod_fields} = ModPanel.manageable_fields(socket.assigns.permissions)
      allowed_fields = Enum.map(user_fields ++ mod_fields, & &1.field)

      diff =
        socket.assigns.mod_draft
        |> Map.take(allowed_fields)
        |> Enum.filter(fn {k, v} -> Map.get(socket.assigns.mod_saved, k) != v end)
        |> Map.new()

      if diff == %{} do
        {:noreply, Phoenix.Component.assign(socket, :mod_dialog, nil)}
      else
        socket = Phoenix.Component.assign(socket, :mod_busy, true)

        case Users.update_permissions(profile.id, diff) do
          {:ok, _user} ->
            Kaguya.AuditLog.log(
              viewer.id,
              "update_permissions",
              "user",
              profile.id,
              inspect(diff)
            )

            new_saved = Map.merge(socket.assigns.mod_saved, diff)

            {:noreply,
             socket
             |> Phoenix.Component.assign(:mod_busy, false)
             |> Phoenix.Component.assign(:mod_dialog, nil)
             |> Phoenix.Component.assign(:mod_saved, new_saved)
             |> Phoenix.Component.assign(:mod_draft, new_saved)
             |> Phoenix.LiveView.put_flash(:info, "Permissions updated")}

          {:error, _} ->
            {:noreply,
             socket
             |> Phoenix.Component.assign(:mod_busy, false)
             |> Phoenix.LiveView.put_flash(:error, "Failed to update permissions")}
        end
      end
    end
  end

  def handle_event("mod_confirm_suppress", _params, socket) do
    profile = socket.assigns.profile
    suppressed = Map.get(socket.assigns.mod_state, :ratings_suppressed, false)
    socket = Phoenix.Component.assign(socket, :mod_busy, true)

    result =
      if suppressed do
        Users.unsuppress_ratings(profile.id)
      else
        Users.suppress_ratings(profile.id)
      end

    case result do
      {:ok, user} ->
        new_state = mod_state_from_user(user)

        Kaguya.AuditLog.log(
          socket.assigns.current_user.id,
          if(suppressed, do: "unsuppress_ratings", else: "suppress_ratings"),
          "user",
          profile.id,
          ""
        )

        flash = if suppressed, do: "Ratings restored", else: "Ratings suppressed"

        {:noreply,
         socket
         |> Phoenix.Component.assign(:mod_busy, false)
         |> Phoenix.Component.assign(:mod_dialog, nil)
         |> Phoenix.Component.assign(:mod_state, new_state)
         |> Phoenix.LiveView.put_flash(:info, flash)}

      {:error, _} ->
        {:noreply,
         socket
         |> Phoenix.Component.assign(:mod_busy, false)
         |> Phoenix.LiveView.put_flash(:error, "Operation failed")}
    end
  end

  def handle_event("mod_confirm_delete", _params, socket) do
    profile = socket.assigns.profile
    viewer = socket.assigns[:current_user]

    if is_nil(viewer) or not Map.get(socket.assigns.permissions, :is_admin, false) do
      {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Admin only")}
    else
      socket = Phoenix.Component.assign(socket, :mod_busy, true)

      Kaguya.AuditLog.log(viewer.id, "admin_delete_user", "user", profile.id, "")

      with {:ok, _} <- Users.delete_user(profile.id) do
        {:noreply, Phoenix.LiveView.redirect(socket, to: "/")}
      else
        _ ->
          {:noreply,
           socket
           |> Phoenix.Component.assign(:mod_busy, false)
           |> Phoenix.LiveView.put_flash(:error, "Deletion failed")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp default_mod_state do
    @permission_fields
    |> Enum.map(fn k -> {k, default_flag(k)} end)
    |> Map.new()
    |> Map.put(:ratings_suppressed, false)
  end

  defp default_flag(k) when k in [:can_edit, :can_discuss, :can_review, :can_list], do: true
  defp default_flag(_), do: false

  defp mod_state_from_user(user) do
    Map.new(@permission_fields, fn k -> {k, Map.get(user, k, default_flag(k))} end)
    |> Map.put(:ratings_suppressed, Map.get(user, :ratings_suppressed, false))
  end

  defp refresh_overview(socket) do
    profile = socket.assigns.profile
    viewer = socket.assigns[:current_user]

    with %{id: id} <- profile,
         {:ok, user} <- Users.get_user(id) do
      Phoenix.Component.assign(socket, :overview, Overview.profile_overview(user, viewer))
    else
      _ -> socket
    end
  end

  defp toggle_review_like_optimistic(socket, review_id, user_id) do
    review = find_overview_review(socket.assigns.overview, review_id)

    cond do
      is_nil(review) ->
        {:noreply, socket}

      review.liked_by_me ->
        do_toggle_review_like(socket, review.id, &Reviews.unlike_review(&1, user_id), :unlike)

      true ->
        do_toggle_review_like(socket, review.id, &Reviews.like_review(&1, user_id), :like)
    end
  end

  defp do_toggle_review_like(socket, review_id, mutation, direction) do
    delta = if direction == :like, do: 1, else: -1
    liked? = direction == :like
    optimistic = update_overview_review(socket.assigns.overview, review_id, delta, liked?)
    socket = Phoenix.Component.assign(socket, :overview, optimistic)

    case mutation.(review_id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, reason} ->
        rolled_back = update_overview_review(optimistic, review_id, -delta, not liked?)

        {:noreply,
         socket
         |> Phoenix.Component.assign(:overview, rolled_back)
         |> Phoenix.LiveView.put_flash(:error, like_error_message(reason))}
    end
  end

  defp find_overview_review(overview, review_id) do
    Enum.find((overview.popular_reviews || []) ++ (overview.recent_reviews || []), fn review ->
      to_string(review.id) == to_string(review_id)
    end)
  end

  defp update_overview_review(overview, review_id, delta, liked?) do
    Map.update!(overview, :popular_reviews, &bump_overview_reviews(&1, review_id, delta, liked?))
    |> Map.update!(:recent_reviews, &bump_overview_reviews(&1, review_id, delta, liked?))
  end

  defp bump_overview_reviews(reviews, review_id, delta, liked?) do
    Enum.map(reviews || [], fn review ->
      if to_string(review.id) == to_string(review_id) do
        %{
          review
          | likes_count: max(0, (review.likes_count || 0) + delta),
            liked_by_me: liked?
        }
      else
        review
      end
    end)
  end

  defp like_error_message(reason) when is_binary(reason), do: reason
  defp like_error_message(_), do: "Could not update this like."
end

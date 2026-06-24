defmodule KaguyaWeb.ProfileLive.Lists do
  @moduledoc """
  `/@:username/lists` — paginated VN lists.

  Mirrors `../personal/legacy-next-app/src/components/profile/ListsTab.tsx` and its
  `ListRow` dependency. The LiveView reads `Kaguya.Lists` directly with
  the current viewer's visibility/content preferences.
  """

  use KaguyaWeb.ProfileLive, tab: :lists, title_suffix: "Lists"

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.ListItem
  alias Kaguya.Pagination
  alias Kaguya.Repo
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.ListLive.Data, as: ListData
  alias KaguyaWeb.Lists.Cards
  alias KaguyaWeb.SharedComponents.Pagination, as: SharedPagination

  @page_size 12
  @cover_page_size 5

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        page = parse_page(params["page"])
        lists = load_lists(profile, viewer, page)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Lists"))
         |> assign(:lists, lists)
         |> assign(:page, lists.pagination.page)
         |> assign(:total_pages, max(lists.pagination.total_pages || 0, 1))
         |> assign(:total_count, lists.pagination.total_count || 0)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <section class="mx-auto mt-8 flex w-full max-w-[988px] flex-1 flex-col max-lg:px-5 lg:mt-10">
        <div class="lg:grid lg:grid-cols-[1fr_270px] lg:gap-10">
          <div>
            <%= if @total_count > 0 do %>
              <div :if={@profile.viewer.is_mine} class="mb-4 flex justify-end lg:hidden">
                <.new_list_cta
                  class="h-9 w-full text-xs sm:w-fit sm:text-sm"
                  label="Start a new list"
                />
              </div>

              <div class="divide-y divide-[rgb(var(--border-divider))]">
                <div :for={list <- @lists.items} class="py-5 first:pt-0 lg:py-6">
                  <Cards.list_row
                    list={list}
                    hide_user
                    show_edit_link={@profile.viewer.is_mine}
                    show_description={false}
                    size={:large}
                  />
                </div>
              </div>
            <% else %>
              <.empty_lists
                is_mine={@profile.viewer.is_mine}
                profile_lists_count={@profile.counts.lists}
              />
            <% end %>

            <SharedPagination.pagination
              total_pages={@total_pages}
              current_page={@page}
              base_path={"/@" <> @profile.username <> "/lists"}
              aria_label="lists pagination"
            />
          </div>

          <div class="max-lg:hidden">
            <.new_list_cta
              :if={@profile.viewer.is_mine}
              class="h-9 w-full text-sm"
              label="Start a new list..."
            />
          </div>
        </div>
      </section>
    </main>
    """
  end

  attr :class, :any, default: nil
  attr :label, :string, required: true

  defp new_list_cta(assigns) do
    ~H"""
    <.link
      navigate="/list/new"
      rel="nofollow noindex"
      class={[
        "active:bg-button-background-neutral-inverse-pressed bg-button-background-neutral-inverse-default hover:bg-button-background-neutral-inverse-hover text-button-text-on-neutral-inverse inline-flex items-center justify-center gap-1.5 rounded-[4px] px-3 font-medium transition",
        @class
      ]}
    >
      <Lucide.plus class="size-[14px]" aria-hidden />
      <span>{@label}</span>
    </.link>
    """
  end

  attr :is_mine, :boolean, required: true
  attr :profile_lists_count, :integer, required: true

  defp empty_lists(assigns) do
    assigns = assign(assigns, :private?, !assigns.is_mine and assigns.profile_lists_count > 0)

    ~H"""
    <div class="flex min-h-[180px] items-center justify-center rounded-lg border border-[rgb(var(--border-divider))]">
      <p
        :if={@private?}
        class="flex items-center gap-1.5 text-sm text-[rgb(var(--foreground-tertiary))]"
      >
        <Lucide.lock class="size-[14px]" aria-hidden />
        <span>This user's lists are private.</span>
      </p>
      <p :if={!@private?} class="text-sm text-[rgb(var(--foreground-secondary))]">No lists yet.</p>
    </div>
    """
  end

  defp load_lists(profile, viewer, page) do
    viewer_id = Data.viewer_id(viewer)
    allowed = allowed_categories(profile, viewer)

    {:ok, %{items: items, pagination: pagination}} =
      Lists.list_user_lists(profile.id, viewer_id, %{
        page: page,
        page_size: @page_size,
        sort_by: :updated_at_desc,
        allowed_categories: allowed
      })

    %{
      items: hydrate_lists(items, profile, allowed),
      pagination: %{
        page: pagination.page,
        page_size: pagination.page_size,
        total_count: Pagination.resolve_count(pagination),
        total_pages: Pagination.resolve_total_pages(pagination)
      }
    }
  end

  defp hydrate_lists([], _profile, _allowed), do: []

  defp hydrate_lists(lists, profile, allowed) do
    owner = owner_view(profile)
    vn_batches = list_thumbnail_batches(lists, allowed)

    Enum.map(lists, fn list ->
      items =
        vn_batches
        |> Map.get(list.id, %{items: []})
        |> Map.get(:items, [])
        |> Enum.map(&normalize_item/1)

      list
      |> ListData.normalize_list()
      |> Map.put(:user, owner)
      |> Map.put(:visual_novels, %{items: items})
    end)
  end

  defp list_thumbnail_batches(lists, nil) do
    lists
    |> Enum.map(&{&1.id, &1.vns_count || 0})
    |> Lists.batch_list_vns_for_lists(@cover_page_size)
  end

  defp list_thumbnail_batches(lists, allowed) do
    list_ids = Enum.map(lists, & &1.id)
    page_size = @cover_page_size

    if list_ids == [] do
      %{}
    else
      ranked =
        from(li in ListItem,
          join: vn in VisualNovel,
          on: vn.id == li.visual_novel_id,
          where: li.list_id in ^list_ids and vn.title_category in ^allowed,
          windows: [w: [partition_by: li.list_id, order_by: li.position]],
          select: %{
            list_id: li.list_id,
            visual_novel_id: li.visual_novel_id,
            position: li.position,
            tier_id: li.tier_id,
            tier_position: li.tier_position,
            rn: row_number() |> over(:w)
          }
        )

      results =
        from(r in subquery(ranked),
          join: vn in VisualNovel,
          on: vn.id == r.visual_novel_id,
          where: r.rn <= ^page_size,
          order_by: [asc: r.list_id, asc: r.position],
          select: {r.list_id, r.position, r.tier_id, r.tier_position, vn}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0))
        |> Map.new(fn {list_id, rows} ->
          items =
            Enum.map(rows, fn {_list_id, position, tier_id, tier_position, vn} ->
              %{
                visual_novel: vn,
                position: position,
                tier_id: tier_id,
                tier_position: tier_position
              }
            end)

          {list_id, %{items: items}}
        end)

      Map.new(list_ids, &{&1, Map.get(results, &1, %{items: []})})
    end
  end

  defp normalize_item(%{visual_novel: vn} = item) do
    %{item | visual_novel: normalize_visual_novel(vn)}
  end

  defp normalize_visual_novel(%VisualNovel{} = vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp owner_view(profile) do
    avatar_urls = Map.get(profile, :avatar_urls) || %{}

    %{
      id: profile.id,
      username: profile.username,
      display_name: profile.display_name || profile.username,
      avatar_urls: avatar_urls,
      avatar_url: avatar_urls[:small]
    }
  end

  defp allowed_categories(%{viewer: %{is_mine: true}}, _viewer), do: nil
  defp allowed_categories(_profile, viewer), do: TitleCategory.allowed_categories(viewer || %{})

  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page >= 1 -> page
      _ -> 1
    end
  end

  defp parse_page(value) when is_integer(value) and value >= 1, do: value
  defp parse_page(_), do: 1
end

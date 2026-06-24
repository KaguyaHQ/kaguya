defmodule KaguyaWeb.ListLive.Form do
  use KaguyaWeb, :live_view

  alias Kaguya.Lists
  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.ListLive.Data
  alias KaguyaWeb.Lists.FormComponents

  @search_page_size 5
  @max_tier_count 10
  @tier_color_options [
    "#f87171",
    "#fb923c",
    "#facc15",
    "#4ade80",
    "#34d399",
    "#22d3ee",
    "#60a5fa",
    "#a78bfa",
    "#f472b6",
    "#94a3b8"
  ]

  @impl true
  def mount(_params, session, socket) do
    current_user = Map.get(socket.assigns, :current_user) || current_user_from_session(session)

    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(:current_user, current_user)
     |> assign(:navbar_class, "max-lg:hidden")
     |> assign(:hide_footer, true)
     |> assign(:auth_required?, is_nil(current_user))
     |> assign(:not_found?, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:search_error, nil)
     |> assign(:searching?, false)
     |> assign(:mobile_search_open?, false)
     |> assign(:tier_dialog_open?, false)
     |> assign(:draft_tiers, Data.default_tiers())
     |> assign(:dialog, nil)
     |> assign(:saving, false)
     |> assign(:deleting, false)
     |> assign(:item_error, nil)
     |> assign(:list, nil)
     |> assign(:tiers, Data.default_tiers())
     |> assign(:layout_state, %{display_mode: "grid", tiers: Data.default_tiers(), items: []})
     |> assign(:selected_items, [])
     |> assign(:form_attrs, attrs_from_list(%{}))
     |> assign(:initial_signature, nil)
     |> assign(:dirty?, false)
     |> put_form()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         socket
         |> assign(:auth_required?, true)
         |> assign(:page_title, auth_page_title(socket.assigns.live_action))}

      current_user ->
        {:noreply, load_editor(socket, params, current_user)}
    end
  end

  @impl true
  def handle_event("validate", %{"list" => attrs}, socket) do
    {:noreply, assign_form_attrs(socket, attrs)}
  end

  def handle_event("set_display_mode", %{"mode" => mode}, socket) do
    mode = if mode == "tier", do: "tier", else: "grid"

    {:noreply,
     socket
     |> assign_form_attrs(%{"display_mode" => mode})
     |> assign(:layout_state, %{socket.assigns.layout_state | display_mode: mode})
     |> push_event("list_layout:set_mode", %{mode: mode})}
  end

  def handle_event("toggle_flag", %{"field" => field}, socket)
      when field in ["is_public", "is_ranked"] do
    next_value = !truthy?(Map.get(socket.assigns.form_attrs, field))

    {:noreply, set_form_flag(socket, field, next_value)}
  end

  def handle_event("set_flag", %{"field" => field, "value" => value}, socket)
      when field in ["is_public", "is_ranked"] do
    {:noreply, set_form_flag(socket, field, truthy?(value))}
  end

  def handle_event("cancel", _params, socket) do
    if socket.assigns.dirty? do
      {:noreply, assign(socket, :dialog, :discard)}
    else
      {:noreply, push_navigate(socket, to: cancel_path(socket))}
    end
  end

  def handle_event("discard_changes", _params, socket) do
    {:noreply, push_navigate(socket, to: cancel_path(socket))}
  end

  def handle_event("close_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :dialog, :delete)}
  end

  def handle_event("open_tier_editor", _params, socket) do
    {:noreply,
     assign(socket,
       tier_dialog_open?: true,
       draft_tiers: normalize_tier_draft(socket.assigns.layout_state.tiers)
     )}
  end

  def handle_event("close_tier_editor", _params, socket) do
    {:noreply, assign(socket, :tier_dialog_open?, false)}
  end

  def handle_event("add_tier", _params, socket) do
    tiers = socket.assigns.draft_tiers || []

    tiers =
      if length(tiers) >= @max_tier_count do
        tiers
      else
        tiers ++ [new_tier(length(tiers))]
      end

    {:noreply, assign(socket, :draft_tiers, normalize_tier_draft(tiers))}
  end

  def handle_event("remove_tier", %{"id" => id}, socket) do
    tiers = socket.assigns.draft_tiers || []

    tiers =
      if length(tiers) <= 1 do
        tiers
      else
        Enum.reject(tiers, &(to_string(&1.id) == id))
      end

    {:noreply, assign(socket, :draft_tiers, normalize_tier_draft(tiers))}
  end

  def handle_event("move_tier", %{"id" => id, "direction" => direction}, socket) do
    tiers =
      socket.assigns.draft_tiers
      |> move_tier(id, direction)
      |> normalize_tier_draft()

    {:noreply, assign(socket, :draft_tiers, tiers)}
  end

  def handle_event("set_tier_label", %{"id" => id, "label" => label}, socket) do
    {:noreply,
     assign(socket, :draft_tiers, update_tier(socket.assigns.draft_tiers, id, %{label: label}))}
  end

  def handle_event("set_tier_color", %{"id" => id, "color" => color}, socket) do
    {:noreply,
     assign(socket, :draft_tiers, update_tier(socket.assigns.draft_tiers, id, %{color: color}))}
  end

  def handle_event("set_tier_label", %{"tier_id" => id, "label" => label}, socket) do
    handle_event("set_tier_label", %{"id" => id, "label" => label}, socket)
  end

  def handle_event("set_tier_label", %{"tier" => %{"tier_id" => id, "label" => label}}, socket) do
    handle_event("set_tier_label", %{"id" => id, "label" => label}, socket)
  end

  def handle_event("save_tier_draft", _params, socket) do
    tiers = normalize_tier_draft(socket.assigns.draft_tiers)
    tier_ids = MapSet.new(Enum.map(tiers, & &1.id))

    selected_items =
      Enum.map(socket.assigns.selected_items, fn item ->
        if is_nil(item.tier_id) or MapSet.member?(tier_ids, item.tier_id) do
          item
        else
          %{item | tier_id: nil, tier_position: nil}
        end
      end)
      |> normalize_positions()

    layout_state = %{
      socket.assigns.layout_state
      | tiers: tiers,
        items: layout_items_from_selected(selected_items)
    }

    {:noreply,
     socket
     |> assign(:tier_dialog_open?, false)
     |> assign(:draft_tiers, tiers)
     |> assign(:tiers, tiers)
     |> assign(:selected_items, selected_items)
     |> assign(:layout_state, layout_state)
     |> mark_dirty()
     |> push_event("list_layout:set_tiers", %{tiers: tiers})}
  end

  def handle_event("open_mobile_search", _params, socket) do
    {:noreply, assign(socket, :mobile_search_open?, true)}
  end

  def handle_event("close_mobile_search", _params, socket) do
    {:noreply, assign(socket, :mobile_search_open?, false)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, assign_search(socket, query)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign_search(socket, query)}
  end

  def handle_event("add_vn", %{"id" => vn_id}, socket) do
    add_item_by_id(socket, vn_id)
  end

  def handle_event("add_item", %{"id" => vn_id}, socket) do
    add_item_by_id(socket, vn_id)
  end

  def handle_event("remove_vn", %{"id" => vn_id}, socket) do
    remove_item_by_id(socket, vn_id)
  end

  def handle_event("remove_item", %{"id" => vn_id}, socket) do
    remove_item_by_id(socket, vn_id)
  end

  def handle_event("move_vn", %{"id" => vn_id, "direction" => direction}, socket) do
    {:noreply, assign_items(socket, move_item(socket.assigns.selected_items, vn_id, direction))}
  end

  def handle_event("move_item", %{"index" => index, "direction" => direction}, socket) do
    items = socket.assigns.selected_items

    with {index, ""} <- Integer.parse(to_string(index)),
         %{id: vn_id} <- Enum.at(items, index) do
      {:noreply, assign_items(socket, move_item(items, vn_id, direction))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("layout_changed", payload, socket) do
    apply_layout_payload(payload, socket)
  end

  def handle_event("save_layout", payload, socket) do
    apply_layout_payload(payload, socket)
  end

  def handle_event("save", %{"list" => attrs}, socket) do
    form_attrs = Data.normalize_form_attrs(attrs)
    layout = layout_for_submit(socket, form_attrs)
    current_user = socket.assigns.current_user

    cond do
      layout.items == [] ->
        {:noreply,
         socket
         |> assign_form_attrs(attrs)
         |> assign(:item_error, "Add at least one VN to publish the list")
         |> put_flash(:error, "Add at least one VN to publish the list")}

      form_attrs.is_public and not Data.can_publish_public_lists?(current_user) ->
        {:noreply,
         socket
         |> assign_form_attrs(attrs)
         |> put_flash(:error, "Your public list privileges have been revoked")}

      true ->
        socket = assign(socket, :saving, true)

        case save_list(
               socket.assigns.live_action,
               socket.assigns.list,
               current_user,
               form_attrs,
               layout
             ) do
          {:ok, list, :created} ->
            {:noreply,
             socket
             |> put_flash(:info, "List created")
             |> push_navigate(to: show_path(current_user, list))}

          {:ok, list, :updated} ->
            socket =
              socket
              |> assign_form_attrs(attrs)
              |> assign(:list, list)
              |> assign(:layout_state, layout)
              |> assign(:saving, false)
              |> put_flash(:info, "List updated")

            {:noreply, push_navigate(socket, to: show_path(current_user, list))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign_form_attrs(attrs)
             |> assign(:saving, false)
             |> put_flash(:error, save_error_message(reason))}
        end
    end
  end

  def handle_event("delete", _params, socket) do
    socket = assign(socket, :deleting, true)

    with %{id: user_id} <- socket.assigns.current_user,
         %{id: list_id} <- socket.assigns.list,
         {:ok, true} <- Lists.delete_list(list_id, user_id) do
      {:noreply,
       socket
       |> put_flash(:info, "List deleted")
       |> push_navigate(to: profile_lists_path(socket))}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:deleting, false)
         |> put_flash(:error, "Could not delete this list")}
    end
  end

  defp add_item_by_id(socket, vn_id) do
    with nil <- find_item(socket.assigns.selected_items, vn_id),
         %VisualNovel{} = vn <- Repo.get(VisualNovel, vn_id) do
      item = item_from_vn(vn)

      {:noreply,
       socket
       |> assign_items(socket.assigns.selected_items ++ [item])
       |> assign(:mobile_search_open?, false)
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:item_error, nil)
       |> push_event("list_layout:add_item", %{item: island_item(item)})}
    else
      _ -> {:noreply, socket}
    end
  end

  defp remove_item_by_id(socket, vn_id) do
    items = Enum.reject(socket.assigns.selected_items, &(item_id(&1) == vn_id))
    {:noreply, assign_items(socket, items)}
  end

  defp apply_layout_payload(payload, socket) do
    layout =
      normalize_hook_layout(
        payload,
        socket.assigns.selected_items,
        socket.assigns.layout_state.tiers
      )

    items = reorder_items_from_layout(layout.items, socket.assigns.selected_items)

    {:noreply,
     socket
     |> assign(:layout_state, layout)
     |> assign(:selected_items, items)
     |> assign(:tiers, layout.tiers)
     |> mark_dirty()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-20 text-[rgb(var(--foreground-primary))]">
      <%= if @auth_required? do %>
        <section class="mx-auto grid max-w-[760px] gap-2 px-4 py-20">
          <h1 class="text-2xl font-semibold">Sign in to create lists</h1>
          <p class="text-sm text-[rgb(var(--foreground-secondary))]">
            Sign in to create and edit visual novel lists.
          </p>
        </section>
      <% else %>
        <%= if @not_found? do %>
          <NotFoundPage.not_found_page variant={:overlay} />
        <% else %>
          <FormComponents.mobile_navbar
            title={if @live_action == :edit, do: "Edit List", else: "New List"}
            edit_mode={@live_action == :edit}
            saving={@saving}
            deleting={@deleting}
            save_disabled={@selected_items == []}
          />

          <FormComponents.mobile_search_overlay
            show={@mobile_search_open?}
            query={@search_query}
            results={@search_results}
            error={@search_error}
            loading={@searching?}
          />

          <FormComponents.confirm_dialog dialog={@dialog} deleting={@deleting} />
          <FormComponents.tier_dialog open={@tier_dialog_open?} tiers={@draft_tiers} />

          <section
            id="list-form-editor"
            phx-hook="MobileSearchHistory"
            data-mobile-search-open={to_string(@mobile_search_open?)}
            class="mx-auto flex max-w-[988px] flex-col px-4 pt-16 pb-8 md:px-8 lg:px-0 lg:pt-10 lg:pb-16"
          >
            <section>
              <div class="mb-0 hidden items-baseline justify-between lg:flex">
                <h3 class="text-[30px] leading-[38px] font-semibold text-[rgb(var(--foreground-primary))]">
                  {if @live_action == :edit, do: "Edit List", else: "New list"}
                </h3>
                <button
                  :if={@live_action == :edit}
                  type="button"
                  phx-click="confirm_delete"
                  disabled={@saving or @deleting}
                  class="text-sm font-normal text-[rgb(var(--foreground-secondary))] transition-colors hover:text-red-500 disabled:opacity-50"
                >
                  Delete list
                </button>
              </div>
              <div class="mt-3 mb-5 hidden h-px bg-[rgb(var(--border-divider))] lg:block"></div>

              <.form
                id="list-form"
                for={@form}
                phx-change="validate"
                phx-submit="save"
                phx-hook="UnsavedChanges"
                data-dirty={to_string(@dirty?)}
                class="text-[rgb(var(--foreground-primary))]"
              >
                <FormComponents.metadata_fields form={@form} values={@form_attrs} />
              </.form>
            </section>

            <div class="invisible h-0"></div>
            <div class="sticky -top-10 z-20 bg-[rgb(var(--surface-base))]">
              <div class="mt-6 mb-4 hidden h-px scroll-mt-[92px] bg-white/5 lg:block"></div>
              <div class="mb-3 hidden items-center justify-between gap-3 lg:flex">
                <KaguyaWeb.SharedComponents.Search.vn_select_search
                  id="desktop-list-vn-search"
                  select_event="add_item"
                  page_size={5}
                  placeholder="Search visual novels…"
                  class="flex-1"
                  popover_class="lg:!top-[48px] lg:!left-0 lg:!max-w-[500px] lg:rounded-t-none lg:border-t-0"
                />
                <div class="flex shrink-0 items-center gap-2">
                  <button
                    :if={@form_attrs["display_mode"] == "tier"}
                    id="list-form-desktop-tier-settings"
                    type="button"
                    phx-click="open_tier_editor"
                    class="flex h-11 items-center justify-center rounded-[8px] bg-[rgb(var(--surface-elevated))] px-3 text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
                    aria-label="Customize tiers"
                  >
                    <FormComponents.icon name={:settings} class="size-4" />
                  </button>
                  <button
                    id="list-form-desktop-cancel"
                    type="button"
                    phx-click="cancel"
                    disabled={@saving}
                    class="flex h-11 items-center rounded-[8px] bg-[rgb(var(--surface-elevated))] px-[18px] py-[11px] text-base font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-white/8 disabled:opacity-50"
                  >
                    Cancel
                  </button>
                  <button
                    id="list-form-desktop-save"
                    type="submit"
                    form="list-form"
                    disabled={@saving or @selected_items == []}
                    class="flex h-11 items-center rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-[18px] py-[11px] text-base font-normal text-[rgb(var(--button-text-on-brand))] transition hover:bg-[rgb(var(--button-background-brand-hover))] disabled:opacity-50"
                  >
                    {if @saving, do: "Saving...", else: "Save"}
                  </button>
                </div>
              </div>
              <p :if={@item_error} role="alert" class="mt-2 text-sm font-medium text-[#E5484D]">
                {@item_error}
              </p>
            </div>

            <section class="flex flex-1 flex-col gap-5">
              <%= if @selected_items == [] do %>
                <FormComponents.item_surface
                  items={@selected_items}
                  tiers={@tiers}
                  display_mode={@form_attrs["display_mode"]}
                  is_ranked={truthy?(@form_attrs["is_ranked"])}
                  item_error={@item_error}
                />
              <% else %>
                <p class="-mb-1 text-xs text-[rgb(var(--foreground-tertiary))]">
                  Drag to reorder
                </p>
                <div
                  id="list-layout-island"
                  phx-hook="ListLayoutIsland"
                  phx-update="ignore"
                  data-layout={island_layout_json(@layout_state, @selected_items, @form_attrs)}
                  data-island-src={~p"/assets/js/list_layout_island.js"}
                  data-emit-initial="false"
                  class="lg:min-h-[65vh]"
                >
                  <FormComponents.item_surface
                    items={@selected_items}
                    tiers={@tiers}
                    display_mode={@form_attrs["display_mode"]}
                    is_ranked={truthy?(@form_attrs["is_ranked"])}
                    item_error={nil}
                  />
                </div>

                <button
                  type="button"
                  phx-click="open_mobile_search"
                  class="sticky bottom-6 mt-auto flex size-14 items-center justify-center self-end rounded-full bg-[rgb(var(--button-background-brand-default))] text-[rgb(var(--button-text-on-brand))] shadow-2xl transition hover:bg-[rgb(var(--button-background-brand-hover))] lg:hidden"
                  aria-label="Add visual novel"
                >
                  <FormComponents.icon name={:plus} class="size-6" />
                </button>
              <% end %>
            </section>
          </section>
        <% end %>
      <% end %>
    </main>
    """
  end

  defp load_editor(socket, params, current_user) do
    case socket.assigns.live_action do
      :new ->
        payload = Data.new_form_payload(current_user)
        assign_payload(socket, payload, "New list · Kaguya")

      :edit ->
        case Data.load_editor_page(params["username"], params["slug"], current_user) do
          {:ok, payload} ->
            assign_payload(socket, payload, "Edit #{payload.list.name} · Kaguya")

          {:error, _reason} ->
            socket |> assign(:not_found?, true) |> assign(:page_title, "List not found · Kaguya")
        end
    end
  end

  defp assign_payload(socket, payload, page_title) do
    selected_items = payload.visual_novels |> normalize_editor_items() |> normalize_positions()
    tiers = normalize_tiers(payload.tiers)

    layout = %{
      display_mode: payload.layout.display_mode || payload.list.display_mode || "grid",
      tiers: normalize_tiers(payload.layout.tiers || tiers),
      items: layout_items_from_selected(selected_items)
    }

    socket =
      socket
      |> assign(:auth_required?, false)
      |> assign(:not_found?, false)
      |> assign(:page_title, page_title)
      |> assign(:list, Map.get(payload, :raw_list))
      |> assign(:tiers, tiers)
      |> assign(:layout_state, layout)
      |> assign(:selected_items, selected_items)
      |> assign(:form_attrs, attrs_from_list(payload.list))
      |> assign(:item_error, nil)
      |> put_form()

    assign(socket, initial_signature: editor_signature(socket), dirty?: false)
  end

  defp assign_form_attrs(socket, attrs) do
    existing = socket.assigns.form_attrs

    normalized =
      %{
        "name" => Map.get(attrs, "name", Map.get(existing, "name", "")),
        "description" => Map.get(attrs, "description", Map.get(existing, "description", "")),
        "is_public" => truthy?(Map.get(attrs, "is_public", Map.get(existing, "is_public", true))),
        "is_ranked" =>
          truthy?(Map.get(attrs, "is_ranked", Map.get(existing, "is_ranked", false))),
        "display_mode" =>
          normalize_display_mode(
            Map.get(attrs, "display_mode", Map.get(existing, "display_mode", "grid"))
          )
      }

    socket
    |> assign(:form_attrs, normalized)
    |> put_form()
    |> mark_dirty()
  end

  defp assign_items(socket, items) do
    items = normalize_positions(items)
    layout = %{socket.assigns.layout_state | items: layout_items_from_selected(items)}

    socket
    |> assign(:selected_items, items)
    |> assign(:layout_state, layout)
    |> mark_dirty()
  end

  defp mark_dirty(%{assigns: %{initial_signature: nil}} = socket) do
    assign(socket, :dirty?, false)
  end

  defp mark_dirty(socket) do
    assign(socket, :dirty?, editor_signature(socket) != socket.assigns.initial_signature)
  end

  defp editor_signature(socket) do
    form_attrs = socket.assigns.form_attrs
    layout_state = socket.assigns.layout_state

    %{
      form: %{
        name: Map.get(form_attrs, "name", "") |> to_string(),
        description: Map.get(form_attrs, "description", "") |> to_string(),
        is_public: truthy?(Map.get(form_attrs, "is_public", true)),
        is_ranked: truthy?(Map.get(form_attrs, "is_ranked", false)),
        display_mode: normalize_display_mode(Map.get(form_attrs, "display_mode", "grid"))
      },
      tiers:
        layout_state.tiers
        |> normalize_tiers()
        |> Enum.map(&{&1.id, &1.label, &1.color, &1.position}),
      items:
        socket.assigns.selected_items
        |> layout_items_from_selected()
        |> Enum.map(&{&1.visual_novel_id, &1.position, &1.tier_id, &1.tier_position})
    }
  end

  defp set_form_flag(socket, field, value) do
    socket =
      socket
      |> assign_form_attrs(%{field => value})

    if field == "is_ranked" do
      push_event(socket, "list_layout:set_ranked", %{value: value})
    else
      socket
    end
  end

  defp update_tier(tiers, id, attrs) do
    tiers
    |> Enum.map(fn tier ->
      if to_string(tier.id) == id do
        %{
          tier
          | label: normalize_tier_label(Map.get(attrs, :label, tier.label), tier.position),
            color: normalize_tier_color(Map.get(attrs, :color, tier.color), tier.position)
        }
      else
        tier
      end
    end)
    |> normalize_tier_draft()
  end

  defp move_tier(tiers, id, direction) when direction in ["up", "down"] do
    tiers = tiers || []
    from_index = Enum.find_index(tiers, &(to_string(&1.id) == id))

    with index when is_integer(index) <- from_index,
         to_index <- index + if(direction == "up", do: -1, else: 1),
         true <- to_index >= 0 and to_index < length(tiers) do
      tier = Enum.at(tiers, index)

      tiers
      |> List.delete_at(index)
      |> List.insert_at(to_index, tier)
    else
      _ -> tiers
    end
  end

  defp move_tier(tiers, _id, _direction), do: tiers || []

  defp normalize_tier_draft(tiers) do
    tiers
    |> Enum.take(@max_tier_count)
    |> Enum.with_index()
    |> Enum.map(fn {tier, index} ->
      %{
        id: tier_field(tier, :id) || new_tier_id(),
        label: normalize_tier_label(tier_field(tier, :label), index + 1),
        color: normalize_tier_color(tier_field(tier, :color), index + 1),
        position: index + 1
      }
    end)
  end

  defp new_tier(index) do
    preset = Enum.at(Data.default_tiers(), index)

    %{
      id: new_tier_id(),
      label: (preset && preset.label) || "Tier #{index + 1}",
      color:
        (preset && preset.color) ||
          Enum.at(@tier_color_options, rem(index, length(@tier_color_options))),
      position: index + 1
    }
  end

  defp new_tier_id, do: "tier-" <> Ecto.UUID.generate()

  defp normalize_tier_label(value, position) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> case do
      "" -> default_tier_label(position)
      label -> String.slice(label, 0, 24)
    end
  end

  defp default_tier_label(position) do
    case Enum.at(Data.default_tiers(), position - 1) do
      %{label: label} -> label
      _ -> "Tier #{position}"
    end
  end

  defp normalize_tier_color(color, position) do
    color = to_string(color || "")

    if color in @tier_color_options or Regex.match?(~r/^#[0-9a-fA-F]{6}$/, color) do
      color
    else
      Enum.at(@tier_color_options, rem(max(position - 1, 0), length(@tier_color_options)))
    end
  end

  defp assign_search(socket, query) do
    case search_results(query, socket.assigns.current_user) do
      {:ok, results} ->
        socket
        |> assign(:search_query, query)
        |> assign(:search_results, results)
        |> assign(:search_error, nil)

      {:error, message} ->
        socket
        |> assign(:search_query, query)
        |> assign(:search_results, [])
        |> assign(:search_error, message)
    end
  end

  defp search_results(query, current_user) do
    trimmed = String.trim(query || "")

    if trimmed == "" do
      {:ok, []}
    else
      case Data.search_visual_novels(trimmed, current_user, page: 1, page_size: @search_page_size) do
        {:ok, %{items: items}} -> {:ok, Enum.map(items, &search_result_item/1)}
        _ -> {:error, "Search is temporarily unavailable"}
      end
    end
  end

  defp save_list(:new, _existing_list, current_user, form_attrs, layout) do
    case Lists.create_list_with_layout(current_user.id, form_attrs, layout) do
      {:ok, list} -> {:ok, list, :created}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_list(:edit, existing_list, current_user, form_attrs, layout) do
    case Lists.update_list_with_layout(existing_list.id, current_user.id, form_attrs, layout) do
      {:ok, list} -> {:ok, list, :updated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp layout_for_submit(socket, form_attrs) do
    display_mode =
      Map.get(form_attrs, :display_mode, socket.assigns.layout_state.display_mode || "grid")

    %{
      display_mode: display_mode,
      tiers: socket.assigns.layout_state.tiers || Data.default_tiers(),
      items: layout_items_from_selected(socket.assigns.selected_items)
    }
  end

  defp normalize_hook_layout(payload, _selected_items, existing_tiers) do
    tiers = normalize_hook_tiers(Map.get(payload, "tiers", []), existing_tiers)

    %{
      display_mode: Map.get(payload, "displayMode") || Map.get(payload, "display_mode") || "grid",
      tiers: tiers,
      items:
        Enum.map(Map.get(payload, "items", []), fn item ->
          %{
            visual_novel_id: Map.get(item, "visualNovelId") || Map.get(item, "visual_novel_id"),
            position: Map.get(item, "position") || 1,
            tier_id: Map.get(item, "tierId") || Map.get(item, "tier_id"),
            tier_position: Map.get(item, "tierPosition") || Map.get(item, "tier_position")
          }
        end)
    }
  end

  defp normalize_hook_tiers([], existing_tiers), do: existing_tiers

  defp normalize_hook_tiers(tiers, _existing_tiers) do
    Enum.map(tiers, fn tier ->
      %{
        id: Map.get(tier, "id") || Map.get(tier, :id),
        label: Map.get(tier, "label") || Map.get(tier, :label),
        color: Map.get(tier, "color") || Map.get(tier, :color),
        position: Map.get(tier, "position") || Map.get(tier, :position)
      }
    end)
  end

  defp reorder_items_from_layout(layout_items, selected_items) do
    item_map = Map.new(selected_items, &{item_id(&1), &1})

    layout_items
    |> Enum.sort_by(&{&1.position || 0, &1.tier_position || 0})
    |> Enum.flat_map(fn item ->
      case Map.fetch(item_map, item.visual_novel_id) do
        {:ok, selected} ->
          [
            %{
              selected
              | position: item.position,
                tier_id: item.tier_id,
                tier_position: item.tier_position
            }
          ]

        :error ->
          []
      end
    end)
    |> normalize_positions()
  end

  defp layout_items_from_selected(items) do
    Enum.map(items, fn item ->
      %{
        visual_novel_id: item_id(item),
        position: item.position,
        tier_id: item.tier_id,
        tier_position: item.tier_position
      }
    end)
  end

  defp normalize_positions(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, position} -> %{item | position: position} end)
  end

  defp move_item(items, vn_id, direction) do
    index = Enum.find_index(items, &(item_id(&1) == vn_id))

    cond do
      is_nil(index) -> items
      direction == "up" and index > 0 -> swap_items(items, index, index - 1)
      direction == "down" and index < length(items) - 1 -> swap_items(items, index, index + 1)
      true -> items
    end
  end

  defp swap_items(items, left, right) do
    left_item = Enum.at(items, left)
    right_item = Enum.at(items, right)

    items
    |> List.replace_at(left, right_item)
    |> List.replace_at(right, left_item)
  end

  defp find_item(items, vn_id), do: Enum.find(items, &(item_id(&1) == vn_id))
  defp item_id(%{id: id}) when is_binary(id), do: id
  defp item_id(item), do: get_in(item, [:visual_novel, :id])

  defp item_from_vn(vn) do
    nsfw = Map.get(vn, :is_image_nsfw, false)
    suggestive = Map.get(vn, :is_image_suggestive, false)

    visual_novel = %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: VisualNovels.build_image_urls(vn),
      is_image_nsfw: nsfw,
      is_image_suggestive: suggestive,
      my_reading_status: nil
    }

    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      images: visual_novel.images,
      is_image_nsfw: nsfw,
      is_image_suggestive: suggestive,
      position: 0,
      tier_id: nil,
      tier_position: nil,
      visual_novel: visual_novel
    }
  end

  defp normalize_editor_items(items) do
    Enum.map(items, &editor_item/1)
  end

  defp editor_item(%{visual_novel: vn} = item) do
    visual_novel = normalize_visual_novel_map(vn)

    %{
      id: visual_novel.id,
      slug: visual_novel.slug,
      title: visual_novel.title,
      images: visual_novel.images,
      position: item.position || 0,
      tier_id: item.tier_id,
      tier_position: item.tier_position,
      visual_novel: visual_novel
    }
  end

  defp editor_item(%VisualNovel{} = vn), do: item_from_vn(vn)

  defp search_result_item(item) do
    %{
      id: Map.get(item, :id) || Map.get(item, "id"),
      slug: Map.get(item, :slug) || Map.get(item, "slug"),
      title: Map.get(item, :title) || Map.get(item, "title"),
      images: Map.get(item, :images) || Map.get(item, "images") || %{},
      image_url: Map.get(item, :image_url) || Map.get(item, "image_url"),
      producers: Map.get(item, :producers) || Map.get(item, "producers") || [],
      is_image_nsfw: Map.get(item, :is_image_nsfw) || Map.get(item, "is_image_nsfw") || false,
      is_image_suggestive:
        Map.get(item, :is_image_suggestive) || Map.get(item, "is_image_suggestive") || false
    }
  end

  defp normalize_visual_novel_map(%{} = vn) do
    %{
      id: Map.get(vn, :id),
      slug: Map.get(vn, :slug),
      title: Map.get(vn, :title),
      images: Map.get(vn, :images) || %{},
      is_image_nsfw: Map.get(vn, :is_image_nsfw, false),
      is_image_suggestive: Map.get(vn, :is_image_suggestive, false),
      my_reading_status: Map.get(vn, :my_reading_status)
    }
  end

  defp island_layout_json(layout_state, selected_items, form_attrs) do
    %{
      display_mode: Map.get(form_attrs, "display_mode", layout_state.display_mode || "grid"),
      is_ranked: truthy?(Map.get(form_attrs, "is_ranked", false)),
      tiers: normalize_tiers(layout_state.tiers),
      items: Enum.map(selected_items, &island_item/1)
    }
    |> Jason.encode!()
  end

  defp island_item(item) do
    visual_novel = item.visual_novel

    %{
      id: item_id(item),
      visual_novel_id: item_id(item),
      title: item.title,
      slug: item.slug,
      images: item.images || %{},
      position: item.position,
      tier_id: item.tier_id,
      tier_position: item.tier_position,
      visual_novel: visual_novel
    }
  end

  defp normalize_tiers([]), do: Data.default_tiers()
  defp normalize_tiers(nil), do: Data.default_tiers()

  defp normalize_tiers(tiers) do
    tiers
    |> Enum.map(fn tier ->
      %{
        id: Map.get(tier, :id) || Map.get(tier, "id"),
        label: Map.get(tier, :label) || Map.get(tier, "label"),
        color: Map.get(tier, :color) || Map.get(tier, "color"),
        position: normalize_tier_position(Map.get(tier, :position) || Map.get(tier, "position"))
      }
    end)
    |> Enum.with_index()
    |> Enum.sort_by(fn {tier, index} -> {tier.position || index + 1, index} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp tier_field(tier, field) when is_map(tier) do
    Map.get(tier, field) || Map.get(tier, to_string(field))
  end

  defp tier_field(_tier, _field), do: nil

  defp normalize_tier_position(value) when is_integer(value) and value > 0, do: value

  defp normalize_tier_position(value) when is_binary(value) do
    case Integer.parse(value) do
      {position, ""} when position > 0 -> position
      _ -> nil
    end
  end

  defp normalize_tier_position(_value), do: nil

  defp normalize_display_mode("tier"), do: "tier"
  defp normalize_display_mode(:tier), do: "tier"
  defp normalize_display_mode(_mode), do: "grid"

  defp put_form(socket) do
    assign(socket, :form, to_form(socket.assigns.form_attrs, as: :list))
  end

  defp cancel_path(%{
         assigns: %{live_action: :edit, current_user: %{username: username}, list: %{slug: slug}}
       }) do
    "/@#{username}/list/#{slug}"
  end

  defp cancel_path(%{assigns: %{current_user: %{username: username}}}), do: "/@#{username}/lists"
  defp cancel_path(_socket), do: "/lists"

  defp profile_lists_path(%{assigns: %{current_user: %{username: username}}}),
    do: "/@#{username}/lists"

  defp profile_lists_path(_socket), do: "/lists"

  defp show_path(%{username: username}, %{slug: slug}), do: "/@#{username}/list/#{slug}"

  defp attrs_from_list(list) do
    %{
      "name" => Map.get(list, :name, ""),
      "description" => Map.get(list, :description, ""),
      "is_public" => Map.get(list, :is_public, true),
      "is_ranked" => Map.get(list, :is_ranked, false),
      "display_mode" => normalize_display_mode(Map.get(list, :display_mode, "grid"))
    }
  end

  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_value), do: false

  defp save_error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end

  defp save_error_message(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp save_error_message(_reason), do: "Could not save this list"

  defp auth_page_title(:new), do: "Sign in required · Kaguya"
  defp auth_page_title(:edit), do: "Sign in required · Kaguya"

  defp current_user_from_session(%{"current_user_id" => user_id}) when is_binary(user_id) do
    case Users.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp current_user_from_session(_session), do: nil
end

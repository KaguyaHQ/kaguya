defmodule KaguyaWeb.AccountLive.EditProfile do
  use KaguyaWeb, :live_view
  use KaguyaWeb.ImageCropperHandlers

  import Ecto.Query
  import KaguyaWeb.UI.Button, only: [button: 1]
  import KaguyaWeb.UI.ImageCropper, only: [image_cropper: 1]

  alias Kaguya.Characters.{Character, CharacterFavorite, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Uploads
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.Components.Shared.SocialIcons
  alias KaguyaWeb.Components.VN.Cards
  alias KaguyaWeb.ListLive.Data, as: ListData

  @top_favorites_limit 4
  @search_page_size 8
  @empty_search %{
    open: false,
    type: nil,
    step: :vn_search,
    query: "",
    results: [],
    characters: [],
    selected_vn: nil,
    error: nil
  }

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      with {:ok, user} <- Users.get_user(socket.assigns.current_user.id) do
        {:ok,
         socket
         |> assign(:page_title, "Edit Profile - Kaguya")
         |> assign(:meta_description, "Edit profile")
         |> assign(KaguyaWeb.SEO.noindex())
         |> assign_user_state(user)
         |> assign(:search, @empty_search)
         |> assign(:upload_error, nil)
         |> assign(:profile_image_uploads_in_progress, MapSet.new())
         |> assign(:pending_avatar_upload_id, nil)
         |> assign(:pending_banner_upload_id, nil)
         |> assign(:delete_banner?, false)}
      else
        _ -> {:ok, redirect(socket, to: ~p"/login")}
      end
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("validate_profile", %{"profile" => params}, socket) do
    {:noreply, assign(socket, :form, form_for_params(params))}
  end

  def handle_event("save_profile", %{"profile" => params}, socket) do
    if profile_image_uploading?(socket) do
      {:noreply,
       socket
       |> assign(:form, form_for_params(params))
       |> assign(:upload_error, "Please wait for your profile image to finish uploading.")}
    else
      save_profile(socket, params)
    end
  end

  def handle_event(
        "reorder_favorite",
        %{"kind" => raw_kind, "from" => from, "to" => to},
        socket
      ) do
    with {:ok, type} <- parse_type(raw_kind),
         {:ok, from_idx} <- cast_index(from),
         {:ok, to_idx} <- cast_index(to) do
      {:noreply, update_draft(socket, type, &move(&1, from_idx, to_idx))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_favorite", %{"type" => raw_type, "id" => id}, socket) do
    with {:ok, type} <- parse_type(raw_type) do
      {:noreply,
       update_draft(socket, type, fn favorites ->
         Enum.reject(favorites, fn favorite -> to_string(favorite.id) == to_string(id) end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_favorite_search", %{"type" => raw_type}, socket) do
    with {:ok, type} <- parse_type(raw_type),
         true <- length(Map.fetch!(socket.assigns.draft_favorites, type)) < @top_favorites_limit do
      {:noreply,
       assign(socket, :search, %{
         @empty_search
         | open: true,
           type: type,
           step: :vn_search
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_favorite_search", _params, socket) do
    {:noreply, assign(socket, :search, @empty_search)}
  end

  def handle_event("delete_banner", _params, socket) do
    {:noreply,
     socket
     |> assign(:profile_user, Map.put(socket.assigns.profile_user, :banner_url, nil))
     |> Phoenix.Component.update(:profile_image_uploads_in_progress, &MapSet.delete(&1, :banner))
     |> assign(:pending_banner_upload_id, nil)
     |> assign(:delete_banner?, true)}
  end

  def handle_event("search_favorite", %{"favorite_search" => %{"query" => query}}, socket) do
    {:noreply, assign_search(socket, query)}
  end

  def handle_event("select_character_search_vn", %{"id" => vn_id}, socket) do
    with %{type: :characters} <- socket.assigns.search,
         %VisualNovel{} = vn <- VisualNovels.get_visual_novel(vn_id) do
      {:noreply,
       assign(socket, :search, %{
         @empty_search
         | open: true,
           type: :characters,
           step: :character_select,
           selected_vn: decorate_vn(vn),
           characters: load_characters_for_vn(vn.id, draft_ids(socket, :characters))
       })}
    else
      _ ->
        {:noreply,
         assign(socket, :search, Map.put(socket.assigns.search, :error, "Something went wrong"))}
    end
  end

  def handle_event("back_to_character_vn_search", _params, socket) do
    {:noreply,
     assign(socket, :search, %{
       @empty_search
       | open: true,
         type: :characters,
         step: :vn_search
     })}
  end

  def handle_event("add_favorite", %{"type" => raw_type, "id" => id}, socket) do
    with {:ok, type} <- parse_type(raw_type) do
      add_favorite(socket, type, id)
    else
      _ -> {:noreply, socket}
    end
  end

  def __image_cropper_uploaded__(socket, image_type, upload_id)
      when image_type in [:avatar, :banner] do
    send(self(), {:image_uploaded, image_type, upload_id})
    {:noreply, socket}
  end

  def __image_cropper_uploaded__(socket, image_type, upload_id) do
    super(socket, image_type, upload_id)
  end

  def __image_cropper_upload_failed__(socket, image_type, message)
      when image_type in [:avatar, :banner] do
    send(self(), {:image_upload_failed, image_type, message})
    {:noreply, socket}
  end

  def __image_cropper_upload_failed__(socket, image_type, message) do
    super(socket, image_type, message)
  end

  @impl true
  def handle_info({:image_cropped, image_type}, socket) when image_type in [:avatar, :banner] do
    {:noreply,
     socket
     |> Phoenix.Component.update(:profile_image_uploads_in_progress, &MapSet.put(&1, image_type))
     |> assign(:upload_error, nil)}
  end

  def handle_info({:image_uploaded, :avatar, upload_id}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.update(:profile_image_uploads_in_progress, &MapSet.delete(&1, :avatar))
     |> assign(:pending_avatar_upload_id, upload_id)
     |> assign(:upload_error, nil)}
  end

  def handle_info({:image_uploaded, :banner, upload_id}, socket) do
    {:noreply,
     socket
     |> Phoenix.Component.update(:profile_image_uploads_in_progress, &MapSet.delete(&1, :banner))
     |> assign(:pending_banner_upload_id, upload_id)
     |> assign(:delete_banner?, false)
     |> assign(:upload_error, nil)}
  end

  def handle_info({:image_upload_failed, image_type, message}, socket)
      when image_type in [:avatar, :banner] do
    {:noreply,
     socket
     |> Phoenix.Component.update(
       :profile_image_uploads_in_progress,
       &MapSet.delete(&1, image_type)
     )
     |> clear_pending_profile_image(image_type)
     |> assign(:upload_error, message)}
  end

  def handle_info({:image_uploaded, _image_type, _upload_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.image_cropper id="edit-profile-avatar-cropper" variant="profile" image_type={:avatar} />
    <.image_cropper id="edit-profile-banner-cropper" variant="cover" image_type={:banner} />

    <.form
      for={@form}
      id="profile-edit-form"
      phx-change="validate_profile"
      phx-submit="save_profile"
      class="mx-auto max-w-[988px] scroll-smooth pb-[120px] sm:pt-10 sm:pb-[160px] sm:max-lg:mx-5 lg:px-6"
    >
      <h1 class="text-foreground-primary text-2xl font-semibold max-sm:hidden">
        Edit Profile
      </h1>

      <.profile_images user={@profile_user} />

      <p
        :if={@upload_error}
        role="alert"
        class="mt-3 px-5 text-sm text-[rgb(var(--foreground-error))] sm:px-8 lg:px-0"
      >
        {@upload_error}
      </p>

      <div class="max-lg:space-y-8 max-sm:mt-8 sm:max-lg:mt-9 lg:mt-8 lg:grid lg:grid-cols-[minmax(0,45fr)_minmax(0,50fr)] lg:items-stretch lg:gap-x-[60px]">
        <div class="flex flex-col space-y-8">
          <.basic_information form={@form} />
          <.online_presence form={@form} />
        </div>

        <div class="space-y-8">
          <.favorite_editor
            id="favorite-visual-novels"
            title="Favorite Visual Novels"
            type={:visual_novels}
            items={@draft_favorites.visual_novels}
            tail_count={tail_count(@favorite_vns)}
            username={@user.username}
          />
          <.favorite_editor
            id="favorite-characters"
            title="Favorite Characters"
            type={:characters}
            items={@draft_favorites.characters}
            tail_count={tail_count(@favorite_characters)}
            username={@user.username}
          />
        </div>
      </div>

      <div class="lg:border-border-divider flex items-center justify-end gap-3 px-5 py-6 max-sm:mt-6 max-sm:py-0 sm:px-8 sm:max-lg:mt-9 lg:mt-10 lg:border-t lg:px-0">
        <.link
          navigate={profile_path(@user)}
          class="hover:text-foreground-primary text-foreground-secondary text-style-body2Medium inline-flex h-10 items-center rounded-[6px] px-6 transition-colors"
        >
          Cancel
        </.link>

        <.button
          type="submit"
          variant="brand"
          size="small"
          disabled={profile_image_uploading?(@profile_image_uploads_in_progress)}
          phx-disable-with="Saving..."
        >
          <%= if profile_image_uploading?(@profile_image_uploads_in_progress) do %>
            Uploading image…
          <% else %>
            Save changes
          <% end %>
        </.button>
      </div>
    </.form>

    <.search_dialog search={@search} />
    """
  end

  attr :user, :map, required: true

  defp profile_images(assigns) do
    ~H"""
    <div class="relative max-sm:hidden sm:max-lg:mt-10 lg:mt-6">
      <div
        class="group relative h-[196px] w-full cursor-pointer overflow-hidden rounded-[4px]"
        phx-click={
          Phoenix.LiveView.JS.dispatch("kaguya:open-image-cropper",
            detail: %{id: "edit-profile-banner-cropper"}
          )
        }
      >
        <%= if @user.banner_url do %>
          <img
            id="edit-profile-banner-preview-desktop"
            phx-update="ignore"
            data-cropper-preview="banner"
            src={@user.banner_url}
            width="1080"
            height="196"
            sizes="1080px"
            alt="cover"
            class="h-[196px] w-full object-cover object-center"
          />
        <% else %>
          <img
            id="edit-profile-banner-preview-desktop"
            phx-update="ignore"
            data-cropper-preview="banner"
            src=""
            alt=""
            hidden
          />
          <div class="h-[196px] w-full bg-[rgb(30,32,34)]" />
        <% end %>

        <div class="pointer-events-none absolute inset-0 flex items-center justify-center gap-5 bg-black/50 px-4 text-sm font-medium text-white opacity-0 transition-opacity duration-300 group-hover:opacity-100">
          <div class="flex flex-col items-center justify-center gap-2 px-[18px] py-3">
            <Lucide.pencil class="size-5" aria-hidden />
            <span>Edit Banner</span>
          </div>

          <button
            :if={@user.banner_url != nil}
            type="button"
            data-cropper-skip
            phx-click={Phoenix.LiveView.JS.push("delete_banner")}
            class="pointer-events-auto flex cursor-pointer flex-col items-center justify-center gap-2 px-[18px] py-3"
          >
            <Lucide.trash_2 class="size-5" aria-hidden />
            <span>Delete Banner</span>
          </button>
        </div>
      </div>

      <div class="absolute top-[196px] left-6 z-10 -translate-y-1/2">
        <div
          class="group relative size-[100px] cursor-pointer overflow-hidden rounded-full shadow-[0_0_0_4px_rgb(var(--surface-base))]"
          phx-click={
            Phoenix.LiveView.JS.dispatch("kaguya:open-image-cropper",
              detail: %{id: "edit-profile-avatar-cropper"}
            )
          }
        >
          <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
            user={@user}
            size="size-[100px]"
            sizes="100px"
            class="object-center"
            fallback={:default_url}
            id="edit-profile-avatar-preview-desktop"
            phx-update="ignore"
            data-cropper-preview="avatar"
          />
          <div class="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition-opacity duration-300 group-hover:opacity-100">
            <Lucide.pencil class="size-5 text-white" aria-hidden />
          </div>
        </div>
      </div>

      <div class="h-[54px]" />
    </div>

    <div class="relative sm:hidden">
      <div class="relative h-[156px] w-full overflow-hidden">
        <%= if @user.banner_url do %>
          <img
            id="edit-profile-banner-preview-mobile"
            phx-update="ignore"
            data-cropper-preview="banner"
            src={@user.banner_url}
            width="390"
            height="156"
            sizes="390px"
            alt="cover"
            class="h-[156px] w-full object-cover object-center"
          />
        <% else %>
          <img
            id="edit-profile-banner-preview-mobile"
            phx-update="ignore"
            data-cropper-preview="banner"
            src=""
            alt=""
            hidden
          />
          <div class="h-[156px] w-full bg-[rgb(30,32,34)]" />
        <% end %>

        <div class="absolute top-3 right-3 flex items-center gap-2">
          <button
            type="button"
            phx-click={
              Phoenix.LiveView.JS.dispatch("kaguya:open-image-cropper",
                detail: %{id: "edit-profile-banner-cropper"}
              )
            }
            class="flex size-9 cursor-pointer items-center justify-center rounded-full bg-black/40 backdrop-blur-xs"
            aria-label="Edit banner"
          >
            <Lucide.pencil class="size-[18px] text-white/70" aria-hidden />
          </button>
          <button
            :if={@user.banner_url != nil}
            type="button"
            phx-click={Phoenix.LiveView.JS.push("delete_banner")}
            class="flex size-9 cursor-pointer items-center justify-center rounded-full bg-black/40 backdrop-blur-xs"
            aria-label="Delete banner"
          >
            <Lucide.trash_2 class="size-[18px] text-white/70" aria-hidden />
          </button>
        </div>
      </div>

      <div class="absolute top-[156px] left-4 z-10 -translate-y-1/2">
        <div
          class="relative size-[90px] cursor-pointer overflow-hidden rounded-full shadow-[0_0_0_4px_rgb(var(--surface-base))]"
          phx-click={
            Phoenix.LiveView.JS.dispatch("kaguya:open-image-cropper",
              detail: %{id: "edit-profile-avatar-cropper"}
            )
          }
        >
          <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
            user={@user}
            size="size-[90px]"
            sizes="90px"
            class="object-center"
            fallback={:default_url}
            id="edit-profile-avatar-preview-mobile"
            phx-update="ignore"
            data-cropper-preview="avatar"
          />
          <div class="pointer-events-none absolute top-1/2 left-1/2 flex size-9 -translate-1/2 items-center justify-center rounded-full bg-black/40 backdrop-blur-xs">
            <Lucide.pencil class="size-[18px] text-white/70" aria-hidden />
          </div>
        </div>
      </div>

      <div class="h-[49px]" />
    </div>
    """
  end

  attr :form, :map, required: true

  defp basic_information(assigns) do
    assigns =
      assign(assigns, :bio_length, assigns.form[:bio].value |> to_string() |> String.length())

    ~H"""
    <div
      id="basic-information"
      class="w-full scroll-mt-24 px-5 sm:p-8 lg:flex lg:flex-1 lg:flex-col lg:p-0"
    >
      <div class="flex w-full flex-col justify-between gap-4 sm:gap-7 lg:flex-1">
        <div class="gap-[18px] sm:flex sm:justify-between">
          <.input_field label="Display Name">
            <input
              name="profile[display_name]"
              value={@form[:display_name].value}
              placeholder="Arcueid"
              maxlength="36"
              class="border-border-divider focus-visible:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-12 w-full rounded-[6px] border px-4 py-[15px] text-sm transition-colors placeholder:text-sm focus-visible:outline-hidden sm:h-[46px] sm:px-3 sm:py-[14px] dark:bg-white/2 sm:dark:bg-white/1"
            />
          </.input_field>

          <.input_field label="Username" class="max-sm:mt-4">
            <input
              id="usernameInput"
              name="profile[username]"
              value={@form[:username].value}
              placeholder="arcueid"
              minlength="3"
              maxlength="30"
              class="border-border-divider focus-visible:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-12 w-full rounded-[6px] border px-4 py-[15px] text-sm transition-colors placeholder:text-sm focus-visible:outline-hidden sm:h-[46px] sm:px-3 sm:py-[13px] dark:bg-white/2 sm:dark:bg-white/1"
            />
          </.input_field>
        </div>

        <.input_field label="About Me" class="lg:flex lg:flex-1 lg:flex-col">
          <textarea
            name="profile[bio]"
            maxlength="250"
            placeholder="Write something about yourself…"
            class="border-border-divider custom-dropdown-scrollbar focus-visible:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-[120px] w-full resize-none rounded-[6px] border px-4 py-[15px] text-sm transition-colors placeholder:text-sm focus-visible:outline-hidden sm:h-[124px] sm:px-3 sm:py-[14px] lg:h-auto lg:min-h-[124px] lg:flex-1 dark:bg-white/2 sm:dark:bg-white/1"
          ><%= @form[:bio].value %></textarea>
          <span
            :if={@bio_length >= 200}
            class={[
              "ml-auto block self-end text-right text-xs font-normal",
              @bio_length > 250 && "text-red-400",
              @bio_length <= 250 && "text-foreground-secondary"
            ]}
          >
            {@bio_length}/250
          </span>
        </.input_field>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  defp online_presence(assigns) do
    ~H"""
    <div id="online-presence" class="w-full scroll-mt-24 px-5 sm:px-8 lg:px-0 lg:pt-0">
      <h3 class="text-foreground-secondary mb-3 text-xs font-medium tracking-[0.08em] uppercase">
        Links
      </h3>
      <div class="gap-[18px] sm:flex sm:justify-between">
        <.social_input
          name="profile[social_links][twitter]"
          value={@form[:twitter].value}
          placeholder="@handle"
          icon={:x}
        />
        <.social_input
          name="profile[social_links][website]"
          value={@form[:website].value}
          placeholder="https://"
          icon={:link}
          class="max-sm:mt-4"
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp input_field(assigns) do
    ~H"""
    <label class={["max-sm:space-y-3 sm:w-full", @class]}>
      <span class="lg:text-foreground-secondary sm:text-foreground-primary text-foreground-secondary block text-xs font-medium tracking-[0.08em] uppercase sm:text-sm sm:tracking-normal sm:normal-case lg:text-xs lg:tracking-[0.08em] lg:uppercase">
        {@label}
      </span>
      <span class="mt-3 block sm:mt-2">{render_slot(@inner_block)}</span>
    </label>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :icon, :atom, required: true
  attr :class, :any, default: nil

  defp social_input(assigns) do
    ~H"""
    <label class={["relative block sm:w-full", @class]}>
      <span class="text-foreground-primary/50 pointer-events-none absolute top-1/2 left-4 -translate-y-1/2">
        <SocialIcons.icon site={social_icon_site(@icon)} class="size-4" />
      </span>
      <input
        name={@name}
        value={@value}
        placeholder={@placeholder}
        type="text"
        class="border-border-divider focus-visible:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-12 w-full rounded-[6px] border py-[15px] pr-4 pl-11 text-sm transition-colors placeholder:text-sm focus-visible:outline-hidden sm:h-[46px] sm:py-[13px] dark:bg-white/2 sm:dark:bg-white/1"
      />
    </label>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :type, :atom, required: true
  attr :items, :list, required: true
  attr :tail_count, :integer, required: true
  attr :username, :string, default: nil

  defp favorite_editor(assigns) do
    assigns =
      assigns
      |> assign(:grid_id, "#{assigns.id}-grid")
      |> assign(:items_json, Jason.encode!(items_for_island(assigns.items, assigns.type)))

    ~H"""
    <div id={@id} class="w-full scroll-mt-24 px-5 sm:px-8 sm:pt-6 lg:px-0 lg:pt-0">
      <div class="mb-3 flex items-baseline justify-between">
        <h3 class="text-foreground-secondary text-xs font-medium tracking-[0.08em] uppercase">
          {@title}
        </h3>
        <span class="text-foreground-tertiary text-xs">Drag to reorder</span>
      </div>

      <p :if={@tail_count > 0 and @username} class="text-foreground-tertiary mb-3 text-xs">
        + {@tail_count} more not shown.
        <.link navigate={"/@#{@username}/favorites"} class="hover:text-foreground-secondary underline">
          Manage all
        </.link>
      </p>

      <div
        id={@grid_id}
        phx-hook="FavoritesDnd"
        phx-update="ignore"
        data-kind={@type}
        data-layout="edit_profile"
        data-limit="4"
        data-items={@items_json}
        data-island-src={~p"/assets/js/favorites_dnd_island.js"}
      >
      </div>
    </div>
    """
  end

  attr :search, :map, required: true

  defp search_dialog(assigns) do
    assigns =
      assigns
      |> assign(:open, Map.get(assigns.search, :open, false))
      |> assign(:type, Map.get(assigns.search, :type))
      |> assign(:step, Map.get(assigns.search, :step))
      |> assign(:query, Map.get(assigns.search, :query, ""))
      |> assign(:results, Map.get(assigns.search, :results, []))
      |> assign(:characters, Map.get(assigns.search, :characters, []))
      |> assign(:selected_vn, Map.get(assigns.search, :selected_vn))
      |> assign(:error, Map.get(assigns.search, :error))

    ~H"""
    <div
      :if={@open}
      class="fixed inset-0 z-100 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
      phx-window-keydown="close_favorite_search"
      phx-key="Escape"
    >
      <button
        type="button"
        phx-click="close_favorite_search"
        class="absolute inset-0 cursor-default"
        aria-label="Close favorites search"
      />

      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="favorite-search-title"
        class="relative flex max-h-[88vh] w-full max-w-[480px] flex-col overflow-hidden rounded-t-[16px] bg-[rgb(var(--surface-base))] shadow-2xl sm:rounded-[16px]"
      >
        <div class="flex items-center gap-2 px-6 pt-6 pr-12 pb-4">
          <button
            :if={@type == :characters and @step == :character_select}
            type="button"
            class="hover:bg-surface-menu-item-hover text-foreground-primary flex size-7 items-center justify-center rounded-full"
            phx-click="back_to_character_vn_search"
            aria-label="Back"
          >
            <Lucide.chevron_left class="size-5" aria-hidden />
          </button>
          <h2
            id="favorite-search-title"
            class="text-style-heading3Medium line-clamp-1 text-left text-[rgb(var(--foreground-primary))]"
          >
            {dialog_title(@type, @step, @selected_vn)}
          </h2>
        </div>

        <%= if @type == :visual_novels or @step == :vn_search do %>
          <div class="px-6 pb-6">
            <.form
              for={%{}}
              as={:favorite_search}
              id="favorite-search-form"
              phx-change="search_favorite"
              phx-submit="search_favorite"
              class="relative"
            >
              <.search_icon
                class="pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2 text-[rgb(var(--foreground-tertiary))]"
                aria-hidden
              />
              <input
                type="search"
                name="favorite_search[query]"
                value={@query}
                placeholder="Search visual novels"
                autocomplete="off"
                phx-debounce="350"
                class="text-style-body2Regular h-11 w-full rounded-full border-none bg-[rgb(var(--surface-elevated))] pr-4 pl-11 text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:ring-0 focus:outline-none"
                data-modal-initial-focus
              />
            </.form>
            <div class="mt-4 max-h-[320px] min-h-[280px] overflow-y-auto">
              <.search_message :if={@error} message="Something went wrong" />
              <div
                :if={!@error and String.trim(@query || "") == ""}
                class="h-[280px]"
                aria-hidden="true"
              />
              <.search_message
                :if={!@error and String.trim(@query || "") != "" and @results == []}
                message="No matches"
              />
              <div :if={!@error and @results != []} class="space-y-1">
                <.vn_search_row
                  :for={vn <- @results}
                  vn={vn}
                  select_event={
                    if(@type == :characters, do: "select_character_search_vn", else: "add_favorite")
                  }
                  type={@type}
                />
              </div>
            </div>
          </div>
        <% else %>
          <div class="px-6 pb-6">
            <div class="max-h-[400px] min-h-[320px] overflow-y-auto">
              <.search_message :if={@error} message="Something went wrong" />
              <.search_message :if={!@error and @characters == []} message="No characters found" />
              <div :if={!@error and @characters != []} class="grid grid-cols-3 gap-3 sm:grid-cols-4">
                <button
                  :for={character <- @characters}
                  type="button"
                  phx-click="add_favorite"
                  phx-value-type="characters"
                  phx-value-id={character.id}
                  class="group flex flex-col items-center rounded-lg p-2 transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:outline-none"
                >
                  <Cards.character_image
                    character={character}
                    sizes="(max-width: 640px) 90px, 110px"
                    class="aspect-2/3 w-full rounded-[8px] object-cover transition-all group-hover:ring-2 group-hover:ring-[rgb(var(--foreground-primary))]/50"
                    rounded="rounded-[8px]"
                  />
                  <span class="text-style-captionMedium mt-2 line-clamp-1 w-full text-center text-[rgb(var(--foreground-primary))]">
                    {character.name}
                  </span>
                  <span
                    :if={character[:role]}
                    class="text-style-captionRegular mt-1 text-[rgb(var(--foreground-tertiary))] uppercase"
                  >
                    {role_label(character[:role])}
                  </span>
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :message, :string, required: true

  defp search_message(assigns) do
    ~H"""
    <div class="text-style-body2Regular flex h-[280px] items-center justify-center text-[rgb(var(--foreground-tertiary))]">
      {@message}
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :select_event, :string, required: true
  attr :type, :atom, required: true

  defp vn_search_row(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@select_event}
      phx-value-type={@type}
      phx-value-id={@vn.id}
      class="flex w-full items-center gap-4 rounded-lg p-3 text-left transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:bg-[rgb(var(--surface-menu-item-hover))] focus-visible:outline-none"
    >
      <div class="h-[84px] w-14 shrink-0 overflow-hidden rounded-md bg-[rgb(var(--surface-elevated))]">
        <Cards.cover
          vn={@vn}
          sizes="56px"
          class="h-[84px] w-14 rounded-md object-cover"
          fallback_class="h-[84px] w-14 rounded-md"
        />
      </div>
      <span class="min-w-0 flex-1">
        <span class="text-style-body2Medium line-clamp-2 text-[rgb(var(--foreground-primary))]">
          {@vn.title}
        </span>
        <span
          :if={@vn[:producers]}
          class="text-style-captionRegular mt-1 line-clamp-1 text-[rgb(var(--foreground-tertiary))]"
        >
          {@vn.producers}
        </span>
      </span>
    </button>
    """
  end

  defp save_profile(socket, params) do
    user = socket.assigns.user

    attrs =
      params
      |> profile_attrs()
      |> Map.put(
        :favorite_visual_novels,
        merged_ids(socket.assigns.draft_favorites.visual_novels, user.favorite_visual_novels)
      )
      |> Map.put(
        :favorite_characters,
        merged_ids(socket.assigns.draft_favorites.characters, socket.assigns.character_ids)
      )
      |> maybe_delete_banner(socket.assigns.delete_banner?)

    case Users.update_user(user, attrs) do
      {:ok, updated} ->
        case commit_pending_profile_images(updated, socket.assigns) do
          {:ok, updated_with_images} ->
            {:noreply,
             socket
             |> put_flash(:info, "Profile updated successfully!")
             |> push_navigate(to: profile_path(updated_with_images))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign_user_state(updated)
             |> assign(:upload_error, reason)}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_changeset_error(changeset))}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, :upload_error, reason)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update profile. Please try again.")}
    end
  end

  defp commit_pending_profile_images(%User{} = user, assigns) do
    with :ok <- commit_pending_profile_image(:avatar, assigns.pending_avatar_upload_id, user.id),
         :ok <- commit_pending_profile_image(:banner, assigns.pending_banner_upload_id, user.id),
         {:ok, updated} <- Users.get_user(user.id) do
      {:ok, updated}
    else
      {:error, reason} -> {:error, error_to_string(reason)}
    end
  end

  defp commit_pending_profile_image(_type, nil, _user_id), do: :ok

  defp commit_pending_profile_image(type, upload_id, user_id) do
    case Uploads.process_profile_image_upload(upload_id, type, user_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp clear_pending_profile_image(socket, :avatar),
    do: assign(socket, :pending_avatar_upload_id, nil)

  defp clear_pending_profile_image(socket, :banner),
    do: assign(socket, :pending_banner_upload_id, nil)

  defp profile_image_uploading?(%{assigns: %{profile_image_uploads_in_progress: uploads}}) do
    profile_image_uploading?(uploads)
  end

  defp profile_image_uploading?(%MapSet{} = uploads), do: MapSet.size(uploads) > 0

  defp error_to_string(reason) when is_binary(reason), do: reason
  defp error_to_string(reason), do: inspect(reason)

  defp assign_user_state(socket, %User{} = user) do
    favorite_vns = load_favorite_vns(user.favorite_visual_novels)
    favorite_characters = load_favorite_characters(user.id)

    socket
    |> assign(:user, user)
    |> assign(:profile_user, profile_user(user))
    |> assign(:form, form_for_user(user))
    |> assign(:favorite_vns, favorite_vns)
    |> assign(:favorite_characters, favorite_characters)
    |> assign(:character_ids, Enum.map(favorite_characters, & &1.id))
    |> assign(:draft_favorites, %{
      visual_novels: Enum.take(favorite_vns, @top_favorites_limit),
      characters: Enum.take(favorite_characters, @top_favorites_limit)
    })
  end

  defp form_for_user(user) do
    social_links = Map.get(user, :social_links)

    form_for_params(%{
      "display_name" => Map.get(user, :display_name) || "",
      "username" => Map.get(user, :username) || "",
      "bio" => Map.get(user, :bio) || "",
      "website" => social_value(social_links, :website),
      "twitter" => social_value(social_links, :twitter)
    })
  end

  defp form_for_params(params) do
    social = Map.get(params, "social_links", %{})

    to_form(
      %{
        "display_name" => Map.get(params, "display_name") || "",
        "username" => Map.get(params, "username") || "",
        "bio" => Map.get(params, "bio") || "",
        "website" => Map.get(params, "website") || Map.get(social, "website") || "",
        "twitter" => Map.get(params, "twitter") || Map.get(social, "twitter") || ""
      },
      as: :profile
    )
  end

  defp profile_attrs(params) do
    social_links =
      params
      |> Map.get("social_links", %{})
      |> Map.take(~w(website twitter))
      |> Map.new(fn
        {"website", value} -> {"website", normalize_website(value)}
        {"twitter", value} -> {"twitter", normalize_twitter(value)}
      end)

    %{
      display_name: blank_to_nil(params["display_name"]),
      username: blank_to_nil(params["username"]),
      bio: blank_to_nil(params["bio"]),
      social_links: social_links
    }
  end

  defp maybe_delete_banner(attrs, true), do: Map.put(attrs, :banner_id, nil)
  defp maybe_delete_banner(attrs, _), do: attrs

  defp assign_search(socket, query) do
    search = socket.assigns.search

    if search.open and (search.type == :visual_novels or search.step == :vn_search) do
      case search_visual_novels(query, socket.assigns[:current_user]) do
        {:ok, results} ->
          assign(socket, :search, %{search | query: query, results: results, error: nil})

        :error ->
          assign(socket, :search, %{
            search
            | query: query,
              results: [],
              error: "Something went wrong"
          })
      end
    else
      socket
    end
  end

  defp search_visual_novels(query, viewer) do
    trimmed = String.trim(query || "")

    if trimmed == "" do
      {:ok, []}
    else
      case ListData.search_visual_novels(trimmed, viewer, page: 1, page_size: @search_page_size) do
        {:ok, %{items: items}} -> {:ok, Enum.map(items, &normalize_search_vn/1)}
        _ -> :error
      end
    end
  end

  defp add_favorite(socket, type, id) do
    cond do
      id in draft_ids(socket, type) ->
        {:noreply, assign(socket, :search, @empty_search)}

      length(Map.fetch!(socket.assigns.draft_favorites, type)) >= @top_favorites_limit ->
        {:noreply, assign(socket, :search, @empty_search)}

      true ->
        case load_favorite_item(type, id) do
          {:ok, item} ->
            {:noreply,
             socket
             |> update_draft(type, &(&1 ++ [item]))
             |> assign(:search, @empty_search)}

          :error ->
            {:noreply,
             assign(
               socket,
               :search,
               Map.put(socket.assigns.search, :error, "Something went wrong")
             )}
        end
    end
  end

  defp load_favorite_item(:visual_novels, id) do
    case VisualNovels.get_visual_novel(id) do
      %VisualNovel{} = vn -> {:ok, decorate_vn(vn)}
      _ -> :error
    end
  end

  defp load_favorite_item(:characters, id) do
    case Repo.get(Character, id) do
      %Character{hidden_at: nil} = character -> {:ok, decorate_character(character)}
      _ -> :error
    end
  end

  defp load_characters_for_vn(vn_id, excluded_ids) do
    query =
      from vc in VNCharacter,
        join: c in Character,
        on: c.id == vc.character_id,
        where: vc.visual_novel_id == ^vn_id,
        where: vc.spoiler_level <= 0,
        where: is_nil(c.hidden_at),
        order_by: [
          asc:
            fragment(
              "CASE ? WHEN 'main' THEN 0 WHEN 'primary' THEN 1 WHEN 'side' THEN 2 ELSE 3 END",
              vc.role
            ),
          asc: c.name
        ],
        select: %{character: c, role: vc.role}

    query =
      if excluded_ids == [] do
        query
      else
        where(query, [_vc, c], c.id not in ^excluded_ids)
      end

    query
    |> Repo.all()
    |> Enum.map(fn %{character: character, role: role} ->
      character
      |> decorate_character()
      |> Map.put(:role, role)
    end)
  end

  defp load_favorite_vns(nil), do: []
  defp load_favorite_vns([]), do: []

  defp load_favorite_vns(ids) when is_list(ids) do
    by_id =
      VisualNovel
      |> where([vn], vn.id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    ids
    |> Enum.map(&Map.get(by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&decorate_vn/1)
  end

  defp load_favorite_characters(user_id) do
    Character
    |> join(:inner, [c], cf in CharacterFavorite, on: cf.character_id == c.id)
    |> where([_c, cf], cf.user_id == ^user_id)
    |> order_by([_c, cf], asc: cf.position, asc: cf.inserted_at)
    |> Repo.all()
    |> Enum.map(&decorate_character/1)
  end

  defp update_draft(socket, type, fun) do
    assign(socket, :draft_favorites, Map.update!(socket.assigns.draft_favorites, type, fun))
  end

  defp move(items, from, to) do
    length = length(items)

    cond do
      length == 0 ->
        items

      from < 0 or from >= length ->
        items

      from == to ->
        items

      true ->
        clamped_to = to |> max(0) |> min(length - 1)
        {item, rest} = List.pop_at(items, from)
        List.insert_at(rest, clamped_to, item)
    end
  end

  defp cast_index(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp cast_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> :error
    end
  end

  defp cast_index(_), do: :error

  defp parse_type(value) when value in [:visual_novels, "visual_novels"],
    do: {:ok, :visual_novels}

  defp parse_type(value) when value in [:characters, "characters"], do: {:ok, :characters}
  defp parse_type(_), do: :error

  defp draft_ids(socket, type) do
    socket.assigns.draft_favorites
    |> Map.get(type, [])
    |> Enum.map(& &1.id)
  end

  defp merged_ids(draft_items, existing_ids) do
    top_ids = Enum.map(draft_items, & &1.id)
    tail_ids = existing_ids |> List.wrap() |> Enum.drop(@top_favorites_limit)
    top_ids ++ Enum.reject(tail_ids, &(&1 in top_ids))
  end

  defp tail_count(items), do: max(length(items) - @top_favorites_limit, 0)

  defp items_for_island(items, type) do
    items
    |> List.wrap()
    |> Enum.map(&item_for_island(&1, type))
  end

  defp item_for_island(item, :visual_novels) do
    %{
      id: to_string(item.id),
      title: Map.get(item, :title) || "",
      slug: Map.get(item, :slug),
      images: normalize_images(Map.get(item, :images)),
      image_url: Map.get(item, :image_url),
      has_ero: Map.get(item, :has_ero) || false,
      is_image_nsfw: Map.get(item, :is_image_nsfw) || false,
      is_image_suggestive: Map.get(item, :is_image_suggestive) || false
    }
  end

  defp item_for_island(item, :characters) do
    %{
      id: to_string(item.id),
      name: Map.get(item, :name) || "",
      title: Map.get(item, :name) || "",
      slug: Map.get(item, :slug),
      images: normalize_images(Map.get(item, :images)),
      image_url: Map.get(item, :image_url),
      is_image_nsfw: Map.get(item, :is_image_nsfw) || false,
      is_image_suggestive: Map.get(item, :is_image_suggestive) || false
    }
  end

  defp normalize_images(nil), do: %{}

  defp normalize_images(%{} = images) do
    images
    |> Enum.flat_map(fn
      {key, value} when is_binary(value) and value != "" -> [{to_string(key), value}]
      _ -> []
    end)
    |> Map.new()
  end

  defp normalize_images(_), do: %{}

  defp decorate_vn(%VisualNovel{} = vn) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      image_url: image_url(VisualNovels.build_image_urls(vn)),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp decorate_character(%Character{} = character) do
    images = VisualNovels.build_character_image_urls(character)

    %{
      id: character.id,
      name: character.name,
      slug: character.slug,
      images: images,
      image_url: image_url(images),
      is_image_nsfw: character.is_image_nsfw,
      is_image_suggestive: character.is_image_suggestive
    }
  end

  defp normalize_search_vn(%{} = item) do
    image_url = Map.get(item, :image_url) || Map.get(item, "image_url")

    %{
      id: Map.get(item, :id) || Map.get(item, "id"),
      title: Map.get(item, :title) || Map.get(item, "title"),
      slug: Map.get(item, :slug) || Map.get(item, "slug"),
      image_url: image_url,
      images: image_map(Map.get(item, :images) || Map.get(item, "images"), image_url),
      producers: Map.get(item, :producers) || Map.get(item, "producers"),
      has_ero: Map.get(item, :has_ero) || Map.get(item, "has_ero"),
      is_image_nsfw: Map.get(item, :is_image_nsfw) || Map.get(item, "is_image_nsfw"),
      is_image_suggestive:
        Map.get(item, :is_image_suggestive) || Map.get(item, "is_image_suggestive")
    }
  end

  defp image_map(images, _image_url) when is_map(images) and map_size(images) > 0, do: images

  defp image_map(_images, image_url),
    do: %{small: image_url, medium: image_url, large: image_url, xl: image_url}

  defp image_url(images) when is_map(images) do
    images[:small] || images["small"] || images[:medium] || images["medium"] || images[:large] ||
      images["large"]
  end

  defp image_url(_), do: nil

  defp profile_user(%User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)
    banner_urls = Users.build_banner_urls(user.banner_id)

    %{
      username: user.username,
      display_name: user.display_name || user.username || "User",
      avatar_url:
        avatar_urls[:medium] || avatar_urls[:small] ||
          "https://images.kaguya.io/users/avatars/default-120w.webp",
      banner_url: banner_urls[:large] || banner_urls[:medium]
    }
  end

  defp social_value(nil, _field), do: ""

  defp social_value(social_links, field) do
    Map.get(social_links, field) || Map.get(social_links, Atom.to_string(field)) || ""
  end

  defp profile_path(%{username: username}) when is_binary(username) and username != "",
    do: ~p"/@#{username}"

  defp profile_path(_user), do: ~p"/settings"

  defp normalize_website(value) do
    value
    |> blank_to_nil()
    |> case do
      nil ->
        nil

      url ->
        if String.match?(url, ~r/^https?:\/\//i), do: url, else: "https://#{url}"
    end
  end

  defp normalize_twitter(value) do
    value
    |> blank_to_nil()
    |> case do
      nil ->
        nil

      value ->
        value
        |> String.trim_leading("@")
        |> twitter_handle_from_url()
    end
  end

  defp twitter_handle_from_url(value) do
    uri = URI.parse(value)

    if uri.host &&
         (String.contains?(uri.host, "twitter.com") || String.contains?(uri.host, "x.com")) do
      uri.path
      |> to_string()
      |> String.split("/", trim: true)
      |> List.first()
      |> blank_to_nil()
    else
      value
    end
  rescue
    _ -> value
  end

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp first_changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, &"#{Phoenix.Naming.humanize(field)} #{&1}")
    end)
    |> List.first()
    |> case do
      nil -> "Failed to update profile."
      message -> message
    end
  end

  defp social_icon_site(:x), do: "twitter"
  defp social_icon_site(:link), do: "website"

  defp dialog_title(:visual_novels, _step, _selected_vn), do: "Search VN"

  defp dialog_title(:characters, :character_select, %{title: title}) when is_binary(title),
    do: title

  defp dialog_title(:characters, _step, _selected_vn), do: "Search VN"
  defp dialog_title(_, _, _), do: "Search VN"

  defp role_label(:main), do: "Main"
  defp role_label(:primary), do: "Primary"
  defp role_label(:side), do: "Side"
  defp role_label(:appears), do: "Appears"
  defp role_label(value) when is_binary(value), do: String.capitalize(value)
  defp role_label(_), do: nil
end

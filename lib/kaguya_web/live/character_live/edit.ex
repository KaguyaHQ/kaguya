defmodule KaguyaWeb.CharacterLive.Edit do
  use KaguyaWeb, :live_view

  alias Kaguya.Authorization
  alias Kaguya.Characters
  alias Kaguya.Characters.Contributions
  alias Kaguya.Revisions
  alias KaguyaWeb.CharacterLive.Edit.Uploads, as: ImageUploads
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.SharedComponents.CharacterImage
  alias Phoenix.LiveView.JS

  import KaguyaWeb.UI.Button, only: [button: 1]
  import KaguyaWeb.UI.Checkbox, only: [checkbox: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Character editor",
       character: nil,
       state: :loading,
       can_moderate: false,
       base_revision: 0,
       staged_uploads: %{},
       appearances: %{},
       original_appearances: %{},
       original_form: empty_form(),
       original_appearance_ids: [],
       appearance_query: "",
       appearance_results: %{},
       form: empty_form()
     )
     |> allow_upload(:character_image,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 10_000_000
     )
     |> stream(:appearances, [])
     |> stream(:appearance_results, [])}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         assign(socket,
           slug: nil,
           character: nil,
           state: :auth_required,
           page_title: "New character",
           form: empty_form()
         )}

      current_user ->
        if can_edit?(current_user) do
          {:noreply,
           assign(socket,
             slug: nil,
             character: nil,
             state: :creating,
             can_moderate: Authorization.can_moderate_db?(current_user),
             page_title: "New character",
             form: empty_form()
           )}
        else
          {:noreply,
           assign(socket,
             slug: nil,
             character: nil,
             state: :forbidden,
             page_title: "New character"
           )}
        end
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    socket = assign(socket, :slug, slug)

    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, state: :auth_required)}

      current_user ->
        case Characters.get_character_page_by_slug(slug, current_user) do
          {:ok, page} ->
            can_moderate = Authorization.can_moderate_db?(current_user)

            cond do
              # Lock check first so non-mods on locked entries see the specific
              # reason instead of a generic "no permission." Mods bypass —
              # they unlock from the form's Moderation fieldset.
              page.character.is_locked and not can_moderate ->
                {:noreply,
                 assign(socket,
                   state: :locked,
                   character: page.character,
                   page_title: "#{page.character.name} · Edit"
                 )}

              !can_edit?(current_user) ->
                {:noreply,
                 assign(socket,
                   state: :forbidden,
                   character: page.character,
                   page_title: "#{page.character.name} · Edit"
                 )}

              true ->
                appearances =
                  Characters.list_appearances_for_edit(page.character.id, current_user)

                {:noreply,
                 socket
                 |> assign(
                   state: :editing,
                   character: page.character,
                   can_moderate: can_moderate,
                   page_title: "Edit #{page.character.name}",
                   base_revision: Revisions.latest_revision_number(:character, page.character.id),
                   original_appearance_ids: Enum.map(appearances, & &1.id),
                   original_appearances: Map.new(appearances, &{&1.id, &1}),
                   original_form: form_from_character(page.character),
                   form: form_from_character(page.character)
                 )
                 |> put_appearances(appearances)}
            end

          {:error, :not_found} ->
            {:noreply,
             assign(socket,
               state: :not_found,
               page_title: "Character not found · Kaguya"
             )}
        end
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{state: state}} = socket)
      when event in [
             "validate",
             "save",
             "search_appearance_vns",
             "add_appearance",
             "remove_appearance",
             "cancel_image"
           ] and
             state not in [:editing, :creating] do
    {:noreply, put_flash(socket, :error, "You do not have permission to edit this character.")}
  end

  def handle_event("search_appearance_vns", params, socket) do
    query = params |> Map.get("appearance_query", "") |> normalize_text() |> String.slice(0, 100)

    results =
      Characters.search_appearance_visual_novels(query, socket.assigns.current_user)
      |> Enum.reject(&Map.has_key?(socket.assigns.appearances, &1.id))

    {:noreply,
     socket
     |> assign(appearance_query: query, appearance_results: Map.new(results, &{&1.id, &1}))
     |> stream(:appearance_results, results, reset: true)}
  end

  def handle_event("add_appearance", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.appearance_results, id) do
      {:ok, vn} ->
        appearance = Map.merge(vn, %{role: "side", spoiler_level: "0"})

        {:noreply,
         socket
         |> put_appearances(Map.put(socket.assigns.appearances, id, appearance) |> Map.values())
         |> assign(appearance_query: "", appearance_results: %{})
         |> stream(:appearance_results, [], reset: true)}

      :error ->
        {:noreply, put_flash(socket, :error, "Search for a visual novel before adding it.")}
    end
  end

  def handle_event("remove_appearance", %{"id" => id}, socket) do
    {:noreply,
     put_appearances(socket, socket.assigns.appearances |> Map.delete(id) |> Map.values())}
  end

  def handle_event("validate", %{"character" => attrs}, socket) do
    {:noreply,
     socket
     |> assign(:form, normalize_form(attrs, socket.assigns.form))
     |> update_appearance_fields(attrs)}
  end

  @impl true
  def handle_event("save", %{"character" => attrs}, socket) do
    socket = update_appearance_fields(socket, attrs)
    form = normalize_form(attrs, socket.assigns.form)
    summary = form["summary"] |> ensure_summary(socket.assigns.live_action)

    appearances =
      Enum.map(socket.assigns.appearances, fn {id, row} ->
        %{visual_novel_id: id, role: row.role, spoiler_level: row.spoiler_level}
      end)

    changes = %{name: form["name"], description: form["description"], appearances: appearances}

    changes =
      if socket.assigns.character do
        changes
        |> maybe_put_hidden_at(socket.assigns.character, form)
        |> maybe_put_is_locked(socket.assigns.character, form)
      else
        changes
      end

    case ImageUploads.stage(socket, form) do
      {:ok, staged_socket, image} ->
        finish_save(staged_socket, form, changes, summary, image)

      {:error, staged_socket, message} ->
        {:noreply, staged_socket |> assign(:form, form) |> put_flash(:error, message)}
    end
  end

  def handle_event("cancel_image", %{"ref" => ref}, socket) do
    if Enum.any?(socket.assigns.uploads.character_image.entries, &(&1.ref == ref)) do
      {:noreply,
       socket
       |> cancel_upload(:character_image, ref)
       |> assign(
         :form,
         Map.merge(
           socket.assigns.form,
           Map.take(socket.assigns.original_form, ["image_nsfw", "image_suggestive"])
         )
       )
       |> assign(:staged_uploads, Map.delete(socket.assigns.staged_uploads, ref))}
    else
      {:noreply, socket}
    end
  end

  defp finish_save(socket, form, changes, summary, image) do
    case save_character(socket, changes, summary, image) do
      {:ok, result} ->
        character =
          if socket.assigns.live_action == :new,
            do: result.entity,
            else: socket.assigns.character

        invalidate_appearance_pages(socket)

        {:noreply,
         socket
         |> ImageUploads.complete()
         |> assign(form: form)
         |> put_flash(
           :info,
           if(socket.assigns.live_action == :new,
             do: "Character created.",
             else: "Character updated."
           )
         )
         |> push_navigate(to: "/character/#{character.slug}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, format_revision_error(reason))}
    end
  end

  defp save_character(%{assigns: %{live_action: :new}} = socket, attrs, summary, image) do
    Contributions.create(attrs, summary, socket.assigns.current_user, image)
  end

  defp save_character(socket, attrs, summary, image) do
    Contributions.update(
      socket.assigns.character.id,
      attrs,
      summary,
      socket.assigns.current_user,
      socket.assigns.base_revision,
      image
    )
  end

  @impl true
  def render(%{state: :not_found} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :editor_form, to_form(assigns.form, as: :character))

    ~H"""
    <div class="mx-auto mt-6 max-w-[748px] px-4 pb-20 lg:mt-10 lg:px-0">
      <button
        :if={@live_action == :new}
        type="button"
        onclick="history.back()"
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back
      </button>
      <.link
        :if={@live_action != :new}
        navigate={back_path(assigns)}
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← {back_label(assigns)}
      </.link>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {heading(assigns)}
      </h1>

      <.link
        id="character-editor-help"
        href={~p"/help/characters"}
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Character editing guide (opens in a new tab)"
        class="text-foreground-link text-style-body2Regular inline-flex items-center gap-1.5 underline underline-offset-2"
      >
        Character editing guide <Lucide.external_link class="size-3.5" aria-hidden />
      </.link>

      <section
        :if={@state == :auth_required}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        {auth_message(assigns)}
      </section>

      <section
        :if={@state == :forbidden}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        {forbidden_message(assigns)}
      </section>

      <section
        :if={@state == :locked}
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        This character is locked and cannot be edited.
      </section>

      <.form
        :if={@state in [:editing, :creating]}
        id="character-edit"
        for={@editor_form}
        phx-hook="UnsavedChanges"
        data-dirty={
          to_string(
            @form != @original_form or @appearances != @original_appearances or
              @uploads.character_image.entries != []
          )
        }
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4"
        phx-change="validate"
        phx-submit="save"
      >
        <div class="space-y-4">
          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Name</span>
            <input
              id="character-name"
              type="text"
              name="character[name]"
              value={@form["name"]}
              maxlength="255"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            />
          </label>

          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Description</span>
            <textarea
              name="character[description]"
              rows="8"
              maxlength="5000"
              class="bg-surface-elevated border-border-divider min-h-[180px] rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            ><%= @form["description"] %></textarea>
          </label>

          <section id="character-image-editor" class="border-border-divider space-y-4 border-t pt-5">
            <div>
              <h2 class="text-foreground-primary text-style-body1Medium">Character image</h2>
              <p class="text-foreground-secondary text-style-body2Regular mt-1">
                Choose a clear portrait. Your image is saved with your other changes.
              </p>
            </div>
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start">
              <div class="bg-surface-elevated size-32 shrink-0 overflow-hidden rounded-lg">
                <.live_img_preview
                  :for={entry <- @uploads.character_image.entries}
                  entry={entry}
                  id={"character-image-preview-#{entry.ref}"}
                  class="size-full object-contain"
                  alt="Selected character image"
                />
                <CharacterImage.character_image
                  :if={@uploads.character_image.entries == [] && @character}
                  character={@character}
                  class="size-full object-contain"
                  fallback_class="size-full"
                  enable_nsfw_reveal
                  alt="Current character image"
                />
                <div
                  :if={@uploads.character_image.entries == [] && is_nil(@character)}
                  class="text-foreground-tertiary flex size-full items-center justify-center"
                  aria-label="No character image selected"
                >
                  <Lucide.image class="size-8" aria-hidden />
                </div>
              </div>
              <div class="min-w-0 flex-1 space-y-3">
                <.button
                  :if={@uploads.character_image.entries == []}
                  id="character-image-choose"
                  variant="neutral"
                  size="small"
                  class="gap-2"
                  phx-click={JS.dispatch("click", to: "##{@uploads.character_image.ref}")}
                  aria-describedby="character-image-hint"
                >
                  <Lucide.upload class="size-4" aria-hidden />
                  {if @character && @character.primary_image_id,
                    do: "Replace image",
                    else: "Choose image"}
                </.button>
                <.live_file_input
                  upload={@uploads.character_image}
                  class="hidden"
                  tabindex="-1"
                  aria-label="Choose character image"
                />
                <p id="character-image-hint" class="text-foreground-secondary text-style-body2Regular">
                  JPG, PNG, or WebP. Up to 10 MB.
                </p>
                <div :for={entry <- @uploads.character_image.entries} class="space-y-2">
                  <p class="text-foreground-secondary text-style-body2Regular break-all">
                    {entry.client_name}
                  </p>
                  <p
                    :if={entry.progress > 0 && !entry.done?}
                    class="text-foreground-secondary text-style-body2Regular"
                    role="status"
                  >
                    Uploading: {entry.progress}%
                  </p>
                  <.button
                    id={"character-image-cancel-#{entry.ref}"}
                    variant="ghost"
                    size="small"
                    phx-click="cancel_image"
                    phx-value-ref={entry.ref}
                  >
                    Cancel image selection
                  </.button>
                  <p
                    :for={error <- upload_errors(@uploads.character_image, entry)}
                    class="text-semantic-error text-style-body2Regular"
                    role="alert"
                  >
                    {ImageUploads.error_message(error)}
                  </p>
                </div>
                <p
                  :for={error <- upload_errors(@uploads.character_image)}
                  class="text-semantic-error text-style-body2Regular"
                  role="alert"
                >
                  {ImageUploads.error_message(error)}
                </p>
                <fieldset :if={@uploads.character_image.entries != []} class="space-y-2">
                  <legend class="text-foreground-primary text-style-body2Medium mb-2">
                    Image content
                  </legend>
                  <label class="text-foreground-secondary text-style-body2Regular flex items-center gap-2">
                    <.checkbox
                      id="character-image-nsfw"
                      name="character[image_nsfw]"
                      value="true"
                      checked={@form["image_nsfw"]}
                    /> Explicit / NSFW
                  </label>
                  <label class="text-foreground-secondary text-style-body2Regular flex items-center gap-2">
                    <.checkbox
                      id="character-image-suggestive"
                      name="character[image_suggestive]"
                      value="true"
                      checked={@form["image_suggestive"]}
                    /> Suggestive
                  </label>
                </fieldset>
              </div>
            </div>
          </section>

          <section id="character-appearances" class="border-border-divider space-y-4 border-t pt-5">
            <div>
              <h2 class="text-foreground-primary text-base font-medium">Visual novel appearances</h2>
              <p class="text-foreground-secondary mt-1 text-sm">
                Link this character to the visual novels they appear in. Changes are saved with the character.
              </p>
            </div>

            <p class="text-foreground-secondary text-sm">
              Set the role for each VN. The spoiler level marks whether knowing they appear there
              reveals part of the story.
            </p>

            <div id="character-appearance-list" phx-update="stream" class="space-y-3">
              <p
                id="character-appearances-empty"
                class="text-foreground-tertiary hidden text-sm only:block"
              >
                No visual novels linked yet.
              </p>
              <div
                :for={{dom_id, appearance} <- @streams.appearances}
                id={dom_id}
                class="bg-surface-elevated border-border-divider rounded-lg border p-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <.link
                    :if={appearance.slug}
                    navigate={"/vn/#{appearance.slug}"}
                    class="text-foreground-primary min-w-0 font-medium hover:underline"
                  >
                    {appearance.title}
                  </.link>
                  <span :if={!appearance.slug} class="text-foreground-secondary font-medium">{appearance.title}</span>
                  <button
                    id={"remove-appearance-#{appearance.id}"}
                    type="button"
                    phx-click="remove_appearance"
                    phx-value-id={appearance.id}
                    aria-label={"Remove #{appearance.title}"}
                    class="hover:text-foreground-primary text-foreground-secondary shrink-0 text-sm"
                  >
                    Remove
                  </button>
                </div>
                <div class="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <label class="text-foreground-secondary flex flex-col gap-1.5 text-sm">
                    <span>Role</span>
                    <select
                      id={"appearance-role-#{appearance.id}"}
                      name={"character[appearances][#{appearance.id}][role]"}
                      class="bg-surface-base border-border-divider text-foreground-primary w-full rounded-md border px-3 py-2"
                    >
                      <option
                        :for={
                          {label, value} <- [
                            {"Main", "main"},
                            {"Primary", "primary"},
                            {"Side", "side"},
                            {"Appears", "appears"}
                          ]
                        }
                        value={value}
                        selected={appearance.role == value}
                      >
                        {label}
                      </option>
                    </select>
                  </label>
                  <label class="text-foreground-secondary flex flex-col gap-1.5 text-sm">
                    <span>Appearance spoiler level</span>
                    <select
                      id={"appearance-spoiler-#{appearance.id}"}
                      name={"character[appearances][#{appearance.id}][spoiler_level]"}
                      class="bg-surface-base border-border-divider text-foreground-primary w-full rounded-md border px-3 py-2"
                    >
                      <option
                        :for={
                          {label, value} <- [
                            {"No spoilers", "0"},
                            {"Minor spoilers", "1"},
                            {"Major spoilers", "2"}
                          ]
                        }
                        value={value}
                        selected={appearance.spoiler_level == value}
                      >
                        {label}
                      </option>
                    </select>
                  </label>
                </div>
              </div>
            </div>

            <label for="character-vn-search" class="text-foreground-primary block text-sm font-medium">
              Add a visual novel
            </label>
            <input
              id="character-vn-search"
              type="search"
              name="appearance_query"
              data-unsaved-ignore
              value={@appearance_query}
              phx-change="search_appearance_vns"
              phx-debounce="250"
              maxlength="100"
              placeholder="Search by title (at least 2 characters)"
              autocomplete="off"
              aria-controls="character-vn-results"
              class="bg-surface-elevated border-border-divider text-foreground-primary w-full rounded-md border px-3 py-2 text-sm"
            />
            <p
              :if={String.length(@appearance_query) >= 2 and map_size(@appearance_results) == 0}
              id="character-vn-no-results"
              class="text-foreground-tertiary text-sm"
              role="status"
            >
              No matching visual novels to add.
            </p>
            <div id="character-vn-results" phx-update="stream" class="space-y-1">
              <button
                :for={{dom_id, vn} <- @streams.appearance_results}
                id={dom_id}
                type="button"
                phx-click="add_appearance"
                phx-value-id={vn.id}
                class="border-border-divider hover:bg-surface-elevated text-foreground-primary flex w-full items-center justify-between gap-3 rounded-md border px-3 py-2 text-left text-sm"
              >
                <span>{vn.title}</span><span class="text-foreground-secondary shrink-0">Add</span>
              </button>
            </div>
          </section>

          <fieldset
            :if={@can_moderate and @live_action == :edit}
            class="space-y-3 rounded-[8px] border border-amber-500/20 bg-amber-500/6 p-3"
          >
            <legend class="px-1 text-xs font-medium tracking-[0.06em] text-amber-400 uppercase">
              Moderation
            </legend>

            <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="character[is_hidden]" value="false" />
              <input
                type="checkbox"
                name="character[is_hidden]"
                value="true"
                checked={@form["is_hidden"]}
                class="bg-surface-elevated border-border-divider mt-0.5 size-4 rounded"
              />
              <span class="flex flex-col gap-0.5">
                <span class="font-medium text-[rgb(var(--foreground-primary))]">Hide entry</span>
                <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  Removes from public lists and search. The audit summary doubles as the reason.
                </span>
              </span>
            </label>

            <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="character[is_locked]" value="false" />
              <input
                type="checkbox"
                name="character[is_locked]"
                value="true"
                checked={@form["is_locked"]}
                class="bg-surface-elevated border-border-divider mt-0.5 size-4 rounded"
              />
              <span class="flex flex-col gap-0.5">
                <span class="font-medium text-[rgb(var(--foreground-primary))]">Lock entry</span>
                <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  Prevents non-moderators from submitting further edits.
                </span>
              </span>
            </label>
          </fieldset>

          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Summary</span>
            <input
              type="text"
              name="character[summary]"
              value={@form["summary"]}
              placeholder="Brief change summary"
              minlength="2"
              maxlength="5000"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            />
          </label>

          <button
            type="submit"
            class="rounded-[6px] border border-[rgb(var(--chip-border-default))] px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
          >
            {submit_label(assigns)}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp put_appearances(socket, rows) do
    rows = Enum.sort_by(rows, &{&1.title, &1.id})

    socket
    |> assign(:appearances, Map.new(rows, &{&1.id, &1}))
    |> stream(:appearances, rows, reset: true)
  end

  defp update_appearance_fields(socket, attrs) do
    params = Map.get(attrs, "appearances", %{})
    params = if is_map(params), do: params, else: %{}

    rows =
      Enum.map(socket.assigns.appearances, fn {id, row} ->
        fields = Map.get(params, id, %{})
        fields = if is_map(fields), do: fields, else: %{}

        %{
          row
          | role: Map.get(fields, "role", row.role),
            spoiler_level: Map.get(fields, "spoiler_level", row.spoiler_level)
        }
      end)

    put_appearances(socket, rows)
  end

  defp invalidate_appearance_pages(socket) do
    Characters.invalidate_appearance_pages(
      socket.assigns.original_appearance_ids ++ Map.keys(socket.assigns.appearances)
    )
  end

  defp normalize_text(nil), do: ""
  defp normalize_text(value), do: String.trim(to_string(value))

  defp empty_form do
    %{
      "name" => "",
      "description" => "",
      "summary" => "",
      "is_hidden" => false,
      "is_locked" => false,
      "image_nsfw" => false,
      "image_suggestive" => false
    }
  end

  defp form_from_character(character) do
    %{
      "name" => character.name,
      "description" => character.description || "",
      "summary" => "",
      "is_hidden" => not is_nil(character.hidden_at),
      "is_locked" => character.is_locked || false,
      "image_nsfw" => character.is_image_nsfw || false,
      "image_suggestive" => character.is_image_suggestive || false
    }
  end

  defp normalize_form(attrs, current_form) do
    %{
      "name" => normalize_text(Map.get(attrs, "name", current_form["name"])),
      "description" => normalize_text(Map.get(attrs, "description", current_form["description"])),
      "summary" => normalize_text(Map.get(attrs, "summary", current_form["summary"])),
      "is_hidden" => truthy?(Map.get(attrs, "is_hidden", Map.get(current_form, "is_hidden"))),
      "is_locked" => truthy?(Map.get(attrs, "is_locked", Map.get(current_form, "is_locked"))),
      "image_nsfw" => truthy?(Map.get(attrs, "image_nsfw", current_form["image_nsfw"])),
      "image_suggestive" =>
        truthy?(Map.get(attrs, "image_suggestive", current_form["image_suggestive"]))
    }
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("on"), do: true
  defp truthy?(_), do: false

  # Mirrors the producer Edit form. The server-side sanitize in
  # `Kaguya.Revisions.submit_edit/6` is the actual permission boundary; this
  # only avoids sending no-op changes for non-mods.
  defp maybe_put_hidden_at(changes, character, form) do
    new_value = Map.get(form, "is_hidden")
    current_value = not is_nil(character.hidden_at)

    if new_value != current_value do
      Map.put(changes, :hidden_at, hidden_at_value(new_value))
    else
      changes
    end
  end

  defp maybe_put_is_locked(changes, character, form) do
    new_value = Map.get(form, "is_locked")

    if new_value != (character.is_locked || false) do
      Map.put(changes, :is_locked, new_value)
    else
      changes
    end
  end

  defp hidden_at_value(true), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp hidden_at_value(_), do: nil

  defp ensure_summary("", :new), do: "Created character"
  defp ensure_summary("", _action), do: "Updated character"
  defp ensure_summary(summary, _action), do: summary

  defp heading(%{live_action: :new}), do: "Create character"
  defp heading(_assigns), do: "Edit character"

  defp submit_label(%{live_action: :new}), do: "Create character"
  defp submit_label(_assigns), do: "Save changes"

  defp auth_message(%{live_action: :new}), do: "Sign in to create a character."
  defp auth_message(_assigns), do: "Sign in to edit this character."

  defp forbidden_message(%{live_action: :new}),
    do: "You do not have permission to create characters."

  defp forbidden_message(_assigns), do: "You do not have permission to edit this character."

  defp back_path(%{slug: slug}), do: "/character/#{slug}"

  defp back_label(_assigns), do: "Back to character"

  defp format_revision_error({:error, reason}), do: format_revision_error(reason)

  defp format_revision_error(:edit_conflict),
    do: "This character changed while you were editing. Reload before saving again."

  defp format_revision_error(reason) when is_binary(reason), do: reason
  defp format_revision_error(%Ecto.Changeset{} = changeset), do: format_changeset_error(changeset)
  defp format_revision_error(_), do: "Unable to save character."

  defp format_changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end

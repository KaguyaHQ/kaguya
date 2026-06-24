defmodule KaguyaWeb.VNLive.Edit do
  use KaguyaWeb, :live_view

  alias Kaguya.Authorization
  alias Kaguya.Covers
  alias Kaguya.Repo
  alias Kaguya.Screenshots
  alias Kaguya.Revisions
  alias Kaguya.VisualNovels

  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.VNLive.Edit.{Form, Uploads, Sections}

  @accepted_image_exts ~w(.jpg .jpeg .png .webp)
  @max_vn_image_size 10_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Edit visual novel",
       state: :loading,
       vn: nil,
       can_moderate: false,
       revisions: [],
       base_revision: 0,
       original_form: Form.empty_form(),
       form: Form.empty_form(),
       dirty_fields: [],
       dirty_count: 0,
       relation_query: "",
       relation_results: [],
       create_step: :form,
       create_mode: nil,
       create_mode_options: create_mode_options(),
       dup_query: "",
       dup_results: [],
       development_status_options: development_status_options(),
       length_options: length_options(),
       language_options: language_options(),
       title_category_options: title_category_options()
     )
     |> allow_upload(:new_screenshots,
       accept: @accepted_image_exts,
       max_entries: 12,
       max_file_size: @max_vn_image_size
     )
     |> allow_upload(:new_covers,
       accept: @accepted_image_exts,
       max_entries: 12,
       max_file_size: @max_vn_image_size
     )}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    # A change summary is required to submit, so the create form ships with a
    # sensible default the contributor can override (mirrors the Next flow).
    create_form = Map.put(Form.empty_form(), "summary", "Initial creation")

    base = [
      slug: nil,
      vn: nil,
      revisions: [],
      base_revision: 0,
      original_form: create_form,
      form: create_form,
      dirty_fields: [],
      dirty_count: 0,
      relation_query: "",
      relation_results: [],
      create_step: :fork,
      create_mode: nil,
      dup_query: "",
      dup_results: [],
      page_title: "Create visual novel"
    ]

    case socket.assigns.current_user do
      nil ->
        {:noreply, socket |> assign(base) |> assign(:state, :auth_required)}

      current_user ->
        if can_edit?(current_user) do
          {:noreply,
           socket
           |> assign(base)
           |> assign(:state, :creating)
           |> assign(:can_moderate, Authorization.can_moderate_db?(current_user))}
        else
          {:noreply, socket |> assign(base) |> assign(:state, :forbidden)}
        end
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    socket = assign(socket, :slug, slug)

    base_state =
      [
        state: :loading,
        vn: nil,
        revisions: [],
        base_revision: 0,
        original_form: Form.empty_form(),
        form: Form.empty_form(),
        dirty_fields: [],
        dirty_count: 0,
        relation_query: "",
        relation_results: []
      ]

    case socket.assigns.current_user do
      nil ->
        {:noreply,
         socket
         |> assign(base_state)
         |> assign(:state, :auth_required)
         |> assign(:page_title, "Edit visual novel")}

      current_user ->
        can_moderate = Authorization.can_moderate_db?(current_user)
        opts = if can_moderate, do: [include_hidden: true], else: []

        case VisualNovels.get_visual_novel_by_slug(slug, opts) do
          nil ->
            {:noreply,
             socket
             |> assign(base_state)
             |> assign(:state, :not_found)
             |> assign(:page_title, "Visual novel not found · Kaguya")}

          vn ->
            vn =
              vn.id
              |> VisualNovels.get_for_edit()
              |> Repo.preload(vn_relations: :related_vn)

            revisions = Revisions.list_revisions(:visual_novel, vn.id, limit: 10)
            {:ok, covers} = Covers.list_covers_for_vn(vn.id, current_user.id)
            {:ok, screenshots} = Screenshots.list_screenshots_for_vn(vn.id, current_user.id)
            original_form = Form.from_visual_novel(vn, covers, screenshots)
            latest_revision = Revisions.latest_revision_number(:visual_novel, vn.id)

            cond do
              # Lock check first so non-mods on a locked entry see the specific
              # reason. Mods bypass and unlock from the form's Moderation
              # fieldset.
              vn.is_locked and not can_moderate ->
                {:noreply,
                 socket
                 |> assign(:can_moderate, can_moderate)
                 |> edit_state(:locked, vn, revisions, latest_revision, original_form)}

              !can_edit?(current_user) ->
                {:noreply,
                 socket
                 |> assign(:can_moderate, can_moderate)
                 |> edit_state(:forbidden, vn, revisions, latest_revision, original_form)}

              true ->
                {:noreply,
                 socket
                 |> assign(:can_moderate, can_moderate)
                 |> edit_state(:editing, vn, revisions, latest_revision, original_form)}
            end
        end
    end
  end

  @impl true
  def handle_event("validate", %{"vn" => attrs}, socket) do
    form = Form.normalize(attrs, socket.assigns.form)
    {:noreply, assign_form(socket, form)}
  end

  @impl true
  def handle_event("add_title", _params, socket) do
    form = update_in(socket.assigns.form["titles"], &(&1 ++ [Form.empty_title()]))
    {:noreply, assign_form(socket, Map.put(socket.assigns.form, "titles", form))}
  end

  @impl true
  def handle_event("remove_title", %{"index" => index}, socket) do
    titles =
      socket.assigns.form["titles"]
      |> Form.drop_index(index)
      |> Form.ensure_titles_present()

    {:noreply, assign_form(socket, Map.put(socket.assigns.form, "titles", titles))}
  end

  # ── Create type-fork (the pre-step before the form) ──────────────────
  #
  # Mirrors the Next.js CreateVnTypeFork: pick a category, type the title
  # (which live-checks the catalog for duplicates), then continue into the
  # form pre-filled with mode-appropriate defaults. Only reachable on :new.
  @impl true
  def handle_event("select_create_mode", %{"mode" => mode}, socket) do
    mode = parse_mode(mode)
    query = String.trim(socket.assigns.dup_query)

    results = if mode && String.length(query) >= 2, do: relation_results(query), else: []

    {:noreply, assign(socket, create_mode: mode, dup_results: results)}
  end

  @impl true
  def handle_event("fork_title", %{"title" => title}, socket) do
    query = String.trim(title)

    results =
      if socket.assigns.create_mode && String.length(query) >= 2,
        do: relation_results(query),
        else: []

    {:noreply, assign(socket, dup_query: title, dup_results: results)}
  end

  @impl true
  def handle_event("continue_to_form", params, socket) do
    mode = socket.assigns.create_mode

    # Prefer the title from the submit payload over the debounced query: a
    # contributor who types and immediately presses Enter would otherwise
    # lose the last keystrokes the 350ms debounce hadn't flushed yet.
    title =
      params
      |> Map.get("title", socket.assigns.dup_query)
      |> String.trim()

    if mode != nil and title != "" do
      form = form_for_mode(mode, title)

      {:noreply,
       socket
       |> assign(create_step: :form, dup_query: title)
       |> assign_form(form)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_fork", _params, socket) do
    {:noreply, assign(socket, :create_step, :fork)}
  end

  @impl true
  def handle_event("search_relations", params, socket) do
    query =
      params
      |> Map.get("relation_query", Map.get(params, "value", ""))
      |> normalize_text()

    {:noreply, assign(socket, relation_query: query, relation_results: relation_results(query))}
  end

  @impl true
  def handle_event("add_relation_result", params, socket) do
    relation = %{
      "related_vn_id" => normalize_text(Map.get(params, "id")),
      "related_vn_slug" => normalize_text(Map.get(params, "slug")),
      "related_vn_title" => normalize_text(Map.get(params, "title")),
      "relation_type" => "sequel",
      "is_official" => true
    }

    relations =
      socket.assigns.form["relations"]
      |> Form.add_relation(relation, current_vn_id(socket))

    form = Map.put(socket.assigns.form, "relations", relations)

    {:noreply,
     socket
     |> assign_form(form)
     |> assign(relation_query: "", relation_results: [])}
  end

  @impl true
  def handle_event("remove_relation", %{"index" => index}, socket) do
    relations = Form.drop_index(socket.assigns.form["relations"], index)
    {:noreply, assign_form(socket, Map.put(socket.assigns.form, "relations", relations))}
  end

  @impl true
  def handle_event("remove_screenshot", %{"id" => id}, socket) do
    form =
      update_in(socket.assigns.form, ["screenshots"], fn screenshots ->
        Enum.map(screenshots, fn screenshot ->
          if screenshot["id"] == id, do: Map.put(screenshot, "removed", true), else: screenshot
        end)
      end)

    {:noreply, assign_form(socket, Form.normalize_primary_cover(form))}
  end

  @impl true
  def handle_event("remove_cover", %{"id" => id}, socket) do
    form =
      socket.assigns.form
      |> update_in(["covers"], fn covers ->
        Enum.map(covers, fn cover ->
          if cover["id"] == id, do: Map.put(cover, "removed", true), else: cover
        end)
      end)
      |> Form.clear_primary_cover_if_removed(id)

    {:noreply, assign_form(socket, form)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref, "upload" => upload}, socket) do
    upload_name =
      case upload do
        "new_screenshots" -> :new_screenshots
        "new_covers" -> :new_covers
        _ -> nil
      end

    if upload_name do
      {:noreply, cancel_upload(socket, upload_name, ref)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save", %{"vn" => attrs}, socket) do
    form = Form.normalize(attrs, socket.assigns.form)

    case socket.assigns.live_action do
      :new -> save_new(socket, form)
      _ -> save_edit(socket, form)
    end
  end

  defp save_new(socket, form) do
    with {:ok, current_user} <- require_creator(socket),
         {:ok, _titles, summary} <- Form.validate(form) do
      attrs = Form.to_create_attrs(form)

      case Revisions.create_entity(:visual_novel, attrs, summary, current_user) do
        {:ok, %{entity: vn}} ->
          {:noreply,
           socket
           |> put_flash(:info, "Visual novel created.")
           |> push_navigate(to: "/vn/#{vn.slug}")}

        {:error, reason} ->
          {:noreply,
           socket |> assign_form(form) |> put_flash(:error, format_revision_error(reason))}
      end
    else
      {:error, message} ->
        {:noreply, socket |> assign_form(form) |> put_flash(:error, message)}
    end
  end

  defp save_edit(socket, form) do
    with :ok <- require_editable(socket),
         {:ok, _titles, summary} <- Form.validate(form),
         {:ok, uploaded_form} <- Uploads.finalize_pending_uploads(socket, form),
         changes <- Form.build_changes(socket.assigns.original_form, uploaded_form),
         :ok <- ensure_changes_present(changes) do
      case Revisions.submit_edit(
             :visual_novel,
             socket.assigns.vn.id,
             changes,
             summary,
             socket.assigns.current_user,
             base_revision: socket.assigns.base_revision
           ) do
        {:ok, _change} ->
          {:noreply,
           socket
           |> assign_form(uploaded_form)
           |> put_flash(:info, "Visual novel updated.")
           |> push_navigate(to: "/vn/#{socket.assigns.slug}")}

        {:error, :edit_conflict} ->
          {:noreply,
           socket
           |> assign_form(uploaded_form)
           |> assign(
             :base_revision,
             Revisions.latest_revision_number(:visual_novel, socket.assigns.vn.id)
           )
           |> put_flash(
             :error,
             "This page was updated by someone else. Review your edits and submit again."
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign_form(uploaded_form)
           |> put_flash(:error, format_revision_error(reason))}
      end
    else
      {:error, {:upload_failed, uploaded_form, message}} ->
        {:noreply, socket |> assign_form(uploaded_form) |> put_flash(:error, message)}

      {:error, message} ->
        {:noreply, socket |> assign_form(form) |> put_flash(:error, message)}
    end
  end

  @impl true
  def render(%{state: :not_found} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-6 max-w-[748px] px-4 pb-20 lg:mt-10 lg:px-0">
      <button
        :if={@live_action == :new and @create_step == :fork}
        type="button"
        onclick="history.back()"
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back
      </button>
      <button
        :if={@live_action == :new and @create_step == :form}
        type="button"
        phx-click="back_to_fork"
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back to type selection
      </button>
      <.link
        :if={@live_action != :new}
        navigate={back_path(assigns)}
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← {back_label(assigns)}
      </.link>

      <p class="text-foreground-tertiary text-style-captionMedium mb-2 tracking-[0.08em] uppercase">
        {eyebrow_label(assigns)}
      </p>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {display_title(assigns)}
      </h1>

      <p :if={@vn} class="text-sm text-[rgb(var(--foreground-secondary))]">
        /vn/{@vn.slug}
      </p>

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
        class="mt-6 rounded-[8px] border border-amber-500/20 bg-amber-500/10 p-4 text-sm text-amber-400"
      >
        This entry is locked for editing.
      </section>

      <section
        :if={@revisions != []}
        class="border-border-divider mt-8 overflow-hidden rounded-[8px] border"
      >
        <div class="bg-surface-menu-item-hover/20 border-border-divider border-b px-4 py-3">
          <div class="text-foreground-primary text-sm font-medium">Recent history</div>
        </div>

        <div class="divide-border-divider/60 divide-y">
          <div
            :for={revision <- @revisions}
            class="grid grid-cols-[64px_166px_120px_minmax(0,1fr)] gap-0 px-4 py-3 text-xs"
          >
            <.link
              navigate={"/vn/#{@slug}/history/#{revision.id}"}
              class="font-mono text-[rgb(var(--text-link-default))] hover:text-[rgb(var(--text-link-hover))]"
            >
              r{revision.revision_number}
            </.link>

            <span
              class="text-foreground-tertiary"
              title={revision.inserted_at && DateTime.to_iso8601(revision.inserted_at)}
            >
              {history_timestamp(revision.inserted_at)}
            </span>

            <span class="text-foreground-secondary truncate">
              {history_user(revision)}
            </span>

            <span class="text-foreground-secondary truncate">
              {history_summary(revision)}
            </span>
          </div>
        </div>

        <div class="border-border-divider border-t px-4 py-2">
          <.link
            navigate={"/vn/#{@slug}/history"}
            class="text-xs text-[rgb(var(--text-link-default))] hover:text-[rgb(var(--text-link-hover))]"
          >
            View full history
          </.link>
        </div>
      </section>

      <section :if={@state == :creating and @create_step == :fork} class="mt-8 space-y-10">
        <div class="space-y-4">
          <h2 class="border-border-divider text-foreground-primary text-style-heading3Medium border-b pb-2">
            What kind of VN is this?
          </h2>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <button
              :for={opt <- @create_mode_options}
              type="button"
              phx-click="select_create_mode"
              phx-value-mode={opt.value}
              class={[
                "flex flex-col items-start gap-1.5 rounded-[8px] border bg-transparent p-4 text-left transition-colors",
                if(@create_mode == opt.atom,
                  do: "bg-surface-elevated border-foreground-tertiary",
                  else: "border-border-divider hover:border-[rgb(var(--chip-border-hover))]"
                )
              ]}
            >
              <span class="text-foreground-primary text-sm font-medium">{opt.title}</span>
              <span class="text-foreground-tertiary text-xs">{opt.description}</span>
            </button>
          </div>
        </div>

        <form class="space-y-4" phx-change="fork_title" phx-submit="continue_to_form">
          <h2 class="border-border-divider text-foreground-primary text-style-heading3Medium border-b pb-2">
            Title
          </h2>

          <input
            type="text"
            name="title"
            value={@dup_query}
            disabled={@create_mode == nil}
            phx-debounce="350"
            autocomplete="off"
            placeholder={fork_title_placeholder(@create_mode)}
            class="bg-surface-elevated border-border-divider text-foreground-primary h-10 w-full rounded-[6px] border px-3 py-2 outline-none disabled:opacity-50"
          />

          <p class="text-foreground-tertiary text-xs">
            {fork_hint(@create_mode, @dup_query, @dup_results)}
          </p>

          <div :if={@dup_results != []} class="flex flex-col gap-1.5">
            <a
              :for={dup <- @dup_results}
              href={"/vn/#{dup.slug}"}
              target="_blank"
              rel="noopener"
              class="border-border-divider flex items-center gap-2.5 rounded-[6px] border bg-transparent p-2 transition-colors hover:border-[rgb(var(--chip-border-hover))]"
            >
              <img
                :if={dup.image_url}
                src={dup.image_url}
                alt={dup.title}
                class="h-9 w-6 shrink-0 rounded object-cover"
              />
              <div :if={!dup.image_url} class="bg-surface-elevated h-9 w-6 shrink-0 rounded"></div>
              <div class="min-w-0 truncate text-sm">
                <span class="text-foreground-primary">{dup.title}</span>
                <span :if={dup.producers} class="text-foreground-tertiary">· {dup.producers}</span>
              </div>
            </a>
          </div>

          <div class="flex justify-end pt-2">
            <button
              type="submit"
              disabled={@create_mode == nil or String.trim(@dup_query) == ""}
              class={[
                "inline-flex items-center gap-1 rounded-[6px] border px-4 py-2 text-sm transition-colors",
                if(@create_mode != nil and String.trim(@dup_query) != "",
                  do:
                    "text-foreground-primary border-[rgb(var(--chip-border-default))] hover:border-[rgb(var(--chip-border-hover))]",
                  else: "border-border-divider text-foreground-quaternary cursor-not-allowed"
                )
              ]}
            >
              Continue →
            </button>
          </div>
        </form>
      </section>

      <form
        :if={@state == :editing or (@state == :creating and @create_step == :form)}
        id="vn-edit-form"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty_count > 0)}
        class="mt-8 space-y-10"
        phx-change="validate"
        phx-submit="save"
      >
        <.live_file_input upload={@uploads.new_screenshots} class="sr-only" />
        <.live_file_input upload={@uploads.new_covers} class="sr-only" />

        <div class="bg-surface-base/95 border-border-divider sticky top-0 z-20 -mx-4 border-b px-4 py-3 backdrop-blur xl:hidden">
          <div class="flex gap-2 overflow-x-auto pb-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <.link
              :for={{label, anchor} <- section_links(@state)}
              href={"##{anchor}"}
              class="shrink-0"
            >
              <span class="border-border-divider hover:border-foreground-quaternary hover:text-foreground-primary text-foreground-secondary text-style-captionRegular inline-flex rounded-full border px-3 py-1.5 transition-colors">
                {label}
              </span>
            </.link>
          </div>
        </div>

        <div class="relative">
          <aside class="hidden xl:block">
            <div class="fixed top-26 left-[max(1.5rem,calc(50%-35rem))] flex w-[148px] flex-col gap-1.5">
              <.link
                :for={{label, anchor} <- section_links(@state)}
                href={"##{anchor}"}
                class="hover:bg-surface-elevated/40 hover:text-foreground-secondary text-foreground-tertiary flex items-center gap-2 rounded-md px-3 py-2 text-left transition-colors"
              >
                <span class="bg-foreground-quaternary size-1.5 rounded-full" />
                <span class="text-style-captionRegular">{label}</span>
              </.link>
            </div>
          </aside>

          <div class="bg-surface-base border-border-divider flex flex-col gap-14 rounded-[8px] border p-4">
            <Sections.title_section
              form={@form}
              language_options={@language_options}
            />

            <Sections.general_section
              form={@form}
              development_status_options={@development_status_options}
              length_options={@length_options}
              language_options={@language_options}
              title_category_options={@title_category_options}
            />

            <Sections.relations_section
              form={@form}
              relation_query={@relation_query}
              relation_results={@relation_results}
              relation_type_options={relation_type_options()}
            />

            <Sections.screenshots_section :if={@state == :editing} form={@form} uploads={@uploads} />

            <Sections.covers_section :if={@state == :editing} form={@form} uploads={@uploads} />

            <fieldset
              :if={@can_moderate and @state == :editing}
              class="space-y-3 rounded-[8px] border border-amber-500/20 bg-amber-500/6 p-3"
            >
              <legend class="px-1 text-xs font-medium tracking-[0.06em] text-amber-400 uppercase">
                Moderation
              </legend>

              <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
                <input type="hidden" name="vn[is_hidden]" value="false" />
                <input
                  type="checkbox"
                  name="vn[is_hidden]"
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
                <input type="hidden" name="vn[is_locked]" value="false" />
                <input
                  type="checkbox"
                  name="vn[is_locked]"
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

            <section class="border-border-divider border-t pt-6">
              <div class="grid grid-cols-1 gap-4 md:grid-cols-[170px_minmax(0,1fr)] md:items-center">
                <label class="contents">
                  <span class="text-sm font-medium text-[rgb(var(--foreground-primary))]">
                    Summary
                  </span>
                  <input
                    type="text"
                    name="vn[summary]"
                    value={@form["summary"]}
                    placeholder="Brief change summary"
                    minlength="2"
                    maxlength="5000"
                    class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
                  />
                </label>
              </div>

              <div class="bg-surface-base/95 border-border-divider sticky bottom-3 z-20 mt-6 flex flex-wrap items-center justify-between gap-2 rounded-[8px] border px-3 py-2 backdrop-blur">
                <div class="text-xs text-[rgb(var(--foreground-tertiary))]">
                  <%= cond do %>
                    <% @live_action == :new -> %>
                      Add a title, then create the entry.
                    <% @dirty_count > 0 -> %>
                      {@dirty_count} changed field{if @dirty_count == 1, do: "", else: "s"}: {Enum.join(
                        @dirty_fields,
                        ", "
                      )}
                    <% true -> %>
                      No pending changes
                  <% end %>
                </div>

                <div class="flex items-center gap-3">
                  <button
                    type="submit"
                    disabled={@dirty_count == 0}
                    class={[
                      "rounded-[6px] border px-3 py-2 text-sm transition-colors",
                      if(@dirty_count > 0,
                        do:
                          "border-[rgb(var(--chip-border-default))] text-[rgb(var(--foreground-primary))] hover:border-[rgb(var(--chip-border-hover))]",
                        else:
                          "border-border-divider cursor-not-allowed text-[rgb(var(--foreground-quaternary))]"
                      )
                    ]}
                  >
                    {submit_label(assigns)}
                  </button>

                  <button
                    :if={@live_action == :new}
                    type="button"
                    onclick="history.back()"
                    class="text-sm text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
                  >
                    Cancel
                  </button>
                  <.link
                    :if={@live_action != :new}
                    navigate={back_path(assigns)}
                    class="text-sm text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
                  >
                    Cancel
                  </.link>
                </div>
              </div>
            </section>
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp require_editable(%{assigns: %{state: :editing}}), do: :ok
  defp require_editable(_socket), do: {:error, "This entry cannot be edited right now."}

  defp require_creator(%{assigns: %{state: :creating, current_user: user}}) when not is_nil(user),
    do: {:ok, user}

  defp require_creator(_socket),
    do: {:error, "You do not have permission to add a visual novel."}

  defp current_vn_id(%{assigns: %{vn: %{id: id}}}), do: id
  defp current_vn_id(_socket), do: nil

  defp ensure_changes_present(%{} = changes) when map_size(changes) == 0,
    do: {:error, "No changes detected."}

  defp ensure_changes_present(_changes), do: :ok

  defp edit_state(socket, state, vn, revisions, latest_revision, original_form) do
    page_title =
      case state do
        :editing -> "Edit #{vn.title}"
        _ -> "#{vn.title} · Edit"
      end

    assign(socket,
      state: state,
      vn: vn,
      revisions: revisions,
      base_revision: latest_revision,
      page_title: page_title,
      original_form: original_form,
      form: original_form,
      dirty_fields: [],
      dirty_count: 0,
      relation_query: "",
      relation_results: []
    )
  end

  defp assign_form(socket, form) do
    dirty_fields = Form.dirty_fields(socket.assigns.original_form, form)

    assign(socket,
      form: form,
      dirty_fields: dirty_fields,
      dirty_count: length(dirty_fields)
    )
  end

  defp relation_results(""), do: []

  defp relation_results(query) do
    case VisualNovels.search_visual_novels(query, 1, 6,
           include_nukige: true,
           include_adjacent: true
         ) do
      {:ok, %{items: items}} -> items
      %{} = result -> Map.get(result, :items, [])
      _ -> []
    end
  end

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp create_mode_options do
    [
      %{
        value: "jvn",
        atom: :jvn,
        title: "Japanese VN",
        description: "Translated or original Japanese visual novels"
      },
      %{
        value: "avn",
        atom: :avn,
        title: "Western AVN",
        description: "Patreon-funded indie ero, Ren'Py, F95 scene"
      },
      %{
        value: "other",
        atom: :other,
        title: "Other",
        description: "Western OELVNs, Korean / Chinese, doujin"
      }
    ]
  end

  defp parse_mode("jvn"), do: :jvn
  defp parse_mode("avn"), do: :avn
  defp parse_mode("other"), do: :other
  defp parse_mode(_), do: nil

  # Translate the chosen category into starting form defaults. Japanese VNs
  # default to a Japanese original language; AVNs default to English, flag
  # is_avn, and start in-development (mirrors the Next fork). "Other" gets
  # the neutral English default.
  defp form_for_mode(mode, title) do
    initial_lang = if mode == :jvn, do: "ja", else: "en"
    is_avn = mode == :avn

    Form.empty_form()
    |> Map.put("summary", "Initial creation")
    |> Map.put("original_language", initial_lang)
    |> Map.put("is_avn", is_avn)
    |> Map.put("development_status", if(is_avn, do: "in_development", else: ""))
    |> Map.put("titles", [
      %{"lang" => initial_lang, "title" => title, "latin" => "", "official" => is_avn}
    ])
  end

  defp fork_title_placeholder(:jvn), do: "Steins;Gate, Fata Morgana no Yakata..."
  defp fork_title_placeholder(:avn), do: "Eternum, Being a DIK, Pale Carnations..."
  defp fork_title_placeholder(_mode), do: "Title"

  defp fork_hint(nil, _query, _results), do: "Pick a category above to continue."

  defp fork_hint(_mode, query, results) do
    cond do
      String.length(String.trim(query)) < 2 -> "We'll check the catalog as you type."
      results == [] -> "Nothing similar in the catalog — looks new."
      true -> "Already in the catalog. Open an entry below instead of creating a duplicate."
    end
  end

  defp display_title(%{live_action: :new}), do: "Create visual novel"
  defp display_title(%{vn: %{title: title}}), do: title
  defp display_title(_assigns), do: "Edit visual novel"

  defp eyebrow_label(%{live_action: :new}), do: "Create"
  defp eyebrow_label(_assigns), do: "Edit"

  defp submit_label(%{live_action: :new}), do: "Create visual novel"
  defp submit_label(_assigns), do: "Save changes"

  defp auth_message(%{live_action: :new}), do: "Sign in to add a visual novel."
  defp auth_message(_assigns), do: "Sign in to edit this visual novel."

  defp forbidden_message(%{live_action: :new}),
    do: "You do not have permission to add a visual novel."

  defp forbidden_message(_assigns), do: "Your editing privileges have been revoked."

  defp back_path(%{slug: slug}) when is_binary(slug), do: "/vn/#{slug}"

  defp back_label(_assigns), do: "Back to visual novel"

  defp history_timestamp(nil), do: ""

  defp history_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %-d, %Y %H:%M")
  end

  defp history_user(%{user: %{display_name: display_name}})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp history_user(%{user: %{username: username}}) when is_binary(username), do: username
  defp history_user(_revision), do: "system"

  defp history_summary(%{summary: summary}) when is_binary(summary) and summary != "", do: summary

  defp history_summary(%{action: action}) when not is_nil(action),
    do: action |> to_string() |> String.replace("_", " ")

  defp history_summary(_revision), do: "edit"

  # Create mode omits Screenshots/Covers — images are added from the edit
  # screen after the entry exists (see `Form.to_create_attrs/1`).
  defp section_links(:creating) do
    [
      {"Titles", "vn-edit-title"},
      {"General", "vn-edit-general"},
      {"Relations", "vn-edit-relations"}
    ]
  end

  defp section_links(_state) do
    [
      {"Titles", "vn-edit-title"},
      {"General", "vn-edit-general"},
      {"Relations", "vn-edit-relations"},
      {"Screenshots", "vn-edit-screenshots"},
      {"Covers", "vn-edit-covers"}
    ]
  end

  defp normalize_text(nil), do: ""
  defp normalize_text(value), do: value |> to_string() |> String.trim()

  defp format_revision_error({:error, reason}), do: format_revision_error(reason)
  defp format_revision_error(reason) when is_binary(reason), do: reason
  defp format_revision_error(%Ecto.Changeset{} = changeset), do: format_changeset_error(changeset)
  defp format_revision_error(_), do: "Unable to save visual novel."

  defp format_changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end

  defp development_status_options do
    [
      {"Not set", ""},
      {"Finished", "finished"},
      {"In Development", "in_development"},
      {"On hold", "on_hiatus"},
      {"Abandoned", "abandoned"}
    ]
  end

  defp length_options do
    [
      {"Not set", ""},
      {"Short", "short"},
      {"Medium", "medium"},
      {"Long", "long"},
      {"Very long", "very_long"}
    ]
  end

  defp language_options do
    [
      {"Not set", ""},
      {"Japanese", "ja"},
      {"English", "en"},
      {"Chinese (Simplified)", "zh-Hans"},
      {"Chinese (Traditional)", "zh-Hant"},
      {"Korean", "ko"},
      {"Spanish", "es"},
      {"French", "fr"},
      {"German", "de"},
      {"Portuguese", "pt"},
      {"Russian", "ru"}
    ]
  end

  defp title_category_options do
    [
      {"Visual Novel", "vn"},
      {"Nukige", "nukige"},
      {"Adjacent", "adjacent"}
    ]
  end

  defp relation_type_options do
    [
      {"Sequel", "sequel"},
      {"Prequel", "prequel"},
      {"Fandisc", "fandisc"},
      {"Side story", "side_story"},
      {"Parent story", "parent_story"},
      {"Same setting", "same_setting"},
      {"Alternative version", "alternative"},
      {"Shares characters", "shares_characters"},
      {"Same series", "same_series"}
    ]
  end
end

defmodule KaguyaWeb.DeveloperLive.Edit do
  use KaguyaWeb, :live_view

  alias Kaguya.Producers
  alias Kaguya.Revisions
  alias Kaguya.Sync.VndbStorefrontMapper
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.DeveloperLive.Data

  @producer_type_options [
    {"Developer", "developer"},
    {"Developer + Publisher", "developer_publisher"},
    {"Publisher", "publisher"},
    {"Indie / Amateur", "amateur"}
  ]

  @language_options [
    {"Unknown", ""},
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

  @social_site_options [
    {"Website", "website"},
    {"Discord", "discord"},
    {"X (Twitter)", "twitter"},
    {"YouTube", "youtube"},
    {"Bluesky", "bsky"},
    {"Instagram", "instagram"},
    {"Facebook", "facebook"},
    {"GitHub", "github"},
    {"Patreon", "patreon"},
    {"Twitch", "twitch"},
    {"Steam", "steam"},
    {"Reddit", "reddit"},
    {"Mastodon", "mastodon"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Edit developer",
       state: :loading,
       producer: nil,
       base_revision: 0,
       original_form: empty_form(),
       form: empty_form(),
       dirty_fields: [],
       dirty_count: 0
     )}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :new}} = socket) do
    socket =
      assign(socket,
        slug: nil,
        producer: nil,
        page_title: "Create developer",
        base_revision: 0,
        original_form: empty_form(),
        form: empty_form(),
        dirty_fields: [],
        dirty_count: 0,
        producer_type_options: @producer_type_options,
        language_options: @language_options,
        social_site_options: @social_site_options
      )

    case socket.assigns.current_user do
      nil ->
        {:noreply, assign(socket, state: :auth_required, can_moderate: false)}

      current_user ->
        if can_edit?(current_user) do
          {:noreply,
           assign(socket, state: :creating, can_moderate: Data.can_moderate_db?(current_user))}
        else
          {:noreply, assign(socket, state: :forbidden, can_moderate: false)}
        end
    end
  end

  def handle_params(%{"slug" => slug}, _uri, socket) do
    producer_opts =
      if Data.can_moderate_db?(socket.assigns.current_user), do: [include_hidden: true], else: []

    case Producers.get_producer_by_slug(slug, producer_opts) do
      {:ok, producer} ->
        assign_edit_state(socket, slug, producer)

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           state: :not_found,
           page_title: "Developer not found · Kaguya"
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"developer" => attrs}, socket) do
    form =
      attrs
      |> sanitize_form()
      |> put_summary(Map.get(socket.assigns.form, "summary", ""))

    assign_dirty(socket, form)
  end

  @impl true
  def handle_event("add_link", _params, socket) do
    links = Map.get(socket.assigns.form, "external_links", [])

    form =
      Map.put(
        socket.assigns.form,
        "external_links",
        links ++ [%{"site" => "website", "value" => ""}]
      )

    assign_dirty(socket, form)
  end

  @impl true
  def handle_event("remove_link", %{"index" => index}, socket) do
    links = Map.get(socket.assigns.form, "external_links", [])
    form = Map.put(socket.assigns.form, "external_links", drop_index(links, index))
    assign_dirty(socket, form)
  end

  @impl true
  def handle_event("save", %{"developer" => attrs}, socket) do
    case socket.assigns.live_action do
      :new -> save_new(socket, attrs)
      _ -> save_edit(socket, attrs)
    end
  end

  # Create path. State was gated to :creating in handle_params (signed-in,
  # can_edit), so a non-permitted socket falls through to the no-op guard
  # below — the same defense-in-depth the edit path uses.
  defp save_new(socket, attrs) do
    form =
      attrs
      |> sanitize_form()
      |> put_summary(Map.get(attrs, "summary", ""))

    cond do
      socket.assigns.state != :creating ->
        {:noreply, socket}

      blank?(Map.get(form, "name")) ->
        {:noreply,
         socket
         |> assign_dirty(form)
         |> put_flash(:error, "Name is required.")}

      true ->
        summary = ensure_summary(Map.get(form, "summary"), :new)

        case Revisions.create_entity(
               :producer,
               to_create_attrs(form),
               summary,
               socket.assigns.current_user
             ) do
          {:ok, %{entity: producer}} ->
            {:noreply,
             socket
             |> put_flash(:info, "Developer created.")
             |> push_navigate(to: "/developer/#{producer.slug}")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign_dirty(form)
             |> put_flash(:error, format_revision_error(reason))}
        end
    end
  end

  defp save_edit(socket, attrs) do
    form =
      attrs
      |> sanitize_form()
      |> put_summary(Map.get(attrs, "summary", ""))

    changes = build_changes(socket.assigns.original_form, form)
    summary = ensure_summary(Map.get(form, "summary"), :edit)

    cond do
      socket.assigns.state != :editing ->
        {:noreply, socket}

      changes == %{} ->
        {:noreply,
         socket
         |> assign_dirty(form)
         |> put_flash(:error, "No changes detected.")}

      true ->
        case Revisions.submit_edit(
               :producer,
               socket.assigns.producer.id,
               changes,
               summary,
               socket.assigns.current_user,
               base_revision: socket.assigns.base_revision
             ) do
          {:ok, _change} ->
            {:noreply,
             socket
             |> put_flash(:info, "Developer updated.")
             |> push_navigate(to: "/developer/#{socket.assigns.slug}")}

          {:error, :edit_conflict} ->
            {:noreply,
             socket
             |> assign(
               :base_revision,
               Revisions.latest_revision_number(:producer, socket.assigns.producer.id)
             )
             |> assign_dirty(form)
             |> put_flash(
               :error,
               "This page was updated by someone else. Review your edits and submit again."
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign_dirty(form)
             |> put_flash(:error, format_revision_error(reason))}
        end
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
        :if={@live_action == :new}
        type="button"
        onclick="history.back()"
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back
      </button>
      <.link
        :if={@live_action != :new}
        navigate={"/developer/#{@slug}"}
        class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular mb-8 inline-flex items-center gap-1.5 transition-colors"
      >
        ← Back to developer
      </.link>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {heading(assigns)}
      </h1>

      <p :if={@producer} class="mt-1 text-sm text-[rgb(var(--foreground-secondary))]">
        {@producer.name}
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
        class="bg-surface-base border-border-divider mt-6 rounded-[8px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        This developer is locked and cannot be edited.
      </section>

      <form
        :if={@state in [:editing, :creating]}
        id="developer-edit-form"
        class="bg-surface-base border-border-divider mt-6 space-y-4 rounded-[8px] border p-4"
        phx-change="validate"
        phx-submit="save"
      >
        <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
          <span class="font-medium text-[rgb(var(--foreground-primary))]">Name</span>
          <input
            name="developer[name]"
            type="text"
            maxlength="255"
            value={@form["name"]}
            class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          />
        </label>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Type</span>
            <select
              name="developer[producer_type]"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option value="">Unknown</option>
              <option
                :for={{label, value} <- @producer_type_options}
                value={value}
                selected={@form["producer_type"] == value}
              >
                {label}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <span class="font-medium text-[rgb(var(--foreground-primary))]">Language</span>
            <select
              name="developer[language]"
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option
                :for={{label, value} <- @language_options}
                value={value}
                selected={@form["language"] == value}
              >
                {label}
              </option>
            </select>
          </label>
        </div>

        <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
          <span class="font-medium text-[rgb(var(--foreground-primary))]">Description</span>
          <textarea
            name="developer[description]"
            rows="8"
            maxlength="5000"
            class="bg-surface-elevated border-border-divider min-h-[180px] rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          ><%= @form["description"] %></textarea>
        </label>

        <div class="border-border-divider space-y-3 rounded-[8px] border p-3">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-medium text-[rgb(var(--foreground-primary))]">External links</h2>
            <button
              type="button"
              phx-click="add_link"
              class="rounded-[6px] border border-[rgb(var(--chip-border-default))] px-2.5 py-1 text-xs text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
            >
              Add link
            </button>
          </div>

          <div
            :if={@form["external_links"] == []}
            class="text-xs text-[rgb(var(--foreground-tertiary))]"
          >
            No links added.
          </div>

          <div
            :for={{link, index} <- Enum.with_index(@form["external_links"])}
            class="grid grid-cols-1 gap-2 md:grid-cols-[190px_minmax(0,1fr)_auto]"
          >
            <select
              name={"developer[external_links][#{index}][site]"}
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option
                :for={{label, value} <- @social_site_options}
                value={value}
                selected={link["site"] == value}
              >
                {label}
              </option>
            </select>

            <input
              type="text"
              name={"developer[external_links][#{index}][value]"}
              value={link["value"]}
              placeholder={link_placeholder(link["site"])}
              class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] outline-none"
            />

            <button
              type="button"
              phx-click="remove_link"
              phx-value-index={index}
              class="border-border-divider rounded-[6px] border px-3 py-2 text-xs text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
            >
              Remove
            </button>
          </div>
        </div>

        <fieldset
          :if={@can_moderate and @state == :editing}
          class="space-y-3 rounded-[8px] border border-amber-500/20 bg-amber-500/6 p-3"
        >
          <legend class="px-1 text-xs font-medium tracking-[0.06em] text-amber-400 uppercase">
            Moderation
          </legend>

          <label class="flex items-start gap-2.5 text-sm text-[rgb(var(--foreground-secondary))]">
            <input
              type="hidden"
              name="developer[is_hidden]"
              value="false"
            />
            <input
              type="checkbox"
              name="developer[is_hidden]"
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
            <input
              type="hidden"
              name="developer[is_locked]"
              value="false"
            />
            <input
              type="checkbox"
              name="developer[is_locked]"
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
          <span class="font-medium text-[rgb(var(--foreground-primary))]">Edit summary</span>
          <input
            name="developer[summary]"
            type="text"
            minlength="2"
            maxlength="5000"
            value={@form["summary"]}
            placeholder="Briefly describe what changed"
            class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          />
        </label>

        <div class="bg-surface-base/95 border-border-divider sticky bottom-3 z-20 flex flex-wrap items-center justify-between gap-2 rounded-[8px] border px-3 py-2 backdrop-blur">
          <div class="text-xs text-[rgb(var(--foreground-tertiary))]">
            <%= if @dirty_count > 0 do %>
              {@dirty_count} changed field{if @dirty_count == 1, do: "", else: "s"}: {Enum.join(
                @dirty_fields,
                ", "
              )}
            <% else %>
              No pending changes
            <% end %>
          </div>

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
        </div>
      </form>
    </div>
    """
  end

  defp assign_edit_state(socket, slug, producer) do
    current_user = socket.assigns.current_user
    can_moderate = Data.can_moderate_db?(current_user)
    can_edit = Producers.can_edit_producer?(producer, current_user)

    {state, form, original_form, dirty_fields, dirty_count} =
      cond do
        is_nil(current_user) ->
          {:auth_required, empty_form(), empty_form(), [], 0}

        # Lock check comes BEFORE the generic !can_edit branch so non-mods
        # on a locked entry see the specific "locked" reason instead of a
        # vague "you don't have permission." Mods bypass — they unlock from
        # the mod-only fieldset on this same form.
        producer.is_locked and not can_moderate ->
          {:locked, empty_form(), empty_form(), [], 0}

        !can_edit ->
          {:forbidden, empty_form(), empty_form(), [], 0}

        true ->
          initial_form = form_from_producer(producer)
          {:editing, initial_form, initial_form, [], 0}
      end

    {:noreply,
     assign(socket,
       slug: slug,
       producer: producer,
       page_title: "Edit #{producer.name}",
       state: state,
       can_moderate: can_moderate,
       base_revision: Revisions.latest_revision_number(:producer, producer.id),
       original_form: original_form,
       form: form,
       dirty_fields: dirty_fields,
       dirty_count: dirty_count,
       producer_type_options: @producer_type_options,
       language_options: @language_options,
       social_site_options: @social_site_options
     )}
  end

  defp assign_dirty(socket, form) do
    dirty_fields = changed_fields(socket.assigns.original_form, form)

    {:noreply,
     assign(socket,
       form: form,
       dirty_fields: dirty_fields,
       dirty_count: length(dirty_fields)
     )}
  end

  defp form_from_producer(producer) do
    %{
      "name" => producer.name || "",
      "description" => producer.description || "",
      "producer_type" => producer.producer_type || "",
      "language" => producer.language || "",
      "summary" => "",
      "external_links" => normalize_external_links(Map.get(producer, :external_links, [])),
      "is_hidden" => not is_nil(producer.hidden_at),
      "is_locked" => producer.is_locked || false
    }
  end

  defp empty_form do
    %{
      "name" => "",
      "description" => "",
      "producer_type" => "",
      "language" => "",
      "summary" => "",
      "external_links" => [],
      "is_hidden" => false,
      "is_locked" => false
    }
  end

  defp sanitize_form(attrs) do
    %{
      "name" => normalize_text(Map.get(attrs, "name")),
      "description" => normalize_text(Map.get(attrs, "description")),
      "producer_type" => normalize_text(Map.get(attrs, "producer_type")),
      "language" => normalize_text(Map.get(attrs, "language")),
      "external_links" => normalize_external_links(Map.get(attrs, "external_links")),
      "is_hidden" => truthy?(Map.get(attrs, "is_hidden")),
      "is_locked" => truthy?(Map.get(attrs, "is_locked"))
    }
    |> put_summary(Map.get(attrs, "summary", ""))
  end

  # Checkbox values arrive as the literal string "true" / "on" / true. Anything
  # else (missing, "false", "off", nil) reads as false. Mirror this on the
  # server even though `Kaguya.Revisions` enforces the actual permission
  # boundary — preventing forged params from a non-mod from ever reaching
  # changes is defense in depth.
  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("on"), do: true
  defp truthy?(_), do: false

  defp put_summary(form, summary), do: Map.put(form, "summary", normalize_text(summary))

  defp build_changes(original_form, form) do
    scalar_changes =
      [:name, :description, :producer_type, :language]
      |> Enum.reduce(%{}, fn field, acc ->
        key = Atom.to_string(field)
        current = Map.get(form, key, "")
        original = Map.get(original_form, key, "")

        if current != original do
          Map.put(acc, field, blank_to_nil(current))
        else
          acc
        end
      end)

    scalar_changes
    |> maybe_put_external_links(original_form, form)
    |> maybe_put_mod_fields(original_form, form)
  end

  defp maybe_put_external_links(changes, original_form, form) do
    if Map.get(form, "external_links", []) != Map.get(original_form, "external_links", []) do
      Map.put(
        changes,
        :external_links,
        to_external_links_payload(Map.get(form, "external_links", []))
      )
    else
      changes
    end
  end

  # Sends the underlying schema fields (`:hidden_at` as datetime-or-nil,
  # `:is_locked` as boolean) only when the corresponding form toggle actually
  # changed. `Kaguya.Revisions.submit_edit/6` is the security boundary —
  # if a non-mod forges these into the payload, sanitize_mod_fields/2 drops
  # them server-side regardless of what's sent here.
  defp maybe_put_mod_fields(changes, original_form, form) do
    changes
    |> maybe_put_hidden_at(original_form, form)
    |> maybe_put_is_locked(original_form, form)
  end

  defp maybe_put_hidden_at(changes, original_form, form) do
    if Map.get(form, "is_hidden") != Map.get(original_form, "is_hidden") do
      Map.put(changes, :hidden_at, hidden_at_value(Map.get(form, "is_hidden")))
    else
      changes
    end
  end

  defp maybe_put_is_locked(changes, original_form, form) do
    if Map.get(form, "is_locked") != Map.get(original_form, "is_locked") do
      Map.put(changes, :is_locked, Map.get(form, "is_locked"))
    else
      changes
    end
  end

  defp hidden_at_value(true), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp hidden_at_value(_), do: nil

  defp changed_fields(original_form, form) do
    scalar_labels =
      [
        {"name", "name"},
        {"description", "description"},
        {"producer_type", "type"},
        {"language", "language"}
      ]
      |> Enum.flat_map(fn {key, label} ->
        if Map.get(form, key, "") != Map.get(original_form, key, ""), do: [label], else: []
      end)

    scalar_labels
    |> maybe_append_links_label(original_form, form)
    |> maybe_append_mod_labels(original_form, form)
  end

  defp maybe_append_links_label(labels, original_form, form) do
    if Map.get(form, "external_links", []) != Map.get(original_form, "external_links", []) do
      labels ++ ["links"]
    else
      labels
    end
  end

  defp maybe_append_mod_labels(labels, original_form, form) do
    hidden_label =
      if Map.get(form, "is_hidden") != Map.get(original_form, "is_hidden"),
        do: ["visibility"],
        else: []

    lock_label =
      if Map.get(form, "is_locked") != Map.get(original_form, "is_locked"),
        do: ["lock"],
        else: []

    labels ++ hidden_label ++ lock_label
  end

  defp normalize_external_links(nil), do: []

  defp normalize_external_links(links) when is_map(links) do
    links
    |> Enum.sort_by(fn {idx, _} ->
      case Integer.parse(to_string(idx)) do
        {value, _} -> value
        _ -> 0
      end
    end)
    |> Enum.map(fn {_idx, value} -> value end)
    |> normalize_external_links()
  end

  defp normalize_external_links(links) when is_list(links) do
    links
    |> Enum.map(&normalize_link_entry/1)
    |> Enum.filter(&is_map/1)
    |> Enum.uniq_by(&{&1["site"], &1["value"]})
  end

  defp normalize_external_links(_), do: []

  defp normalize_link_entry(%{site: site, value: value}),
    do: normalize_link_entry(%{"site" => site, "value" => value})

  defp normalize_link_entry(%{"site" => site, "value" => value}) do
    site = normalize_text(site) |> String.downcase()
    value = normalize_text(value)

    cond do
      site == "" and value == "" ->
        nil

      site == "" ->
        normalize_link_entry(%{"site" => "website", "value" => value})

      value == "" ->
        nil

      true ->
        {normalized_site, normalized_value} = normalize_site_value(site, value)
        %{"site" => normalized_site, "value" => normalized_value}
    end
  end

  defp normalize_link_entry(_), do: nil

  defp normalize_site_value(site, value) do
    with {:ok, uri} <- parse_http_url(value),
         {:ok, extracted} <- extract_link_value(site, uri) do
      {site, extracted}
    else
      _ ->
        if looks_like_http_url?(value) and site not in ["website", "discord"] do
          {"website", value}
        else
          {site, value}
        end
    end
  end

  defp extract_link_value("website", _uri), do: :error
  defp extract_link_value("discord", _uri), do: :error

  defp extract_link_value(site, %URI{host: host, path: path})
       when is_binary(site) and is_binary(host) do
    segments =
      (path || "")
      |> String.trim("/")
      |> String.split("/", trim: true)

    downcased_host = String.downcase(host)

    case site do
      "twitter" ->
        extract_by_hosts(downcased_host, segments, ["twitter.com", "x.com"], &first_segment/1)

      "youtube" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["youtube.com", "www.youtube.com", "youtu.be"],
          fn segs ->
            case segs do
              ["@" <> handle | _] when handle != "" -> {:ok, handle}
              ["channel", id | _] when id != "" -> {:ok, id}
              [id] when id != "" -> {:ok, id}
              _ -> :error
            end
          end
        )

      "bsky" ->
        extract_by_hosts(downcased_host, segments, ["bsky.app"], fn segs ->
          case segs do
            ["profile", did | _] when did != "" -> {:ok, did}
            _ -> :error
          end
        end)

      "instagram" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["instagram.com", "www.instagram.com"],
          &first_segment/1
        )

      "facebook" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["facebook.com", "www.facebook.com"],
          &first_segment/1
        )

      "github" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["github.com", "www.github.com"],
          &first_segment/1
        )

      "patreon" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["patreon.com", "www.patreon.com"],
          &first_segment/1
        )

      "twitch" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["twitch.tv", "www.twitch.tv"],
          &first_segment/1
        )

      "reddit" ->
        extract_by_hosts(downcased_host, segments, ["reddit.com", "www.reddit.com"], fn segs ->
          case segs do
            ["u", user | _] when user != "" -> {:ok, user}
            [user | _] when user != "" -> {:ok, user}
            _ -> :error
          end
        end)

      "steam" ->
        extract_by_hosts(
          downcased_host,
          segments,
          ["store.steampowered.com", "steamcommunity.com"],
          fn segs ->
            case segs do
              ["app", id | _] when id != "" -> {:ok, id}
              ["curator", id | _] when id != "" -> {:ok, id}
              ["id", id | _] when id != "" -> {:ok, id}
              _ -> :error
            end
          end
        )

      "mastodon" ->
        extract_by_hosts(downcased_host, segments, [], fn segs ->
          case segs do
            ["@" <> user | _] when user != "" -> {:ok, user}
            _ -> :error
          end
        end)

      _ ->
        :error
    end
  end

  defp extract_link_value(_site, _uri), do: :error

  defp extract_by_hosts(host, segments, allowed_hosts, extractor) do
    if allowed_hosts == [] or host in allowed_hosts do
      extractor.(segments)
    else
      :error
    end
  end

  defp first_segment([value | _]) when value != "", do: {:ok, value}
  defp first_segment(_), do: :error

  defp parse_http_url(value) when is_binary(value) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      {:ok, uri}
    else
      :error
    end
  end

  defp looks_like_http_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  defp looks_like_http_url?(_), do: false

  defp to_external_links_payload(links) do
    Enum.map(links, fn %{"site" => site, "value" => value} ->
      %{site: site, value: value}
    end)
  end

  defp drop_index(values, index) do
    with {position, ""} <- Integer.parse(to_string(index)) do
      values
      |> Enum.with_index()
      |> Enum.reject(fn {_item, current} -> current == position end)
      |> Enum.map(fn {item, _current} -> item end)
    else
      _ -> values
    end
  end

  defp ensure_summary("", :new), do: "Created developer"
  defp ensure_summary("", _action), do: "Updated developer"
  defp ensure_summary(summary, _action), do: summary

  # Build the attrs map for `Producers.create_from_edit/1`. Mirrors the
  # Next.js producer create form (name/description/type/language + links);
  # the whole form maps cleanly, so there are no deferred fields here.
  defp to_create_attrs(form) do
    %{
      name: blank_to_nil(Map.get(form, "name")),
      description: blank_to_nil(Map.get(form, "description")),
      producer_type: blank_to_nil(Map.get(form, "producer_type")),
      language: blank_to_nil(Map.get(form, "language")),
      external_links: to_external_links_payload(Map.get(form, "external_links", []))
    }
  end

  defp blank?(value), do: normalize_text(value) == ""

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp heading(%{live_action: :new}), do: "Create developer"
  defp heading(_assigns), do: "Edit developer"

  defp submit_label(%{live_action: :new}), do: "Create developer"
  defp submit_label(_assigns), do: "Save changes"

  defp auth_message(%{live_action: :new}), do: "Sign in to add a developer."
  defp auth_message(_assigns), do: "Sign in to edit this developer."

  defp forbidden_message(%{live_action: :new}),
    do: "You do not have permission to add a developer."

  defp forbidden_message(_assigns), do: "You do not have permission to edit this developer."

  defp normalize_text(nil), do: ""
  defp normalize_text(value), do: value |> to_string() |> String.trim()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp link_placeholder(site) when is_binary(site) do
    case String.downcase(site) do
      "website" -> "https://example.com"
      "discord" -> "https://discord.gg/..."
      _ -> raw_value_hint(site)
    end
  end

  defp link_placeholder(_), do: "https://example.com"

  defp raw_value_hint(site) do
    "#{VndbStorefrontMapper.label(site)} ID or username"
  end

  defp format_revision_error(reason) when is_binary(reason), do: reason
  defp format_revision_error(:not_found), do: "Developer not found."
  defp format_revision_error(%Ecto.Changeset{} = changeset), do: format_changeset_error(changeset)
  defp format_revision_error(_), do: "Unable to save developer."

  defp format_changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end

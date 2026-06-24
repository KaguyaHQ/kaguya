defmodule KaguyaWeb.ChangesLive.Show do
  use KaguyaWeb, :live_view

  import Ecto.Query
  import KaguyaWeb.UI.Button, only: [button: 1]

  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Users.User
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.Components.Shared.RevisionDiffTable
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       page_title: "Change • Kaguya",
       change: nil,
       previous_change: nil,
       next_change: nil,
       current_snapshot: nil,
       previous_snapshot: nil,
       diff_entries: [],
       entity: nil,
       entity_type_label: nil,
       action_label: nil,
       summary: nil,
       source_label: nil,
       relative_time: nil,
       inserted_at_label: nil,
       user: nil,
       back_href: "/history",
       previous_href: nil,
       next_href: nil,
       edit_href: nil,
       previous_revision_meta: nil,
       current_revision_meta: nil,
       show_revert?: false,
       revert_form: revert_form(),
       revert_error: nil,
       reverting?: false,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"revision_id" => revision_id}, _uri, socket) do
    load_revision(socket, revision_id)
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    load_revision(socket, id)
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-8 max-w-6xl px-4 pb-20 sm:px-6 lg:mt-10">
      <div class="mb-5 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <.link
          navigate={@back_href}
          class="hover:text-foreground-primary text-foreground-tertiary text-sm transition-colors"
        >
          &larr; Back to history
        </.link>

        <div class="text-foreground-tertiary flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
          <button
            type="button"
            data-share-button
            class="hover:text-foreground-primary transition-colors"
          >
            Copy link
          </button>
          <span :if={@edit_href} aria-hidden="true">·</span>
          <.link
            :if={@edit_href}
            navigate={@edit_href}
            class="hover:text-foreground-primary transition-colors"
          >
            Edit entity
          </.link>
        </div>
      </div>

      <section :if={@change} class="space-y-6">
        <header>
          <p :if={@entity && @entity[:title]} class="text-foreground-tertiary text-sm">
            <.link
              :if={@entity[:href]}
              navigate={@entity[:href]}
              class="hover:text-foreground-primary transition-colors hover:underline"
            >
              {@entity[:title]}
            </.link>
            <span :if={!@entity[:href]}>{@entity[:title]}</span>
            <span aria-hidden="true">·</span>
            <span class="lowercase">{@entity_type_label}</span>
          </p>

          <div class="mt-1 flex flex-wrap items-baseline gap-x-4 gap-y-2">
            <.link
              :if={@previous_href}
              navigate={@previous_href}
              class="hover:text-foreground-primary text-foreground-tertiary text-sm transition-colors"
            >
              &larr; earlier
            </.link>
            <h1 class="text-foreground-primary text-2xl font-semibold">
              Revision r{@change.revision_number}
            </h1>
            <span
              :if={@change.action == :revert}
              class="bg-action-revert/10 border-action-revert/40 text-foreground-primary rounded-full border px-2 py-0.5 text-xs font-medium"
            >
              Revert
            </span>
            <.link
              :if={@next_href}
              navigate={@next_href}
              class="hover:text-foreground-primary text-foreground-tertiary ml-auto text-sm transition-colors"
            >
              later &rarr;
            </.link>
          </div>

          <p class="text-foreground-secondary mt-2 text-sm">
            {@action_label}
            <span aria-hidden="true" class="text-foreground-tertiary">·</span>
            by
            <.link
              :if={@user[:href]}
              navigate={@user[:href]}
              class="text-foreground-primary transition-colors hover:underline"
            >
              {@user[:display_name]}
            </.link>
            <span :if={!@user[:href]} class="text-foreground-primary">{@user[:display_name]}</span>
            <span aria-hidden="true" class="text-foreground-tertiary">·</span>
            <time title={@inserted_at_label} class="text-foreground-tertiary">
              {@relative_time}
            </time>
            <span :if={@source_label} aria-hidden="true" class="text-foreground-tertiary">·</span>
            <span :if={@source_label} class="text-foreground-tertiary">{@source_label}</span>
          </p>

          <p
            :if={@summary && String.trim(@summary) != ""}
            class="border-l-border-divider text-foreground-primary mt-3 border-l-2 pl-3 text-sm italic"
          >
            {@summary}
          </p>

          <div :if={@show_revert?} class="mt-5">
            <.button
              id="revision-revert-toggle"
              type="button"
              variant="destructive"
              size="small"
              phx-click="toggle_revert"
            >
              <Lucide.rotate_ccw class="mr-2 size-4" aria-hidden /> Revert to this
            </.button>
          </div>
        </header>

        <section
          :if={@reverting?}
          id="revision-revert-panel"
          class="bg-action-revert/10 border-action-revert/40 rounded-[8px] border p-4"
        >
          <.form for={@revert_form} id="revision-revert-form" phx-submit="submit_revert">
            <label
              for="revision-revert-summary"
              class="text-foreground-primary text-sm font-medium"
            >
              Revert summary
            </label>
            <textarea
              id="revision-revert-summary"
              name={@revert_form[:summary].name}
              rows="3"
              class="bg-surface-base border-text-field-border focus:border-text-field-border-focus placeholder:text-foreground-quaternary text-foreground-primary mt-2 w-full rounded-[6px] border px-3 py-2 text-sm focus:outline-hidden"
              placeholder="Describe why this revert is needed"
            ><%= @revert_form[:summary].value %></textarea>
            <p :if={@revert_error} class="mt-2 text-sm text-red-300">{@revert_error}</p>
            <div class="mt-3 flex flex-wrap justify-end gap-2">
              <.button type="button" variant="ghost" size="small" phx-click="cancel_revert">
                Cancel
              </.button>
              <.button type="submit" variant="brand" size="small">
                Submit revert
              </.button>
            </div>
          </.form>
        </section>

        <div
          :if={is_nil(@previous_change)}
          id="revision-initial-empty"
          class="bg-surface-base border-border-divider rounded-[8px] border px-5 py-8 text-center"
        >
          <p class="text-foreground-primary text-sm font-medium">
            No previous state to compare.
          </p>
          <p class="text-foreground-tertiary mt-1 text-sm">
            This is the first recorded revision for this entry.
          </p>
        </div>

        <RevisionDiffTable.diff_table
          :if={@previous_change}
          diff_entries={@diff_entries}
          current_snapshot={@current_snapshot}
          previous_snapshot={@previous_snapshot}
          entity_type={@change.entity_type}
          current_user={@current_user}
          previous_revision_meta={@previous_revision_meta}
          current_revision_meta={@current_revision_meta}
        />
      </section>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_revert", _params, socket) do
    if socket.assigns.show_revert? do
      {:noreply,
       assign(socket,
         reverting?: !socket.assigns.reverting?,
         revert_error: nil,
         revert_form: revert_form()
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_revert", _params, socket) do
    {:noreply, assign(socket, reverting?: false, revert_error: nil, revert_form: revert_form())}
  end

  def handle_event("submit_revert", params, socket) do
    summary =
      params
      |> get_in(["revert", "summary"])
      |> Kernel.||("")
      |> String.trim()

    cond do
      !socket.assigns.show_revert? ->
        {:noreply, socket}

      String.length(summary) < 2 ->
        {:noreply,
         assign(socket,
           reverting?: true,
           revert_error: "Summary must be at least 2 characters.",
           revert_form: revert_form(%{"summary" => summary})
         )}

      true ->
        case Revisions.revert_to_revision(
               socket.assigns.change.id,
               summary,
               socket.assigns.current_user
             ) do
          {:ok, _change} ->
            {:noreply,
             socket
             |> put_flash(:info, "Revision reverted.")
             |> push_navigate(to: socket.assigns.back_href)}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               reverting?: true,
               revert_error: revert_error_message(reason),
               revert_form: revert_form(%{"summary" => summary})
             )}
        end
    end
  end

  defp load_revision(socket, revision_id) do
    case Revisions.diff_revisions(revision_id) do
      {:ok, payload} ->
        change = payload.change
        entities = Revisions.batch_load_entities([{change.entity_type, change.entity_id}])
        entity = Map.get(entities, {change.entity_type, change.entity_id})
        normalized_entity = normalize_entity(change.entity_type, entity)
        user = change.user_id && Repo.one(from(u in User, where: u.id == ^change.user_id))
        next_change = next_change(change)

        canonical_revision_href =
          revision_href(change.entity_type, normalized_entity, change.id) ||
            "/history/#{change.id}"

        back_href = history_href(change.entity_type, normalized_entity) || "/history"

        {:noreply,
         assign(socket,
           page_title: "Revision r#{change.revision_number} • Kaguya",
           change: change,
           previous_change: payload.previous_change,
           next_change: next_change,
           current_snapshot: payload.current,
           previous_snapshot: payload.previous,
           diff_entries: payload.diff || [],
           entity: normalized_entity,
           entity_type_label: entity_type_label(change.entity_type),
           action_label: action_label(change.action),
           summary: change.summary,
           source_label: source_label(change.source),
           relative_time: SharedTime.calendar_custom(change.inserted_at),
           inserted_at_label: SharedTime.format_datetime_short(change.inserted_at),
           user: normalize_user(user),
           back_href: back_href,
           previous_href:
             previous_href(change.entity_type, normalized_entity, payload.previous_change),
           next_href: next_href(change.entity_type, normalized_entity, next_change),
           edit_href:
             edit_href(change.entity_type, normalized_entity, socket.assigns.current_user),
           previous_revision_meta:
             revision_meta(change.entity_type, normalized_entity, payload.previous_change),
           current_revision_meta:
             revision_meta(change.entity_type, normalized_entity, change,
               href: canonical_revision_href
             ),
           show_revert?: show_revert?(socket.assigns.current_user, normalized_entity),
           revert_form: revert_form(),
           revert_error: nil,
           reverting?: false
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           page_title: "Change not found · Kaguya",
           not_found?: true
         )}
    end
  end

  defp normalize_entity(_type, nil) do
    %{id: nil, slug: nil, title: "Deleted entry", href: nil, is_locked: false}
  end

  defp normalize_entity(:visual_novel, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.title,
      href: "/vn/#{entity.slug}",
      is_locked: entity.is_locked
    }
  end

  defp normalize_entity(:character, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/character/#{entity.slug}",
      is_locked: entity.is_locked
    }
  end

  defp normalize_entity(:producer, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/developer/#{entity.slug}",
      is_locked: entity.is_locked
    }
  end

  defp normalize_entity(:release, entity) do
    %{
      id: entity && entity.id,
      slug: release_parent_slug(entity),
      vn_slug: release_parent_slug(entity),
      title: entity && (entity.display_title || entity.title || "Release"),
      href: release_href(entity),
      is_locked: entity && entity.is_locked
    }
  end

  defp normalize_entity(:series, entity) do
    %{
      id: entity.id,
      slug: entity.slug,
      title: entity.name,
      href: "/series/#{entity.slug}",
      is_locked: entity.is_locked
    }
  end

  defp entity_type_label(:visual_novel), do: "Visual novel"
  defp entity_type_label(:character), do: "Character"
  defp entity_type_label(:producer), do: "Producer"
  defp entity_type_label(:release), do: "Release"
  defp entity_type_label(:series), do: "Series"
  defp entity_type_label(type), do: to_string(type)

  defp action_label(:create), do: "Created"
  defp action_label(:edit), do: "Edited"
  defp action_label(:revert), do: "Reverted"
  defp action_label(:hide), do: "Hidden"
  defp action_label(:unhide), do: "Unhidden"
  defp action_label(:lock), do: "Locked"
  defp action_label(:unlock), do: "Unlocked"
  defp action_label(action), do: to_string(action)

  defp source_label(:user), do: nil
  defp source_label(:vndb_sync), do: "VNDB sync"
  defp source_label(:system), do: "System"
  defp source_label(_), do: nil

  defp release_parent_slug(%{visual_novel: %{slug: slug}}), do: slug
  defp release_parent_slug(_), do: nil

  defp release_href(%{visual_novel: %{slug: slug}}), do: "/vn/#{slug}"
  defp release_href(_entity), do: nil

  defp normalize_user(nil), do: %{display_name: "System", href: nil}

  defp normalize_user(user) do
    %{
      display_name: user.display_name || user.username || "User",
      href: user.username && "/@#{user.username}"
    }
  end

  defp history_href(:visual_novel, %{slug: slug}) when is_binary(slug), do: "/vn/#{slug}/history"

  defp history_href(:character, %{slug: slug}) when is_binary(slug),
    do: "/character/#{slug}/history"

  defp history_href(:producer, %{slug: slug}) when is_binary(slug),
    do: "/developer/#{slug}/history"

  defp history_href(:series, %{slug: slug}) when is_binary(slug), do: "/series/#{slug}/history"
  defp history_href(:release, %{vn_slug: slug}) when is_binary(slug), do: "/vn/#{slug}/history"
  defp history_href(_, _), do: nil

  defp previous_href(_entity_type, _entity, nil), do: nil

  defp previous_href(entity_type, entity, previous_change) do
    revision_href(entity_type, entity, previous_change.id) || "/history/#{previous_change.id}"
  end

  defp next_href(_entity_type, _entity, nil), do: nil

  defp next_href(entity_type, entity, next_change) do
    revision_href(entity_type, entity, next_change.id) || "/history/#{next_change.id}"
  end

  defp next_change(change) do
    from(c in Revisions.Change,
      where:
        c.entity_type == ^change.entity_type and c.entity_id == ^change.entity_id and
          c.revision_number > ^change.revision_number,
      order_by: [asc: c.revision_number],
      limit: 1
    )
    |> Repo.one()
  end

  defp revision_href(:visual_novel, %{slug: slug}, change_id) when is_binary(slug),
    do: "/vn/#{slug}/history/#{change_id}"

  defp revision_href(:character, %{slug: slug}, change_id) when is_binary(slug),
    do: "/character/#{slug}/history/#{change_id}"

  defp revision_href(:producer, %{slug: slug}, change_id) when is_binary(slug),
    do: "/developer/#{slug}/history/#{change_id}"

  defp revision_href(:series, %{slug: slug}, change_id) when is_binary(slug),
    do: "/series/#{slug}/history/#{change_id}"

  defp revision_href(:release, %{id: id, vn_slug: slug}, change_id)
       when is_binary(slug) and is_binary(id),
       do: "/vn/#{slug}/release/#{id}/history/#{change_id}"

  defp revision_href(_, _entity, _change_id), do: nil

  defp edit_href(entity_type, entity, user) do
    if can_edit?(user) and not locked?(entity) do
      entity_edit_href(entity_type, entity)
    end
  end

  defp entity_edit_href(:visual_novel, %{slug: slug}) when is_binary(slug), do: "/vn/#{slug}/edit"

  defp entity_edit_href(:character, %{slug: slug}) when is_binary(slug),
    do: "/character/#{slug}/edit"

  defp entity_edit_href(:producer, %{slug: slug}) when is_binary(slug),
    do: "/developer/#{slug}/edit"

  defp entity_edit_href(_, _), do: nil

  defp revision_meta(entity_type, entity, change, opts \\ [])

  defp revision_meta(_entity_type, _entity, nil, _opts), do: nil

  defp revision_meta(entity_type, entity, change, opts) do
    href = Keyword.get(opts, :href) || revision_href(entity_type, entity, change.id)
    user = user_for_change(change)

    %{
      revision_number: change.revision_number,
      action_label: action_label(change.action),
      summary: change.summary,
      author: normalize_user(user),
      inserted_at_label: SharedTime.format_datetime_short(change.inserted_at),
      href: href
    }
  end

  defp user_for_change(%{user: %User{} = user}), do: user

  defp user_for_change(%{user_id: user_id}) when is_binary(user_id) do
    Repo.one(from(u in User, where: u.id == ^user_id))
  end

  defp user_for_change(_change), do: nil

  defp show_revert?(%{id: _} = user, entity) do
    can_edit?(user) and not locked?(entity)
  end

  defp show_revert?(_user, _entity), do: false

  defp can_edit?(%{id: _} = user), do: Map.get(user, :can_edit, true) != false
  defp can_edit?(_), do: false

  defp locked?(%{is_locked: true}), do: true
  defp locked?(_), do: false

  defp revert_form(params \\ %{"summary" => ""}) do
    to_form(params, as: :revert)
  end

  defp revert_error_message(reason) when is_binary(reason), do: reason
  defp revert_error_message(:not_found), do: "Revision not found."

  defp revert_error_message(:permission_denied),
    do: "You do not have permission to revert this revision."

  defp revert_error_message(reason), do: "Could not revert revision: #{inspect(reason)}"
end

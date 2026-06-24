defmodule KaguyaWeb.CharacterLive.History do
  use KaguyaWeb, :live_view

  import Ecto.Query

  alias Kaguya.Characters
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.ChangedFields
  alias Kaguya.Users.User
  alias KaguyaWeb.Components.Shared.NotFoundPage

  @page_size 25
  @max_page 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       page_title: "Character history",
       character: nil,
       revisions: [],
       page: 1,
       total_count: 0,
       total_pages: 1,
       has_previous: false,
       has_next: false,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    page = Map.get(params, "page") |> parse_page()

    case Characters.get_character_page_by_slug(slug, socket.assigns.current_user) do
      {:ok, page_data} ->
        revisions = load_revisions(page_data.character.id, page)

        total_count = Revisions.revision_count(:character, page_data.character.id)

        total_pages =
          max(div(total_count + @page_size - 1, @page_size), 1)
          |> min(@max_page)

        {:noreply,
         assign(socket,
           slug: slug,
           character: page_data.character,
           page_title: "#{page_data.character.name} (Character history)",
           revisions: revisions,
           page: page,
           total_count: total_count,
           total_pages: total_pages,
           has_previous: page > 1,
           has_next: page < total_pages
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Character not found · Kaguya",
           not_found?: true
         )}
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
    <div class="mx-auto mt-6 max-w-[748px] px-4 pb-20 lg:mt-10 lg:px-0">
      <div class="mb-8">
        <.link
          navigate={"/character/#{@slug}"}
          class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular inline-flex items-center gap-1.5 transition-colors"
        >
          ← Back to character
        </.link>
      </div>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {@character.name} history
      </h1>
      <p class="mt-2 text-sm text-[rgb(var(--foreground-secondary))]">
        {@total_count} edits
      </p>

      <section class="bg-surface-base border-border-divider mt-6 overflow-hidden rounded-[8px] border">
        <div
          :if={@revisions == []}
          class="px-4 py-12 text-center text-sm text-[rgb(var(--foreground-secondary))]"
        >
          No revision history found.
        </div>

        <ol :if={@revisions != []} class="divide-border-divider divide-y">
          <li
            :for={revision <- @revisions}
            class="px-4 py-3 text-sm text-[rgb(var(--foreground-secondary))]"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="bg-surface-elevated text-foreground-tertiary rounded-[4px] px-1.5 py-0.5 text-[11px] font-medium uppercase">
                {format_action_label(revision.action)}
              </span>
              <span class="text-sm font-medium text-[rgb(var(--foreground-primary))]">
                {revision.summary}
              </span>
              <span class="text-xs text-[rgb(var(--foreground-tertiary))]">
                r{revision.revision_number}
              </span>
            </div>

            <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-[rgb(var(--foreground-tertiary))]">
              <span>
                {revision.user_label}
              </span>
              <span aria-hidden="true">·</span>
              <time>{revision.inserted_at_label}</time>
              <span :if={revision.changed_fields != []} aria-hidden="true">·</span>
              <span :if={revision.changed_fields != []}>
                {changed_fields_label(revision.changed_fields)}
              </span>
            </div>
          </li>
        </ol>
      </section>

      <nav
        :if={@total_pages > 1}
        class="mt-4 flex items-center justify-between gap-3 text-sm"
        aria-label="Revision pagination"
      >
        <.link
          patch={history_href(@slug, @page - 1)}
          class={[
            "border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-secondary))] transition-colors hover:border-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-primary))]",
            if(@has_previous, do: "opacity-100", else: "pointer-events-none opacity-40")
          ]}
        >
          Previous
        </.link>

        <span class="text-[rgb(var(--foreground-tertiary))]">
          Page {@page} of {@total_pages}
        </span>

        <.link
          patch={history_href(@slug, @page + 1)}
          class={[
            "border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-secondary))] transition-colors hover:border-[rgb(var(--foreground-tertiary))] hover:text-[rgb(var(--foreground-primary))]",
            if(@has_next, do: "opacity-100", else: "pointer-events-none opacity-40")
          ]}
        >
          Next
        </.link>
      </nav>
    </div>
    """
  end

  defp load_revisions(character_id, page) do
    revisions =
      Revisions.list_revisions(:character, character_id, offset: (page - 1) * @page_size)

    users = load_users_by_ids(revisions)

    Enum.map(revisions, fn revision ->
      %{
        revision_number: revision.revision_number,
        action: revision.action,
        summary: revision.summary,
        changed_fields: revision.changed_fields || [],
        user_label: user_label(revision.user_id, users),
        inserted_at_label: format_inserted_at(revision.inserted_at)
      }
    end)
  end

  defp load_users_by_ids(revisions) do
    revisions
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      user_ids ->
        Repo.all(from u in User, where: u.id in ^user_ids)
        |> Map.new(&{&1.id, &1})
    end
  end

  defp user_label(nil, _users), do: "System"

  defp user_label(user_id, users) do
    case Map.get(users, user_id) do
      nil -> "System"
      user -> user.display_name || user.username || "Unknown user"
    end
  end

  defp format_action_label(:create), do: "Created"
  defp format_action_label(:edit), do: "Edited"
  defp format_action_label(:revert), do: "Reverted"
  defp format_action_label(:hide), do: "Hidden"
  defp format_action_label(:unhide), do: "Unhidden"
  defp format_action_label(:lock), do: "Locked"
  defp format_action_label(:unlock), do: "Unlocked"

  defp format_action_label(action),
    do: action |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp changed_fields_label(changed_fields) do
    ChangedFields.summary_label(changed_fields)
  end

  defp history_href(slug, page) when page <= 1, do: "/character/#{slug}/history"
  defp history_href(slug, page), do: "/character/#{slug}/history?page=#{page}"

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> min(page, @max_page)
      _ -> 1
    end
  end

  defp format_inserted_at(nil), do: "recently"

  defp format_inserted_at(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%b %-d, %Y %H:%M")
end

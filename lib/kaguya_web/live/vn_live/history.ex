defmodule KaguyaWeb.VNLive.History do
  use KaguyaWeb, :live_view

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.ChangedFields
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels
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
       page_title: "Visual novel history",
       vn: nil,
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
    page = parse_page(params["page"])

    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(socket.assigns.current_user)) do
      nil ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Visual novel not found · Kaguya",
           not_found?: true
         )}

      vn ->
        revisions = load_revisions(vn.id, vn.slug, page)
        total_count = Revisions.revision_count(:visual_novel, vn.id)

        total_pages =
          max(div(total_count + @page_size - 1, @page_size), 1)
          |> min(@max_page)

        {:noreply,
         assign(socket,
           slug: slug,
           vn: vn,
           page_title: "#{vn.title} (Visual novel history)",
           revisions: revisions,
           page: page,
           total_count: total_count,
           total_pages: total_pages,
           has_previous: page > 1,
           has_next: page < total_pages
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
          navigate={"/vn/#{@slug}"}
          class="hover:text-foreground-secondary text-foreground-tertiary text-style-captionRegular inline-flex items-center gap-1.5 transition-colors"
        >
          ← Back to visual novel
        </.link>
      </div>

      <h1 class="text-foreground-primary text-style-heading2Medium mb-1">
        {@vn.title} history
      </h1>

      <p class="mt-2 text-sm text-[rgb(var(--foreground-secondary))]">
        {format_count(@total_count)} edits
      </p>

      <section class="bg-surface-base border-border-divider mt-6 overflow-hidden rounded-[8px] border">
        <div
          :if={@revisions == []}
          class="px-4 py-12 text-center text-sm text-[rgb(var(--foreground-secondary))]"
        >
          No revision history found.
        </div>

        <div
          :if={@revisions != []}
          class="bg-surface-elevated/40 border-border-divider text-foreground-tertiary hidden border-b px-4 py-2 text-xs font-medium md:grid md:grid-cols-[64px_152px_116px_minmax(0,1fr)_148px]"
        >
          <div>Rev.</div>
          <div class="px-3">Date</div>
          <div class="px-3">User</div>
          <div class="px-3">Summary</div>
          <div class="px-3">Fields</div>
        </div>

        <ol :if={@revisions != []} class="divide-border-divider divide-y">
          <li
            :for={revision <- @revisions}
            id={"vn-history-row-#{revision.id}"}
            class="hover:bg-surface-elevated/50 relative cursor-pointer px-4 py-3 text-sm text-[rgb(var(--foreground-secondary))] transition-colors md:grid md:grid-cols-[64px_152px_116px_minmax(0,1fr)_148px] md:items-start md:gap-0 md:py-2.5"
          >
            <.link
              navigate={revision.href}
              class="absolute inset-0 z-0"
              aria-label={"Open revision r#{revision.revision_number}"}
            >
              <span class="sr-only">Open revision r{revision.revision_number}</span>
            </.link>

            <div
              id={"vn-history-revision-#{revision.id}"}
              class="pointer-events-none relative z-10 flex flex-wrap items-center gap-2 md:block md:pt-0.5"
            >
              <.link
                navigate={revision.href}
                class="hover:text-text-link-hover text-text-link-default pointer-events-auto font-mono text-sm transition-colors"
              >
                r{revision.revision_number}
              </.link>

              <span class="bg-surface-elevated text-foreground-tertiary rounded-[4px] px-1.5 py-0.5 text-[11px] font-medium uppercase md:hidden">
                {format_action_label(revision.action)}
              </span>
            </div>

            <time
              title={revision.inserted_at_title}
              class="pointer-events-none relative z-10 mt-2 block text-xs text-[rgb(var(--foreground-tertiary))] md:mt-0 md:px-3 md:py-0.5 md:text-sm"
            >
              {revision.inserted_at_label}
            </time>

            <div class="pointer-events-none relative z-10 mt-1 text-xs md:mt-0 md:px-3 md:py-0.5 md:text-sm">
              <.link
                :if={revision.user_href}
                navigate={revision.user_href}
                class="hover:text-text-link-hover text-text-link-default pointer-events-auto transition-colors"
              >
                {revision.user_label}
              </.link>
              <span :if={!revision.user_href} class="text-foreground-tertiary">
                {revision.user_label}
              </span>
            </div>

            <div class="pointer-events-none relative z-10 mt-2 min-w-0 md:mt-0 md:px-3 md:py-0.5">
              <div class="flex flex-wrap items-center gap-2">
                <.link
                  navigate={revision.href}
                  class="hover:text-text-link-hover pointer-events-auto font-medium text-[rgb(var(--foreground-primary))] transition-colors"
                >
                  {revision.summary}
                </.link>
                <span class="bg-surface-elevated text-foreground-tertiary hidden rounded-[4px] px-1.5 py-0.5 text-[11px] font-medium uppercase md:inline-flex">
                  {format_action_label(revision.action)}
                </span>
              </div>
            </div>

            <div class="pointer-events-none relative z-10 mt-2 md:mt-0 md:px-3">
              <div
                :if={revision.changed_fields != []}
                class="flex flex-wrap gap-1"
                aria-label={changed_fields_label(revision.changed_fields)}
              >
                <span
                  :for={field <- changed_field_chips(revision.changed_fields)}
                  class="bg-surface-elevated text-foreground-tertiary rounded px-1.5 py-0.5 text-[11px]"
                >
                  {field}
                </span>
              </div>
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

  defp load_revisions(vn_id, slug, page) do
    revisions = Revisions.list_revisions(:visual_novel, vn_id, offset: (page - 1) * @page_size)
    users = load_users_by_ids(revisions)

    Enum.map(revisions, fn revision ->
      %{
        id: revision.id,
        href: "/vn/#{slug}/history/#{revision.id}",
        revision_number: revision.revision_number,
        action: revision.action,
        summary: revision.summary,
        changed_fields: revision.changed_fields || [],
        user_label: user_label(revision.user_id, users),
        user_href: user_href(revision.user_id, users),
        inserted_at_label: format_inserted_at(revision.inserted_at),
        inserted_at_title: format_inserted_at_title(revision.inserted_at)
      }
    end)
  end

  defp load_users_by_ids(revisions) do
    revisions
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      user_ids -> Repo.all(from u in User, where: u.id in ^user_ids) |> Map.new(&{&1.id, &1})
    end
  end

  defp user_label(nil, _users), do: "System"

  defp user_label(user_id, users) do
    case Map.get(users, user_id) do
      nil -> "System"
      user -> user.display_name || user.username || "Unknown user"
    end
  end

  defp user_href(nil, _users), do: nil

  defp user_href(user_id, users) do
    case Map.get(users, user_id) do
      %{username: username} when is_binary(username) and username != "" -> "/@#{username}"
      _ -> nil
    end
  end

  defp viewer_opts(%{role: role}) when role in [:moderator, :admin], do: [include_hidden: true]
  defp viewer_opts(_), do: []

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

  defp changed_field_chips(changed_fields) do
    changed_fields
    |> Enum.take(3)
    |> Enum.map(&ChangedFields.field_label/1)
  end

  defp history_href(slug, page) when page <= 1, do: "/vn/#{slug}/history"
  defp history_href(slug, page), do: "/vn/#{slug}/history?page=#{page}"

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

  defp format_inserted_at_title(nil), do: nil

  defp format_inserted_at_title(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp format_count(count) when is_integer(count) and count >= 1_000_000,
    do: "#{Float.round(count / 1_000_000, 1)}M"

  defp format_count(count) when is_integer(count) and count >= 1_000,
    do: "#{Float.round(count / 1_000, 1)}K"

  defp format_count(count) when is_integer(count), do: Integer.to_string(count)
  defp format_count(_), do: "0"
end

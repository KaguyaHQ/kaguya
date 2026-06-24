defmodule KaguyaWeb.ModerationLive.Reports do
  use KaguyaWeb, :live_view

  alias Kaguya.Reports
  alias Kaguya.Reports.Report

  @page_size 25
  @statuses [:new, :in_progress, :resolved, :dismissed]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       page_title: "Moderation reports • Kaguya",
       meta_description: "Review and resolve moderation reports across Kaguya.",
       state: :loading,
       reports: [],
       pagination: empty_pagination(),
       filters: %{"status" => "new", "entity_type" => ""},
       unresolved_count: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  @impl true
  def handle_event("filter", %{"filters" => attrs}, socket) do
    filters =
      %{
        "status" => normalize_status_param(Map.get(attrs, "status")),
        "entity_type" => normalize_entity_type_param(Map.get(attrs, "entity_type"))
      }

    {:noreply, push_patch(socket, to: reports_path(filters, 1), replace: true)}
  end

  @impl true
  def handle_event("update_status", %{"report" => attrs}, socket) do
    case socket.assigns do
      %{state: :ready, current_user: current_user} ->
        report_id = Map.get(attrs, "_id")
        status = parse_status(Map.get(attrs, "status"))

        with {:ok, report} <- Reports.get_report(report_id),
             :ok <- ensure_report_visible(current_user, report),
             {:ok, update_attrs} <- build_update_attrs(attrs, status, current_user.id),
             {:ok, _updated} <- Reports.update_report_status(report_id, update_attrs) do
          Kaguya.AuditLog.log(
            current_user.id,
            "report_#{status}",
            report.entity_type,
            report_id,
            Map.get(update_attrs, :mod_notes)
          )

          {:noreply,
           socket
           |> put_flash(:info, status_flash(status))
           |> load_page(current_params(socket))}
        else
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, format_error(reason))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-[980px] space-y-6 px-4 py-8 sm:px-6 lg:px-0">
      <h1 class="text-foreground-primary text-2xl font-semibold">
        Reports
      </h1>

      <section
        :if={@state == :auth_required}
        class="bg-surface-base border-border-divider mt-6 rounded-[10px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        Sign in with a moderator account to review reports.
      </section>

      <section
        :if={@state == :forbidden}
        class="bg-surface-base border-border-divider mt-6 rounded-[10px] border p-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        You do not have permission to access the moderation queue.
      </section>

      <%= if @state == :ready do %>
        <.form for={%{}} as={:filters} phx-change="filter">
          <div class="flex flex-wrap items-center gap-3">
            <label class="sr-only" for="report-status-filter">Status</label>
            <select
              id="report-status-filter"
              name="filters[status]"
              class="bg-surface-elevated border-border-divider h-9 w-[160px] rounded-[8px] border px-3 text-sm text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option value="">All statuses</option>
              <option
                :for={status <- @status_options}
                value={status.value}
                selected={@filters["status"] == status.value}
              >
                {status.label}
              </option>
            </select>

            <label class="sr-only" for="report-entity-filter">Entity type</label>
            <select
              id="report-entity-filter"
              name="filters[entity_type]"
              class="bg-surface-elevated border-border-divider h-9 w-[180px] rounded-[8px] border px-3 text-sm text-[rgb(var(--foreground-primary))] outline-none"
            >
              <option value="">All visible types</option>
              <option
                :for={type <- @entity_type_options}
                value={type.value}
                selected={@filters["entity_type"] == type.value}
              >
                {type.label}
              </option>
            </select>

            <span class="text-foreground-tertiary ml-auto text-xs">
              {@pagination.total_count} report{if @pagination.total_count == 1, do: "", else: "s"}
            </span>
          </div>
        </.form>

        <section class="space-y-4">
          <article
            :for={report <- @reports}
            class="bg-surface-base border-border-divider rounded-[12px] border p-4 sm:p-5"
          >
            <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <KaguyaWeb.SharedComponents.Badge.badge
                    tone={status_badge_tone(report.status)}
                    size="lg"
                    class="rounded-full tracking-[0.16em]"
                  >
                    {status_label(report.status)}
                  </KaguyaWeb.SharedComponents.Badge.badge>
                  <KaguyaWeb.SharedComponents.Badge.badge
                    variant="outline"
                    tone="neutral"
                    size="lg"
                    class="rounded-full tracking-[0.16em]"
                  >
                    {labelize(report.entity_type)}
                  </KaguyaWeb.SharedComponents.Badge.badge>
                  <KaguyaWeb.SharedComponents.Badge.badge
                    variant="outline"
                    tone="neutral"
                    size="lg"
                    class="rounded-full tracking-[0.16em]"
                  >
                    {labelize(report.category)}
                  </KaguyaWeb.SharedComponents.Badge.badge>
                </div>

                <h2 class="mt-3 text-lg font-semibold text-[rgb(var(--foreground-primary))]">
                  {report.entity_name || "Unnamed #{labelize(report.entity_type)}"}
                </h2>

                <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-[rgb(var(--foreground-secondary))]">
                  <span>
                    Reported by
                    <span class="font-medium text-[rgb(var(--foreground-primary))]">
                      {user_label(report.reporter)}
                    </span>
                  </span>
                  <span>{format_datetime(report.inserted_at)}</span>
                  <span :if={report.resolver}>
                    Last reviewed by
                    <span class="font-medium text-[rgb(var(--foreground-primary))]">
                      {user_label(report.resolver)}
                    </span>
                  </span>
                </div>

                <p class="mt-3 text-sm font-medium text-[rgb(var(--foreground-primary))]">
                  {report.reason}
                </p>

                <p
                  :if={present?(report.message)}
                  class="mt-2 text-sm/6 whitespace-pre-wrap text-[rgb(var(--foreground-secondary))]"
                >
                  {report.message}
                </p>

                <div
                  :if={present?(report.resolution_note) or present?(report.mod_notes)}
                  class="mt-4 grid gap-3 md:grid-cols-2"
                >
                  <div
                    :if={present?(report.resolution_note)}
                    class="bg-surface-elevated border-border-divider rounded-[10px] border p-3"
                  >
                    <p class="text-[11px] font-medium tracking-[0.16em] text-[rgb(var(--foreground-tertiary))] uppercase">
                      Reporter note
                    </p>
                    <p class="mt-2 text-sm/6 whitespace-pre-wrap text-[rgb(var(--foreground-secondary))]">
                      {report.resolution_note}
                    </p>
                  </div>

                  <div
                    :if={present?(report.mod_notes)}
                    class="bg-surface-elevated border-border-divider rounded-[10px] border p-3"
                  >
                    <p class="text-[11px] font-medium tracking-[0.16em] text-[rgb(var(--foreground-tertiary))] uppercase">
                      Internal note
                    </p>
                    <p class="mt-2 text-sm/6 whitespace-pre-wrap text-[rgb(var(--foreground-secondary))]">
                      {report.mod_notes}
                    </p>
                  </div>
                </div>
              </div>

              <div class="flex shrink-0 flex-col gap-2">
                <.link
                  :if={entity_path(report)}
                  navigate={entity_path(report)}
                  class="border-border-divider hover:bg-surface-elevated rounded-[8px] border px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors"
                >
                  Open entity
                </.link>
              </div>
            </div>

            <.form
              for={%{}}
              as={:report}
              phx-submit="update_status"
              class="border-border-divider mt-5 border-t pt-4"
            >
              <input type="hidden" name="report[_id]" value={report.id} />

              <div class="grid grid-cols-1 gap-4 lg:grid-cols-[220px_1fr_1fr]">
                <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
                  <span class="font-medium text-[rgb(var(--foreground-primary))]">Decision</span>
                  <select
                    name="report[status]"
                    class="bg-surface-elevated border-border-divider rounded-[8px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
                  >
                    <option
                      :for={status <- @status_options}
                      value={status.value}
                      selected={Atom.to_string(report.status) == status.value}
                    >
                      {status.label}
                    </option>
                  </select>
                </label>

                <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
                  <span class="font-medium text-[rgb(var(--foreground-primary))]">
                    Reporter-facing note
                  </span>
                  <textarea
                    name="report[resolution_note]"
                    rows="4"
                    maxlength="5000"
                    placeholder="Required for resolved or dismissed."
                    class="bg-surface-elevated border-border-divider min-h-[112px] rounded-[8px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
                  ><%= report.resolution_note || "" %></textarea>
                </label>

                <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
                  <span class="font-medium text-[rgb(var(--foreground-primary))]">
                    Internal moderator note
                  </span>
                  <textarea
                    name="report[mod_notes]"
                    rows="4"
                    maxlength="5000"
                    placeholder="Visible only to moderators."
                    class="bg-surface-elevated border-border-divider min-h-[112px] rounded-[8px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
                  ><%= report.mod_notes || "" %></textarea>
                </label>
              </div>

              <div class="mt-4 flex justify-end">
                <button
                  type="submit"
                  class="rounded-[8px] border border-[rgb(var(--chip-border-default))] px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
                >
                  Save decision
                </button>
              </div>
            </.form>
          </article>

          <section
            :if={@reports == []}
            class="bg-surface-base border-border-divider text-foreground-tertiary rounded-xl border p-8 text-center text-sm"
          >
            No reports found.
          </section>
        </section>

        <nav
          :if={@pagination.total_pages > 1}
          class="mt-8 flex items-center justify-center gap-2"
          aria-label="Reports pagination"
        >
          <.page_link
            filters={@filters}
            page={max(@pagination.page - 1, 1)}
            disabled={@pagination.page <= 1}
          >
            Previous
          </.page_link>
          <span class="px-2 text-sm text-[rgb(var(--foreground-secondary))]">
            {@pagination.page} / {@pagination.total_pages}
          </span>
          <.page_link
            filters={@filters}
            page={min(@pagination.page + 1, @pagination.total_pages)}
            disabled={@pagination.page >= @pagination.total_pages}
          >
            Next
          </.page_link>
        </nav>
      <% end %>
    </main>
    """
  end

  attr :filters, :map, required: true
  attr :page, :integer, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp page_link(assigns) do
    ~H"""
    <%= if @disabled do %>
      <span class="border-border-divider rounded-[8px] border px-3 py-2 text-sm text-[rgb(var(--foreground-tertiary))]">
        {render_slot(@inner_block)}
      </span>
    <% else %>
      <.link
        patch={reports_path(@filters, @page)}
        class="border-border-divider hover:bg-surface-elevated rounded-[8px] border px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors"
      >
        {render_slot(@inner_block)}
      </.link>
    <% end %>
    """
  end

  defp load_page(socket, params) do
    case socket.assigns.current_user do
      nil ->
        assign(socket, state: :auth_required, reports: [], pagination: empty_pagination())

      current_user ->
        if moderator?(current_user) do
          filters = %{
            "status" => normalize_status_param(Map.get(params, "status")),
            "entity_type" => normalize_entity_type_param(Map.get(params, "entity_type"))
          }

          page = parse_page(Map.get(params, "page"))
          visible_types = Reports.visible_report_types(current_user)

          opts = [
            page: page,
            page_size: @page_size,
            status: parse_status(filters["status"]),
            entity_type: blank_to_nil(filters["entity_type"]),
            visible_entity_types: visible_types
          ]

          case Reports.list_reports(opts) do
            {:ok, %{items: reports, pagination: pagination}} ->
              assign(socket,
                state: :ready,
                reports: reports,
                pagination: normalize_pagination(pagination),
                unresolved_count: Reports.unresolved_count(visible_types),
                filters: filters,
                status_options: status_options(),
                entity_type_options: entity_type_options(visible_types)
              )

            _ ->
              socket
              |> assign(state: :forbidden, reports: [], pagination: empty_pagination())
              |> put_flash(:error, format_error(:forbidden))
          end
        else
          assign(socket, state: :forbidden, reports: [], pagination: empty_pagination())
        end
    end
  end

  defp current_params(socket) do
    filters = socket.assigns.filters

    %{
      "status" => filters["status"],
      "entity_type" => filters["entity_type"],
      "page" => to_string(socket.assigns.pagination.page)
    }
  end

  defp build_update_attrs(attrs, status, _user_id) when status in [:new, :in_progress] do
    {:ok,
     %{
       status: status,
       mod_notes: blank_to_nil(Map.get(attrs, "mod_notes")),
       resolution_note: blank_to_nil(Map.get(attrs, "resolution_note"))
     }}
  end

  defp build_update_attrs(attrs, status, user_id) when status in [:resolved, :dismissed] do
    {:ok,
     %{
       status: status,
       resolved_by: user_id,
       resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
       mod_notes: blank_to_nil(Map.get(attrs, "mod_notes")),
       resolution_note: blank_to_nil(Map.get(attrs, "resolution_note"))
     }}
  end

  defp build_update_attrs(_attrs, _status, _user_id), do: {:error, "Invalid status"}

  defp ensure_report_visible(user, report) do
    visible_types = Reports.visible_report_types(user)

    if visible_types == :all or report.entity_type in visible_types do
      :ok
    else
      {:error, "You don't have permission to act on this report type"}
    end
  end

  defp moderator?(%{role: role}) when role in [:admin, :moderator], do: true
  defp moderator?(_), do: false

  defp entity_path(report), do: Reports.entity_path_for_report(report)

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_status(nil), do: nil
  defp parse_status(""), do: nil

  defp parse_status(value) when is_binary(value) do
    try do
      status = String.to_existing_atom(value)
      if status in @statuses, do: status, else: nil
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_status(value) when is_atom(value) and value in @statuses, do: value
  defp parse_status(_value), do: nil

  defp normalize_status_param(value) do
    case parse_status(value) do
      nil -> ""
      status -> Atom.to_string(status)
    end
  end

  defp normalize_entity_type_param(value) when value in [nil, ""], do: ""

  defp normalize_entity_type_param(value) do
    normalized = to_string(value)
    if normalized in Report.entity_types(), do: normalized, else: ""
  end

  defp empty_pagination do
    %{page: 1, page_size: @page_size, total_pages: 1, total_count: 0}
  end

  defp normalize_pagination(pagination) do
    total_count = Kaguya.Pagination.resolve_count(pagination) || 0
    total_pages = Kaguya.Pagination.resolve_total_pages(pagination) || 1

    %{
      page: Map.get(pagination, :page, 1),
      page_size: Map.get(pagination, :page_size, @page_size),
      total_count: total_count,
      total_pages: max(total_pages, 1)
    }
  end

  defp reports_path(filters, page) do
    params =
      %{}
      |> maybe_put_param("status", blank_to_nil(filters["status"]))
      |> maybe_put_param("entity_type", blank_to_nil(filters["entity_type"]))
      |> maybe_put_param("page", if(page > 1, do: page, else: nil))

    "/moderation/reports" <> if(params == %{}, do: "", else: "?" <> URI.encode_query(params))
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, to_string(value))

  defp status_options do
    Enum.map(@statuses, fn status ->
      %{value: Atom.to_string(status), label: status_label(status)}
    end)
  end

  defp entity_type_options(:all) do
    Report.entity_types()
    |> Enum.sort()
    |> Enum.map(&%{value: &1, label: labelize(&1)})
  end

  defp entity_type_options(visible_types) do
    visible_types
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%{value: &1, label: labelize(&1)})
  end

  defp status_label(:new), do: "New"
  defp status_label(:in_progress), do: "In progress"
  defp status_label(:resolved), do: "Resolved"
  defp status_label(:dismissed), do: "Dismissed"

  defp status_flash(:new), do: "Report marked as new."
  defp status_flash(:in_progress), do: "Report moved to in progress."
  defp status_flash(:resolved), do: "Report resolved."
  defp status_flash(:dismissed), do: "Report dismissed."

  defp status_badge_tone(:new), do: "warning"
  defp status_badge_tone(:in_progress), do: "info"
  defp status_badge_tone(:resolved), do: "success"
  defp status_badge_tone(:dismissed), do: "danger"
  defp status_badge_tone(_), do: "neutral"

  defp labelize(value) when is_atom(value), do: value |> Atom.to_string() |> labelize()

  defp labelize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp user_label(nil), do: "Unknown user"

  defp user_label(user) do
    user.display_name || user.username || "Unknown user"
  end

  defp format_datetime(nil), do: "Unknown time"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y, %-I:%M %p")
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present?(value), do: not is_nil(blank_to_nil(value))

  defp format_error(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(_reason), do: "Unable to load reports."
end

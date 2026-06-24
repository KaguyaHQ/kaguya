defmodule KaguyaWeb.SettingsLive.Index do
  use KaguyaWeb, :live_view

  import KaguyaWeb.UI.Switch

  alias Kaguya.Exports.KaguyaCsv
  alias Kaguya.Users

  require Logger

  @export_poll_interval 2_500

  @preference_fields %{
    "show_nsfw_images" => :show_nsfw_images,
    "show_nsfw_screenshots" => :show_nsfw_screenshots,
    "show_brutal_screenshots" => :show_brutal_screenshots,
    "show_adjacent" => :show_adjacent,
    "show_nukige" => :show_nukige
  }

  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      latest_export = latest_export(socket.assigns.current_user.id)

      {:ok,
       socket
       |> assign(:page_title, "Settings • Kaguya")
       |> assign(:meta_description, "Settings")
       |> assign(KaguyaWeb.SEO.noindex())
       |> assign(:latest_export, latest_export)
       |> assign(:active_export_id, nil)
       |> assign(:danger_dialog, nil)
       |> maybe_schedule_export_poll()}
    else
      {:ok, redirect(socket, to: "/login")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :section, socket.assigns.live_action)}
  end

  def handle_info(:poll_export, socket) do
    latest_export = latest_export(socket.assigns.current_user.id)
    socket = assign(socket, :latest_export, latest_export)

    cond do
      export_busy?(latest_export) ->
        {:noreply, maybe_schedule_export_poll(socket)}

      active_export?(socket, latest_export) and export_completed?(latest_export) ->
        {:noreply,
         socket
         |> assign(:active_export_id, nil)
         |> push_export_download(latest_export)
         |> put_flash(:info, "Export ready.")}

      active_export?(socket, latest_export) and export_failed?(latest_export) ->
        {:noreply,
         socket
         |> assign(:active_export_id, nil)
         |> put_flash(:error, latest_export.error || "Export failed.")}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_preference", %{"field" => field}, socket) do
    user = socket.assigns.current_user

    with pref when is_atom(pref) <- Map.get(@preference_fields, field),
         {:ok, updated} <- Users.update_user(user.id, %{pref => !Map.get(user, pref, false)}) do
      new_value = Map.get(updated, pref)

      {:noreply,
       socket
       |> assign(:current_user, normalize_user(updated))
       |> assign(
         :nav_viewer,
         KaguyaWeb.AppNavbar.normalize_viewer(updated, nav_viewer_count(socket))
       )
       |> maybe_push_client_pref(pref, new_value)
       |> put_flash(:info, preference_flash(pref, new_value))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not update settings.")}
    end
  end

  def handle_event("start_export", _params, socket) do
    user_id = socket.assigns.current_user.id
    latest_export = latest_export(user_id)

    cond do
      export_busy?(latest_export) ->
        {:noreply,
         socket
         |> assign(:latest_export, latest_export)
         |> maybe_schedule_export_poll()}

      export_completed?(latest_export) ->
        {:noreply,
         socket
         |> assign(:latest_export, latest_export)
         |> push_export_download(latest_export)}

      true ->
        case KaguyaCsv.enqueue(user_id) do
          {:ok, export} ->
            {:noreply,
             socket
             |> assign(:latest_export, export)
             |> assign(:active_export_id, export.id)
             |> maybe_schedule_export_poll()
             |> put_flash(:info, "Export started.")}

          {:error, :export_in_progress} ->
            {:noreply,
             socket
             |> assign(:latest_export, latest_export(user_id))
             |> maybe_schedule_export_poll()
             |> put_flash(:error, "A library export is already queued or running.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not start export: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("open_reset_library_dialog", _params, socket) do
    {:noreply, assign(socket, :danger_dialog, :reset_library)}
  end

  def handle_event("open_delete_account_dialog", _params, socket) do
    {:noreply, assign(socket, :danger_dialog, :delete_account)}
  end

  def handle_event("close_danger_dialog", _params, socket) do
    {:noreply, assign(socket, :danger_dialog, nil)}
  end

  def handle_event("reset_library", _params, socket) do
    case Users.reset_library(socket.assigns.current_user.id) do
      {:ok, true} ->
        {:noreply,
         socket
         |> assign(:danger_dialog, nil)
         |> put_flash(:info, "Library reset.")}

      _ ->
        {:noreply,
         socket
         |> assign(:danger_dialog, nil)
         |> put_flash(:error, "Could not reset library.")}
    end
  end

  def handle_event("delete_account", _params, socket) do
    user_id = socket.assigns.current_user.id

    with {:ok, _} <- Users.delete_user(user_id) do
      {:noreply,
       push_event(socket, "kaguya:submit-form", %{
         selector: "#account-deleted-sign-out-form"
       })}
    else
      {:error, reason} ->
        Logger.error("Account deletion failed for #{user_id}: #{inspect(reason)}")

        {:noreply,
         socket
         |> assign(:danger_dialog, nil)
         |> put_flash(:error, "Account deletion failed. Please try again.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-[520px] px-5 pb-[160px] sm:pt-16">
      <.form
        id="account-deleted-sign-out-form"
        for={%{}}
        action={~p"/auth/sign-out"}
        method="post"
        class="hidden"
      >
        <input type="hidden" name="return_to" value="/" />
      </.form>

      <h3 class="text-foreground-secondary text-style-heading3Medium mb-4 max-sm:mt-8">
        Settings
      </h3>
      <div class="border-border-divider/70 mb-8 border-b" />

      <div
        :if={@section == :integrations}
        class="bg-surface-elevated/40 border-border-divider/50 text-foreground-secondary mb-6 rounded-[8px] border px-4 py-3 text-sm"
      >
        Integrations are not yet available in the LiveView migration.
      </div>

      <div class="flex flex-col gap-6">
        <section id="content-preferences">
          <h4 class="text-foreground-secondary text-style-captionRegular mb-1 tracking-wider uppercase">
            Sensitive content
          </h4>
          <div class="divide-border-divider/30 divide-y">
            <.preference_row
              field="show_nsfw_images"
              enabled={@current_user.show_nsfw_images}
              title="Show NSFW covers"
              description="Off blurs them until clicked"
            />
            <.preference_row
              field="show_nsfw_screenshots"
              enabled={@current_user.show_nsfw_screenshots}
              title="Show NSFW screenshots"
            />
            <.preference_row
              field="show_brutal_screenshots"
              enabled={@current_user.show_brutal_screenshots}
              title="Show brutal screenshots"
              description="Screenshots with violence or gore"
            />
          </div>
        </section>

        <section>
          <h4 class="text-foreground-secondary text-style-captionRegular mb-1 tracking-wider uppercase">
            Catalog
          </h4>
          <div class="divide-border-divider/30 divide-y">
            <.preference_row
              field="show_adjacent"
              enabled={@current_user.show_adjacent}
              title="Show VN hybrids"
              description="Titles where gameplay is part of the work, not decoration"
            />
            <.preference_row
              field="show_nukige"
              enabled={@current_user.show_nukige}
              title="Show nukige"
              description="Titles centered on explicit sexual content"
            />
          </div>
        </section>

        <section>
          <h4 class="text-foreground-secondary text-style-captionRegular mb-1 tracking-wider uppercase">
            Data
          </h4>
          <div class="divide-border-divider/30 divide-y">
            <.link
              navigate="/account/import"
              class="group -mx-3 flex items-center justify-between px-3 py-4 transition-colors hover:bg-white/3"
            >
              <div>
                <p class="text-foreground-primary text-style-body1Medium">Import your library</p>
                <p class="text-foreground-secondary text-style-body2Regular mt-1">
                  Bring in your data from VNDB
                </p>
              </div>
              <span class="group-hover:text-foreground-secondary text-foreground-tertiary transition-colors">
                <Lucide.chevron_right class="size-4" aria-hidden />
              </span>
            </.link>

            <button
              type="button"
              phx-click="start_export"
              disabled={export_busy?(@latest_export)}
              class="group -mx-3 flex w-[calc(100%+1.5rem)] items-center justify-between px-3 py-4 text-left transition-colors hover:bg-white/3 disabled:cursor-wait disabled:opacity-70"
            >
              <div>
                <p class="text-foreground-primary text-style-body1Medium">Export your data</p>
                <p class="text-foreground-secondary text-style-body2Regular mt-1">
                  {export_description(@latest_export)}
                </p>
              </div>
              <span class="group-hover:text-foreground-secondary text-foreground-tertiary transition-colors">
                <Lucide.loader_2
                  :if={export_busy?(@latest_export)}
                  class="size-4 animate-spin"
                  aria-hidden
                />
                <Lucide.download
                  :if={!export_busy?(@latest_export)}
                  class="size-4"
                  aria-hidden
                />
              </span>
            </button>
          </div>
        </section>

        <section :if={Users.has_email_provider?(@current_user)}>
          <h4 class="text-foreground-secondary text-style-captionRegular mb-1 tracking-wider uppercase">
            Security
          </h4>
          <div class="divide-border-divider/30 divide-y">
            <.link
              navigate="/account/edit/email"
              class="group -mx-3 flex items-center justify-between px-3 py-4 transition-colors hover:bg-white/3"
            >
              <div>
                <p class="text-foreground-primary text-style-body1Medium">Email address</p>
                <p class="text-foreground-secondary text-style-body2Regular mt-1">
                  {@current_user.email}
                </p>
              </div>
              <span class="group-hover:text-foreground-secondary text-foreground-tertiary transition-colors">
                <Lucide.chevron_right class="size-4" aria-hidden />
              </span>
            </.link>
          </div>
        </section>
      </div>

      <.danger_zone dialog={@danger_dialog} />
    </div>
    """
  end

  attr :dialog, :atom, default: nil

  defp danger_zone(assigns) do
    ~H"""
    <div class="text-foreground-tertiary mt-8 flex items-center gap-1.5 text-[13px]">
      <button
        type="button"
        phx-click="open_reset_library_dialog"
        class="hover:text-foreground-secondary cursor-pointer transition-colors"
      >
        Reset library
      </button>
      <span class="text-foreground-tertiary/40">·</span>
      <button
        type="button"
        phx-click="open_delete_account_dialog"
        class="hover:text-foreground-secondary cursor-pointer transition-colors"
      >
        Delete account
      </button>
    </div>

    <.danger_confirm_dialog
      :if={@dialog == :reset_library}
      id="reset-library-dialog"
      title="Start over from zero?"
      description="This removes every visual novel, rating, review, and list from your library. There's no way to recover them."
      confirm_text="Reset"
      confirm_event="reset_library"
    />

    <.danger_confirm_dialog
      :if={@dialog == :delete_account}
      id="delete-account-dialog"
      title="This deletes everything."
      description="Your library, reviews, lists, ratings, and profile will all be permanently removed."
      confirm_text="Delete"
      confirm_event="delete_account"
    />
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :confirm_text, :string, required: true
  attr :confirm_event, :string, required: true

  defp danger_confirm_dialog(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-end justify-center bg-black/80 px-4 py-5 backdrop-blur-sm sm:items-center sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      aria-describedby={"#{@id}-description"}
    >
      <div class="w-full max-w-[380px] rounded-[14px] bg-[#0A0A0A] px-6 py-5 shadow-[0_8px_40px_rgba(0,0,0,0.55)] max-sm:max-w-[320px]">
        <h2
          id={"#{@id}-title"}
          class="max-sm:text-style-proseMedium sm:text-style-heading3Medium text-foreground-primary flex items-center gap-2"
        >
          {@title}
        </h2>
        <p id={"#{@id}-description"} class="text-foreground-tertiary mt-2 text-[14px] leading-[20px]">
          {@description}
        </p>
        <div class="mt-5 flex w-full items-center justify-end gap-2.5 max-sm:flex-row">
          <button
            type="button"
            phx-click="close_danger_dialog"
            class="active:bg-button-background-neutral-pressed bg-button-background-neutral-default border-button-border-secondary hover:bg-button-background-neutral-hover text-foreground-secondary h-[36px] rounded-[8px] border px-4 text-[13px] font-normal transition"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={@confirm_event}
            class="bg-button-background-destructive-default hover:bg-button-background-destructive-hover flex h-[36px] w-fit min-w-[64px] items-center gap-1.5 rounded-[8px] px-4 text-[13px] font-medium text-white transition"
          >
            {@confirm_text}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :enabled, :boolean, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  defp preference_row(assigns) do
    ~H"""
    <div class="group -mx-3 flex w-[calc(100%+1.5rem)] items-center justify-between px-3 py-4 text-left transition-colors hover:bg-white/3">
      <div>
        <p class="text-foreground-primary text-style-body1Medium">{@title}</p>
        <p :if={@description} class="text-foreground-secondary text-style-body2Regular mt-1">
          {@description}
        </p>
      </div>
      <.switch
        checked={@enabled}
        label={@title}
        class="ml-4"
        phx-click="toggle_preference"
        phx-value-field={@field}
      />
    </div>
    """
  end

  defp latest_export(user_id) do
    user_id
    |> Users.list_user_library_exports()
    |> List.first()
  end

  defp export_busy?(%{status: status}) when status in [:queued, :processing], do: true
  defp export_busy?(_), do: false

  defp export_completed?(%{status: :completed}), do: true
  defp export_completed?(_), do: false

  defp export_failed?(%{status: :failed}), do: true
  defp export_failed?(_), do: false

  defp active_export?(socket, %{id: id}), do: socket.assigns.active_export_id == id
  defp active_export?(_socket, _export), do: false

  defp maybe_schedule_export_poll(socket) do
    if connected?(socket) and export_busy?(socket.assigns.latest_export) do
      Process.send_after(self(), :poll_export, @export_poll_interval)
    end

    socket
  end

  defp push_export_download(socket, export) do
    case KaguyaCsv.presign_download(
           export,
           KaguyaCsv.download_filename(socket.assigns.current_user, export)
         ) do
      {:ok, url} ->
        push_event(socket, "kaguya:download-file", %{url: url})

      {:error, :not_ready} ->
        put_flash(socket, :error, "Export is not ready yet.")

      {:error, reason} ->
        put_flash(socket, :error, "Could not prepare export download: #{inspect(reason)}")
    end
  end

  defp export_description(%{status: status} = export) do
    cond do
      status in [:queued, :processing] ->
        "Preparing ZIP"

      export.error ->
        export.error

      status ->
        meta =
          [
            if(export.row_count, do: "#{export.row_count} rows"),
            format_bytes(export.byte_size)
          ]
          |> Enum.reject(&is_nil/1)

        suffix = if meta == [], do: "", else: " · #{Enum.join(meta, " · ")}"
        "#{status_text(status)}#{suffix}"
    end
  end

  defp export_description(_), do: "Download a ZIP backup of your library, reviews, and lists"

  defp status_text(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_bytes(nil), do: nil
  defp format_bytes(value) when value < 1_048_576, do: "#{ceil(value / 1024)} KB"
  defp format_bytes(value), do: "#{Float.round(value / 1_048_576, 1)} MB"

  defp preference_flash(:show_nsfw_images, true), do: "NSFW covers are now visible."
  defp preference_flash(:show_nsfw_images, false), do: "NSFW covers are now blurred."
  defp preference_flash(:show_nsfw_screenshots, true), do: "NSFW screenshots are now visible."
  defp preference_flash(:show_nsfw_screenshots, false), do: "NSFW screenshots are now hidden."
  defp preference_flash(:show_brutal_screenshots, true), do: "Brutal screenshots are now visible."
  defp preference_flash(:show_brutal_screenshots, false), do: "Brutal screenshots are now hidden."
  defp preference_flash(:show_adjacent, true), do: "Hybrid titles are now visible."
  defp preference_flash(:show_adjacent, false), do: "Hybrid titles are now hidden."
  defp preference_flash(:show_nukige, true), do: "Nukige titles are now visible."
  defp preference_flash(:show_nukige, false), do: "Nukige titles are now hidden."

  defp normalize_user(user) do
    user
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  # Preserve the live bell badge count when rebuilding nav_viewer after a
  # preference change — normalize_viewer/2 defaults to 0 otherwise.
  defp nav_viewer_count(socket) do
    case socket.assigns[:nav_viewer] do
      %{unread_notifications_count: count} when is_integer(count) -> count
      _ -> 0
    end
  end

  # Each cover/screenshot toggle writes a localStorage key
  # + html data-* attribute so the pre-paint script can suppress the blur
  # flash on the next hard reload, and other open tabs pick it up via the
  # storage event. Nukige/adjacent are server-side-only — no client mirror.
  defp maybe_push_client_pref(socket, :show_nsfw_images, value),
    do: push_event(socket, "kaguya:content-pref", %{nsfw_cover: !!value})

  defp maybe_push_client_pref(socket, :show_nsfw_screenshots, value),
    do: push_event(socket, "kaguya:content-pref", %{nsfw_screenshot: !!value})

  defp maybe_push_client_pref(socket, :show_brutal_screenshots, value),
    do: push_event(socket, "kaguya:content-pref", %{brutal_screenshot: !!value})

  defp maybe_push_client_pref(socket, _pref, _value), do: socket
end

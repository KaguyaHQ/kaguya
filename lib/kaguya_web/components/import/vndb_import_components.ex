defmodule KaguyaWeb.Import.VndbImportComponents do
  use KaguyaWeb, :html

  attr :class, :string, default: nil

  def instructions(assigns) do
    ~H"""
    <div class={["w-full", @class]}>
      <h1 class="text-foreground-primary mb-2 text-xl/6 font-semibold max-sm:mb-1.5 sm:text-[28px]/9 lg:mb-4 lg:text-[32px] lg:leading-[32px]">
        Import your library
      </h1>
      <p class="text-foreground-secondary mb-7 text-sm font-normal max-sm:leading-[150%] sm:mb-9 sm:text-base lg:mb-[52px] lg:text-[14px] lg:leading-[20px]">
        Bring in your data from VNDB
      </p>

      <div class="space-y-6 lg:space-y-8">
        <div class="space-y-3 lg:space-y-4">
          <p class="text-foreground-primary text-center text-sm font-normal sm:text-base lg:text-[16px] lg:leading-[24px]">
            1. Log in to
            <a
              href="https://vndb.org"
              target="_blank"
              rel="noopener noreferrer"
              class="text-foreground-link underline"
            >
              VNDB
            </a>
            -&gt; My Visual Novel List.
          </p>
          <img
            src="https://images.kaguya.io/ui/import/vndb-menu.webp"
            alt="VNDB menu showing My Visual Novel List option"
            width="150"
            height="123"
            class="mx-auto object-contain"
          />
        </div>

        <div class="space-y-3 lg:space-y-4">
          <p class="text-foreground-primary text-center text-sm font-normal sm:text-base lg:text-[16px] lg:leading-[24px]">
            2. Click Export to download your list.
          </p>
          <img
            src="https://images.kaguya.io/ui/import/vndb-export-bar.webp"
            alt="VNDB export bar with Export button"
            width="370"
            class="mx-auto h-auto"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :file_name, :string, default: nil
  attr :error, :string, default: nil
  attr :progress, :integer, default: 0
  attr :input_id, :string, default: "vndb-import-file"
  attr :start_label, :string, default: "Start importing"
  attr :retry_label, :string, default: "Try again"
  attr :show_actions, :boolean, default: true
  attr :retry_event, :string, default: "reset-import"

  def dropzone(assigns) do
    file_name = assigns.file_name

    status =
      if assigns.status == :not_selected && is_binary(file_name) && file_name != "" do
        :selected
      else
        assigns.status
      end

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:display_name, file_display_name(file_name))

    ~H"""
    <div
      id={"#{@input_id}-flow"}
      phx-hook="VndbImportUploader"
      data-status={@status}
      data-input-id={@input_id}
      data-max-size={Kaguya.Uploads.max_vndb_xml_bytes()}
      class="flex w-full flex-col gap-10 sm:max-w-[600px]"
    >
      <div class={[
        "relative flex h-[314px] w-full items-center justify-center overflow-hidden rounded-[8px] border transition-colors",
        @status in [:not_selected, :selected] && "cursor-pointer",
        @status == :failed && "border-red-500",
        @status != :failed && "border-border-strong-divider"
      ]}>
        <div class="pointer-events-none flex flex-col items-center gap-[18px] px-4">
          <%= if @status == :not_selected do %>
            <Lucide.file_up class="text-foreground-tertiary size-14" aria-hidden />
            <div class="flex flex-col items-center gap-0.5">
              <p class="text-foreground-secondary text-style-proseRegular">
                Drop your export file here
              </p>
              <p class="text-foreground-tertiary text-style-body2Regular">Click to browse</p>
            </div>
          <% else %>
            <Lucide.file_text class="text-foreground-tertiary size-14" aria-hidden />
            <p class="text-foreground-tertiary text-style-body2Regular max-w-[500px] truncate px-4 text-center">
              {@display_name}
            </p>
            <span
              :if={@status == :selected}
              class="bg-surface-elevated text-foreground-secondary text-style-captionMedium inline-flex h-8 items-center rounded-[8px] px-3"
            >
              Choose another
            </span>
          <% end %>
        </div>

        <input
          :if={@status in [:not_selected, :selected, :importing]}
          id={@input_id}
          type="file"
          accept=".xml,text/xml,application/xml"
          class={[
            "absolute inset-0 size-full opacity-0",
            @status in [:not_selected, :selected] && "cursor-pointer",
            @status == :importing && "pointer-events-none"
          ]}
        />
      </div>

      <.progress_panel :if={@status == :importing} progress={@progress} />

      <div :if={@status == :failed && @error} class="w-full rounded-[12px] bg-white/4 p-4">
        <p class="text-sm text-red-500">{@error}</p>
      </div>

      <div
        :if={
          @show_actions && @display_name != "VNDB export accepted" &&
            @status != :importing && is_nil(@error)
        }
        id={"#{@input_id}-action"}
        class="self-end"
      >
        <button
          type="submit"
          class="bg-button-background-brand-default text-button-text-on-brand h-[46px] rounded-[8px] px-4 text-base leading-[22px] font-normal"
        >
          {@start_label}
        </button>
      </div>

      <div :if={@show_actions && @status == :failed} class="self-end">
        <button
          type="button"
          phx-click={@retry_event}
          class="bg-button-background-brand-default text-button-text-on-brand inline-flex h-[46px] items-center gap-2 rounded-[8px] px-4 text-base leading-[22px] font-normal"
        >
          <Lucide.refresh_cw class="size-3.5" aria-hidden />
          <span>{@retry_label}</span>
        </button>
      </div>
    </div>
    """
  end

  attr :progress, :integer, required: true

  def progress_panel(assigns) do
    ~H"""
    <div class="w-full rounded-[12px] bg-white/4 p-4">
      <span class="text-foreground-primary text-xs leading-[18px] font-semibold">Importing...</span>
      <p class="text-foreground-primary/40 mt-0.5 text-xs">{@progress}%</p>
      <div class="mt-2 h-2 w-full overflow-hidden rounded-[100px] bg-white/10">
        <div
          class="bg-button-background-brand-default h-full rounded-[100px] transition-all duration-300 ease-out"
          style={"width: #{@progress}%"}
        />
      </div>
    </div>
    """
  end

  defp file_display_name(name) when is_binary(name) and name != "" do
    if String.length(name) > 54 do
      ext = Path.extname(name)
      base = String.trim_trailing(name, ext)
      String.slice(base, 0, max(1, 51 - String.length(ext))) <> "..." <> ext
    else
      name
    end
  end

  defp file_display_name(_), do: "VNDB export accepted"
end

defmodule KaguyaWeb.UI.ImageCropper do
  @moduledoc """
  Reusable image cropper modal with presigned-direct-PUT uploads.

  The JS hook
  (`assets/js/hooks/image_cropper.js`) drives Cropper.js v1 inside the modal
  and uploads the cropped Blob directly to the temp bucket via a presigned
  URL — the LiveView process never proxies the bytes.

  ## Parent contract

  The parent LiveView must handle two events. The `KaguyaWeb.ImageCropperHandlers`
  mixin provides both — `use KaguyaWeb.ImageCropperHandlers`.

      handle_event("request-image-upload", _params, socket)
      # -> {:reply, %{upload_url: url, upload_id: id}, socket}

      handle_event("image-uploaded", %{"upload_id" => _, "image_type" => _}, socket)
      # -> {:noreply, socket |> assign(...)}

  ## Example

      <.image_cropper id="onboarding-avatar" variant="profile" image_type={:avatar}>
        <:trigger>
          <div class="size-[170px] cursor-pointer rounded-full ...">
            <img data-part="preview" src={@user.avatar_url} ... />
            <span class="absolute right-2 bottom-0 ..."><Lucide.plus /></span>
          </div>
        </:trigger>
      </.image_cropper>
  """
  use Phoenix.Component

  alias Lucideicons, as: Lucide

  @doc """
  Renders the cropper trigger, hidden file input, and modal.

  ## Attributes

    * `:id` — required, must be unique per page.
    * `:variant` — "profile" (circular crop, 1:1) or "cover" (banner, ~5:1).
    * `:image_type` — atom passed to `request-image-upload` / `image-uploaded`
      events; the parent uses it to call `Uploads.process_image_upload/3` with
      the right `:avatar` / `:banner` flag.
    * `:class` — optional extra classes on the outer wrapper.

  ## Slots

    * `:trigger` (optional) — the clickable element that opens the file picker.
      Include `<img data-part="preview" ... />` inside if you want the cropped
      result to update the trigger preview optimistically after upload. Omit
      the slot when you want to open the cropper from elsewhere on the page —
      dispatch `kaguya:open-image-cropper` with `detail: %{id: "<this id>"}`,
      e.g. via `phx-click={JS.dispatch("kaguya:open-image-cropper", detail: %{id: "..."})}`.
  """
  attr :id, :string, required: true
  attr :variant, :string, values: ~w(profile cover), default: "profile"
  attr :image_type, :atom, required: true
  attr :class, :any, default: nil

  slot :trigger

  def image_cropper(assigns) do
    ~H"""
    <div
      id={@id}
      class={["group/cropper image-cropper", @class]}
      data-state="closed"
      data-variant={@variant}
      data-image-type={@image_type}
      phx-hook="ImageCropper"
      phx-update="ignore"
    >
      <div
        :if={@trigger != []}
        data-part="trigger"
        role="button"
        tabindex="0"
        class="inline-block cursor-pointer"
      >
        {render_slot(@trigger)}
      </div>

      <input
        data-part="file-input"
        type="file"
        accept="image/png,image/jpeg,image/webp,image/avif"
        class="sr-only"
        tabindex="-1"
        aria-hidden="true"
      />

      <div
        data-part="modal"
        class="fixed inset-0 z-50 hidden items-center justify-center bg-black/80 backdrop-blur-sm group-data-[state=open]/cropper:flex max-sm:p-0 sm:p-6"
      >
        <div class={[
          "bg-surface-base text-foreground-primary relative flex w-full max-w-full flex-col items-center gap-6 border-none p-6",
          "max-sm:h-full sm:max-h-[632px] sm:justify-center sm:gap-8 sm:rounded-2xl sm:p-8",
          @variant == "profile" && "sm:max-w-[460px]",
          @variant == "cover" && "sm:max-w-[657px]"
        ]}>
          <button
            type="button"
            data-part="cancel"
            class="hover:text-foreground-primary text-foreground-tertiary absolute top-4 right-4 grid size-8 place-items-center rounded-full transition-colors hover:bg-white/8"
            aria-label="Cancel"
          >
            <Lucide.x class="size-5" aria-hidden />
          </button>

          <div class={[
            "relative overflow-hidden",
            @variant == "profile" && "size-[350px] sm:size-[299px]",
            @variant == "cover" && "h-[183px] w-[350px] sm:h-[300px] sm:w-[574px]"
          ]}>
            <img data-part="cropper-image" alt="" class="block max-w-full" />
          </div>

          <div class="flex w-full items-center gap-3">
            <button
              type="button"
              data-part="zoom-minus"
              class="hover:text-foreground-primary text-foreground-tertiary transition-colors"
              aria-label="Zoom out"
            >
              <Lucide.minus class="size-[18px]" stroke-width="1.5" aria-hidden />
            </button>
            <input
              data-part="zoom-slider"
              type="range"
              min="1"
              max="5"
              step="0.01"
              value="1"
              class="image-cropper-slider h-1 flex-1 cursor-pointer appearance-none rounded-full bg-white/10 outline-none"
              aria-label="Zoom"
            />
            <button
              type="button"
              data-part="zoom-plus"
              class="hover:text-foreground-primary text-foreground-tertiary transition-colors"
              aria-label="Zoom in"
            >
              <Lucide.plus class="size-[18px]" stroke-width="1.5" aria-hidden />
            </button>
          </div>

          <p data-part="error" hidden class="self-start text-[13px] text-[#FF5E5E]" />

          <div class="flex w-full justify-end gap-3">
            <KaguyaWeb.UI.Button.button type="button" variant="neutral" data-part="replace">
              Replace
            </KaguyaWeb.UI.Button.button>
            <KaguyaWeb.UI.Button.button type="button" variant="brand" data-part="apply">
              Apply
            </KaguyaWeb.UI.Button.button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

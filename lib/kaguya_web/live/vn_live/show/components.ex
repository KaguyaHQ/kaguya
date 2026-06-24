defmodule KaguyaWeb.VNLive.Show.Components do
  @moduledoc false

  use KaguyaWeb, :html

  alias KaguyaWeb.VNLive.Show.ReviewCalendar
  alias Phoenix.LiveView.JS

  import KaguyaWeb.UI.Dialog

  def clear_status_dialog(assigns) do
    ~H"""
    <.dialog
      id="clear-status-dialog"
      on_close={JS.push("close_clear_status_dialog")}
      aria-labelledby="clear-status-dialog-title"
      aria-describedby="clear-status-dialog-description"
      class="w-[calc(100%-2rem)] max-w-[437px] overflow-hidden rounded-t-[12px] rounded-b-[16px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] p-0 text-[rgb(var(--foreground-primary))] shadow-[0_18px_70px_rgba(0,0,0,0.55)] sm:rounded-[16px]"
    >
      <div class="flex items-center justify-between gap-2 border-b border-[rgb(var(--border-divider))] py-3.5 pr-[21px] pl-6">
        <.dialog_title
          id="clear-status-dialog-title"
          class="text-left text-lg font-medium text-[rgb(var(--foreground-primary))]"
        >
          Delete all activity for this VN?
        </.dialog_title>
      </div>

      <div class="px-[26px] py-6">
        <.dialog_description
          id="clear-status-dialog-description"
          class="text-sm font-normal text-[rgb(var(--foreground-secondary))]"
        >
          Your review, rating, reading status, and shelf entries will be permanently removed.
        </.dialog_description>

        <div class="mt-4 flex justify-end gap-2">
          <.dialog_cancel>Cancel</.dialog_cancel>
          <.dialog_action phx-click="confirm_clear_status">
            Delete
          </.dialog_action>
        </div>
      </div>
    </.dialog>
    """
  end

  attr :draft_key, :string,
    default: nil,
    doc: "localStorage key cleared when the review is deleted."

  def review_delete_dialog(assigns) do
    ~H"""
    <.dialog
      id="review-delete-dialog"
      on_close={JS.push("close_review_delete_dialog")}
      aria-labelledby="review-delete-dialog-title"
      aria-describedby="review-delete-dialog-description"
      class="w-[calc(100%-2rem)] max-w-[437px] overflow-hidden rounded-t-[12px] rounded-b-[16px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] p-0 text-[rgb(var(--foreground-primary))] shadow-[0_18px_70px_rgba(0,0,0,0.55)] sm:rounded-[16px]"
    >
      <div class="flex items-center justify-between gap-2 border-b border-[rgb(var(--border-divider))] py-3.5 pr-[21px] pl-6">
        <.dialog_title
          id="review-delete-dialog-title"
          class="text-left text-lg font-medium text-[rgb(var(--foreground-primary))]"
        >
          Delete review?
        </.dialog_title>
      </div>

      <div class="px-[26px] py-6">
        <.dialog_description
          id="review-delete-dialog-description"
          class="text-sm font-normal text-[rgb(var(--foreground-secondary))]"
        >
          This will permanently delete your review. This action cannot be undone.
        </.dialog_description>

        <div class="mt-4 flex justify-end gap-2">
          <.dialog_cancel>Cancel</.dialog_cancel>
          <.dialog_action
            id="review-delete-button"
            phx-hook="DraftClear"
            data-draft-key={@draft_key}
            phx-click="delete_review"
          >
            Delete
          </.dialog_action>
        </div>
      </div>
    </.dialog>
    """
  end

  attr :form, :map, required: true
  attr :open?, :boolean, default: false

  def review_date_picker(assigns) do
    started = ReviewCalendar.parse_review_date(assigns.form["date_started"])
    finished = ReviewCalendar.parse_review_date(assigns.form["date_finished"])

    assigns =
      assigns
      |> assign(:label, ReviewCalendar.review_date_label(assigns.form))
      |> assign(:date_prefix, ReviewCalendar.review_date_prefix(assigns.form["status"] || "READ"))
      |> assign(:date_started, started)
      |> assign(:date_finished, finished)

    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click="toggle_review_date_picker"
        aria-expanded={to_string(@open?)}
        class="inline-flex h-8 cursor-pointer items-center gap-[6px] rounded-[6px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-2 text-sm transition hover:bg-[rgb(var(--surface-elevated))]/80"
      >
        <span class="text-[rgb(var(--foreground-secondary))]">
          {if @date_started && @date_finished, do: "Read", else: @date_prefix}
        </span>
        <%= cond do %>
          <% @date_started && @date_finished -> %>
            <span class="text-[rgb(var(--foreground-primary))]">
              {ReviewCalendar.format_review_date(@date_started)}
            </span>
            <span class="text-[rgb(var(--foreground-secondary))]/40">–</span>
            <span class="text-[rgb(var(--foreground-primary))]">
              {ReviewCalendar.format_review_date(@date_finished)}
            </span>
          <% @date_started -> %>
            <span class="text-[rgb(var(--foreground-primary))]">
              {ReviewCalendar.format_review_date(@date_started)}
            </span>
          <% @date_finished -> %>
            <span class="text-[rgb(var(--foreground-primary))]">
              {ReviewCalendar.format_review_date(@date_finished)}
            </span>
          <% true -> %>
            <span class="text-[rgb(var(--foreground-tertiary))]">Add dates</span>
        <% end %>
      </button>
      <div
        :if={@open?}
        phx-click-away="close_review_date_picker"
        phx-window-keydown="close_review_date_picker"
        phx-key="Escape"
        class="border-border-divider dark:bg-surface-elevated absolute top-full left-0 z-200 mt-1 w-fit rounded-[12px] border bg-white p-0 shadow-[0_8px_30px_rgba(0,0,0,0.4)]"
      >
        <.live_component
          module={KaguyaWeb.SharedComponents.DateRangePicker}
          id="review-date-range-picker"
          date_started={@form["date_started"]}
          date_finished={@form["date_finished"]}
          status={@form["status"] || "READ"}
          notify={:review_date_picked}
        />
      </div>
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :form, :map, required: true
  attr :has_review?, :boolean, required: true
  attr :save_error, :string, default: nil
  attr :date_picker_open?, :boolean, default: false

  attr :min_length_error?, :boolean,
    default: false,
    doc: "Show 'Review must be at least 40 characters' inline. Set by `save_review` server-side."

  attr :draft_key, :string,
    default: nil,
    doc: "localStorage key for the client-side review draft. nil disables draft persistence."

  def review_dialog(assigns) do
    assigns =
      assigns
      |> assign(:cover_url, vn_cover_src(assigns.vn))
      |> assign(:rating, review_form_rating(assigns.form))
      |> assign(:content_length, review_content_length(assigns.form))

    ~H"""
    <div
      id="review-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-stretch bg-black/75 p-0 backdrop-blur-md sm:items-center sm:justify-center sm:p-6"
      role="presentation"
    >
      <.form
        for={@form}
        as={:review}
        phx-change="update_review_form"
        phx-submit="save_review"
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="review-dialog-title"
        class="relative z-10 flex size-full flex-col overflow-y-auto bg-[rgb(var(--surface-base))] shadow-[0_18px_70px_rgba(0,0,0,0.55)] sm:grid sm:h-auto sm:max-h-[80vh] sm:min-h-[479px] sm:max-w-[960px] sm:grid-cols-[180px_1fr] sm:gap-12 sm:overflow-hidden sm:rounded-lg sm:p-12 sm:pb-6"
      >
        <input type="hidden" name="review[status]" value={@form["status"] || "READ"} />
        <input type="hidden" name="review[rating]" value={@form["rating"] || ""} />
        <input type="hidden" name="review[date_started]" value={@form["date_started"] || ""} />
        <input type="hidden" name="review[date_finished]" value={@form["date_finished"] || ""} />

        <div class="flex items-center justify-between border-b border-[rgb(var(--border-divider))] px-5 py-3 sm:hidden">
          <h2 class="text-lg font-semibold text-[rgb(var(--foreground-primary))]">
            {if @has_review?, do: "Edit Review", else: "I read…"}
          </h2>
          <button
            type="button"
            phx-click="close_review_dialog"
            data-modal-cancel
            class="-mr-1 flex size-11 items-center justify-center rounded-full text-[rgb(var(--foreground-primary))] transition hover:bg-white/6"
            aria-label="Close review dialog"
          >
            <Lucide.x class="size-5" aria-hidden="true" />
          </button>
        </div>

        <div class="flex items-start gap-3 px-5 pt-5 pb-4 sm:hidden">
          <div class="aspect-2/3 w-[72px] shrink-0 overflow-hidden rounded-[4px] bg-[rgb(var(--surface-banner))]">
            <img
              :if={@cover_url}
              src={@cover_url}
              alt={"#{@vn.title} cover"}
              class="size-full object-cover object-center"
            />
          </div>
          <div class="flex min-w-0 flex-1 flex-col">
            <span
              class="mt-1 line-clamp-2 text-2xl/7 font-semibold text-[rgb(var(--foreground-primary))]"
              style="font-family: var(--font-source-serif)"
            >
              {@vn.title}
            </span>
            <div class="-ml-2 flex w-fit items-center pt-1">
              <div class="relative flex items-center justify-center p-2 max-sm:-mx-1 max-sm:-my-3 max-sm:px-1 max-sm:py-3">
                <div
                  id="review-rating-stars-mobile"
                  phx-hook="RatingStars"
                  style={if @rating, do: nil, else: "--icons-user-star-hover: var(--icons-user-star)"}
                  class="rating-stars flex items-center justify-center gap-2 leading-none"
                >
                  <.review_rating_star :for={index <- 0..4} index={index} rating={@rating} />
                </div>
                <button
                  :if={@rating}
                  type="button"
                  phx-click="set_review_form_rating"
                  phx-value-rating=""
                  class="absolute top-1/2 -right-[27px] flex size-[27px] -translate-y-1/2 items-center justify-center text-[rgb(var(--foreground-tertiary))] transition hover:text-[rgb(var(--foreground-primary))]"
                  aria-label="Clear rating"
                >
                  <Lucide.x class="size-4" aria-hidden="true" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="hidden w-full flex-col items-center gap-0 sm:flex">
          <div class="aspect-2/3 w-[180px] overflow-hidden rounded-[6px] bg-[rgb(var(--surface-banner))]">
            <img
              :if={@cover_url}
              src={@cover_url}
              alt={"#{@vn.title} cover"}
              class="size-full object-cover object-center"
            />
          </div>
          <div class="group/rating relative mt-3 flex h-[46px] w-full items-center justify-center">
            <div class="relative flex items-center justify-center p-2">
              <button
                :if={@rating}
                type="button"
                phx-click="set_review_form_rating"
                phx-value-rating=""
                class="absolute top-1/2 -left-[27px] flex size-[27px] translate-x-2 -translate-y-1/2 items-center justify-center text-[rgb(var(--foreground-tertiary))] opacity-0 transition duration-200 group-hover/rating:translate-x-0 group-hover/rating:opacity-100 hover:text-[rgb(var(--foreground-primary))]"
                aria-label="Clear rating"
              >
                <Lucide.x class="size-4" aria-hidden="true" />
              </button>
              <div
                id="review-rating-stars-desktop"
                phx-hook="RatingStars"
                style={if @rating, do: nil, else: "--icons-user-star-hover: var(--icons-user-star)"}
                class="rating-stars flex items-center justify-center gap-1 leading-none"
              >
                <.review_rating_star :for={index <- 0..4} index={index} rating={@rating} />
              </div>
            </div>
          </div>
        </div>

        <div class="flex min-h-0 flex-1 flex-col bg-transparent px-4 pb-4 sm:overflow-y-auto sm:p-0">
          <div class="mb-4 hidden flex-row items-start justify-between gap-4 sm:flex">
            <h2
              id="review-dialog-title"
              class="text-[26px]/8 font-medium text-[rgb(var(--foreground-primary))]"
              style="font-family: var(--font-source-serif)"
            >
              {@vn.title}
            </h2>
            <button
              type="button"
              phx-click="close_review_dialog"
              data-modal-cancel
              class="flex size-8 shrink-0 items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] transition hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
              aria-label="Close review dialog"
            >
              <Lucide.x class="size-4" aria-hidden="true" />
            </button>
          </div>

          <div class="mb-4 flex flex-wrap items-start gap-x-3 gap-y-2">
            <.review_date_picker form={@form} open?={@date_picker_open?} />

            <div class="min-w-0 flex-1 max-lg:basis-full">
              <input
                id="review-note-toggle"
                type="checkbox"
                checked={ReviewCalendar.present_text?(@form["note"])}
                class="peer/note sr-only"
              />
              <label
                for="review-note-toggle"
                class="h-8 cursor-pointer text-sm/8 text-[rgb(var(--foreground-tertiary))] transition peer-checked/note:hidden hover:text-[rgb(var(--foreground-secondary))] sm:hidden"
              >
                Add a note
              </label>
              <div class="hidden peer-checked/note:block sm:block">
                <textarea
                  name="review[note]"
                  maxlength="280"
                  rows="1"
                  class="min-h-8 w-full resize-none rounded-[6px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-[6px] text-sm/5 text-[rgb(var(--foreground-primary))] transition placeholder:text-[rgb(var(--foreground-tertiary))] hover:bg-[rgb(var(--surface-elevated))]/80 focus:border-white/15 focus:outline-none sm:px-2 sm:py-[5px]"
                  placeholder="Add a note..."
                ><%= @form["note"] %></textarea>
                <%!--
                  Counter appears at 240+/280 to match Next.js
                  (`ReviewEditor.tsx` ~ line 520). phx-change already round-trips
                  on every keystroke, so server-rendering this is essentially
                  free — no extra hook needed.
                --%>
                <span
                  :if={note_chars(@form) >= 240}
                  class="mt-0.5 block pr-1 text-right text-[11px] text-[rgb(var(--foreground-tertiary))] tabular-nums"
                  aria-live="polite"
                >
                  {note_chars(@form)}/280
                </span>
              </div>
            </div>

            <%!--
              ONE source of truth for the spoiler flag — both desktop and
              mobile toggle UIs link to this hidden input via `for=`. Two
              inputs with the same `name` cause unchecking to fail because
              the still-checked sibling keeps submitting "true".
            --%>
            <input
              type="checkbox"
              id="review-is-spoiler-input"
              name="review[is_spoiler]"
              value="true"
              checked={@form["is_spoiler"]}
              class="sr-only"
            />
            <label
              for="review-is-spoiler-input"
              class="hidden h-8 shrink-0 cursor-pointer items-center gap-2 text-[13px] text-[rgb(var(--foreground-secondary))] transition-colors sm:flex"
            >
              <span class={[
                "relative h-5 w-9 rounded-full transition",
                @form["is_spoiler"] && "bg-[rgb(var(--icons-user-star-hover))]",
                !@form["is_spoiler"] && "bg-[rgb(var(--surface-menu-item-hover))]"
              ]}>
                <span class={[
                  "absolute top-0.5 left-0.5 size-4 rounded-full transition",
                  @form["is_spoiler"] && "translate-x-4 bg-white",
                  !@form["is_spoiler"] && "bg-[rgb(var(--foreground-tertiary))]"
                ]}>
                </span>
              </span>
              Spoiler
            </label>
          </div>

          <%!--
            Wrapper hosts the MarkdownEditor hook so Cmd+B / Cmd+I / Cmd+K
            (and Cmd+Enter → submits the surrounding review form) work
            here the same way they do in the comment composer. The hook
            binds to the first child textarea regardless of the element
            it's attached to, so a `<div>` wrapper is enough.
          --%>
          <%!--
            Wrapper hosts the MarkdownEditor hook so Cmd+B / Cmd+I / Cmd+K
            (and Cmd+Enter → submits the surrounding review form) work
            here the same way they do in the comment composer. The hook
            binds to the first child textarea regardless of the element
            it's attached to, so a `<div>` wrapper is enough.

            We deliberately omit the HTML5 `minlength` attribute on the
            textarea: it triggers the browser's native validation tooltip
            on submit, which doesn't match Next.js's inline error. We
            enforce the 40-char minimum server-side via `save_review`,
            which sets `@review_min_length_error?` for the inline message
            below.
          --%>
          <div
            id="review-content-editor"
            phx-hook="MarkdownEditor"
            phx-update="ignore"
            data-draft-key={@draft_key}
            class="mb-2 rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-3 max-lg:pb-2 sm:px-3 sm:pt-3 sm:pb-5"
          >
            <textarea
              name="review[content]"
              rows="10"
              data-modal-initial-focus
              class="max-h-[236px] min-h-[236px] w-full flex-1 resize-none border-0 bg-transparent p-0 text-sm/6 text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:outline-none sm:min-h-[224px] lg:max-h-[calc(60vh-200px)]"
              placeholder="Write a review..."
            ><%= @form["content"] %></textarea>
          </div>
          <p
            :if={@min_length_error?}
            class="mb-2 text-sm text-red-400"
            role="alert"
            aria-live="polite"
          >
            Review must be at least 40 characters
          </p>

          <div class="mt-4 flex items-center justify-between gap-3">
            <%!--
              Left slot — keeps width via `flex-1` even when its children are
              `sm:hidden` on desktop, so `justify-between` always pins Save
              to the right edge. Without this, an empty left slot collapses
              and Save drifts to the start.
            --%>
            <div class="flex flex-1 items-center">
              <button
                :if={@has_review?}
                type="button"
                phx-click="open_review_delete_dialog"
                class="cursor-pointer text-sm text-[rgb(var(--foreground-tertiary))] transition hover:text-red-400"
              >
                Delete
              </button>
              <label
                :if={!@has_review? && @content_length > 0}
                for="review-is-spoiler-input"
                class="flex items-center gap-2 text-[13px] text-[rgb(var(--foreground-secondary))] transition-colors sm:hidden"
              >
                <span class={[
                  "relative h-5 w-9 rounded-full transition",
                  @form["is_spoiler"] && "bg-[rgb(var(--icons-user-star-hover))]",
                  !@form["is_spoiler"] && "bg-[rgb(var(--surface-menu-item-hover))]"
                ]}>
                  <span class={[
                    "absolute top-0.5 left-0.5 size-4 rounded-full transition",
                    @form["is_spoiler"] && "translate-x-4 bg-white",
                    !@form["is_spoiler"] && "bg-[rgb(var(--foreground-tertiary))]"
                  ]}>
                  </span>
                </span>
                Spoiler
              </label>
            </div>
            <button
              type="submit"
              class="inline-flex h-9 items-center justify-center rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-5 text-sm font-normal text-white transition hover:bg-[rgb(var(--button-background-brand-hover))] active:bg-[rgb(var(--button-background-brand-pressed))]"
            >
              Save
            </button>
          </div>
          <p :if={@save_error} class="mt-3 text-sm text-[rgb(255_99_99)]" role="alert">
            {@save_error}
          </p>
        </div>
      </.form>
    </div>
    """
  end

  attr :index, :integer, required: true
  attr :rating, :any, default: nil

  def review_rating_star(assigns) do
    rating = assigns.rating || 0
    full? = rating >= assigns.index + 1
    half? = !full? and rating >= assigns.index + 0.5

    assigns =
      assigns
      |> assign(:full?, full?)
      |> assign(:half?, half?)
      |> assign(
        :base_state,
        cond do
          full? -> "full"
          half? -> "half"
          true -> "empty"
        end
      )
      |> assign(:half_value, rating_value_string(assigns.index + 0.5))
      |> assign(:full_value, rating_value_string(assigns.index + 1.0))

    ~H"""
    <span
      data-star
      data-base-state={@base_state}
      class="rating-star relative inline-block size-[27px] leading-none"
    >
      <svg
        viewBox="0 0 24 24"
        class="absolute inset-0 size-[27px]"
        fill="rgb(var(--surface-base))"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path
          class="text-[rgb(var(--border-divider))]"
          d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"
        />
      </svg>
      <svg
        data-fill="full"
        viewBox="0 0 24 24"
        class="absolute inset-0 size-[27px]"
        fill="currentColor"
        aria-hidden="true"
      >
        <path
          class="text-[rgb(var(--icons-user-star))]"
          d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"
        />
      </svg>
      <span data-fill="half" class="absolute inset-y-0 left-0 w-1/2 overflow-hidden">
        <svg
          viewBox="0 0 24 24"
          class="absolute inset-y-0 left-0 size-[27px]"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            class="text-[rgb(var(--icons-user-star))]"
            d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"
          />
        </svg>
      </span>
      <button
        type="button"
        phx-click="set_review_form_rating"
        phx-value-rating={@half_value}
        aria-label={"Rate #{@half_value} of 5"}
        class="absolute inset-y-0 left-0 z-10 w-1/2 cursor-pointer"
      >
      </button>
      <button
        type="button"
        phx-click="set_review_form_rating"
        phx-value-rating={@full_value}
        aria-label={"Rate #{@full_value} of 5"}
        class="absolute inset-y-0 right-0 z-10 w-1/2 cursor-pointer"
      >
      </button>
    </span>
    """
  end

  attr :shelves, :list, required: true
  attr :selected_ids, :list, required: true
  attr :initial_ids, :list, required: true
  attr :vn_title, :string, default: nil
  attr :new_shelf_name, :string, default: ""
  attr :create_shelf_error, :string, default: nil

  def list_dialog(assigns) do
    selected = MapSet.new(assigns.selected_ids)
    initial_selected = MapSet.new(assigns.initial_ids)

    assigns =
      assigns
      |> assign(:selected, selected)
      |> assign(:has_list_changes?, !MapSet.equal?(selected, initial_selected))

    ~H"""
    <div
      id="list-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="list-dialog-title"
        class="relative z-10 w-full max-w-[525px] overflow-hidden rounded-t-[16px] bg-[rgb(var(--surface-base))] shadow-2xl sm:rounded-[16px]"
      >
        <div class="flex items-center justify-between gap-4 border-b border-[rgb(var(--border-divider))] px-7 py-5 text-left">
          <h2
            id="list-dialog-title"
            class="line-clamp-2 text-lg/normal font-semibold tracking-[-0.01em] text-[rgb(var(--foreground-primary))]"
          >
            Add
            <span :if={@vn_title}>&lsquo;{@vn_title}&rsquo;</span><span :if={!@vn_title}>visual novel</span>
            to lists
          </h2>
        </div>

        <.form
          id="list-membership-form"
          for={%{}}
          as={:shelves}
          phx-change="update_list_membership"
          phx-submit="save_list_membership"
        >
          <div class="max-h-[320px] min-h-[200px] overflow-y-auto">
            <label
              :for={shelf <- @shelves}
              class={[
                "flex cursor-pointer items-center gap-3 px-7 py-3.5 text-sm transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]/80",
                MapSet.member?(@selected, shelf.id) && "bg-[rgb(var(--surface-elevated))]/60"
              ]}
            >
              <input
                type="checkbox"
                name="shelves[ids][]"
                value={shelf.id}
                checked={MapSet.member?(@selected, shelf.id)}
                class="size-[18px] rounded-[4px] border-[rgb(var(--foreground-secondary))]/30 bg-[rgb(var(--surface-base))] accent-[rgb(var(--button-background-brand-default))]"
              />
              <span class="min-w-0 flex-1 truncate font-medium text-[rgb(var(--foreground-primary))]">
                {shelf.name}
              </span>
              <span class="flex shrink-0 items-center gap-1.5">
                <span class="text-xs text-[rgb(var(--foreground-secondary))]/50 tabular-nums">
                  {shelf_vns_count(shelf)}
                </span>
                <%= if shelf_public?(shelf) do %>
                  <Lucide.globe
                    class="size-3.5 text-[rgb(var(--foreground-secondary))]/40"
                    aria-hidden="true"
                  />
                <% else %>
                  <Lucide.lock
                    class="size-3.5 text-[rgb(var(--foreground-secondary))]/40"
                    aria-hidden="true"
                  />
                <% end %>
              </span>
            </label>

            <div
              :if={@shelves == []}
              class="flex h-[240px] flex-col items-center justify-center gap-4 px-7"
            >
              <p class="text-center text-sm text-[rgb(var(--foreground-tertiary))]">No lists yet</p>
            </div>
          </div>
        </.form>

        <div class="border-t border-[rgb(var(--border-divider))] px-7 py-5">
          <.form
            for={%{"name" => @new_shelf_name}}
            as={:shelf}
            phx-change="change_shelf_name"
            phx-submit="create_shelf"
            class="flex flex-col gap-2"
          >
            <div class="flex items-center gap-2">
              <input
                type="text"
                name="shelf[name]"
                value={@new_shelf_name}
                maxlength="80"
                placeholder="Create a new list"
                data-modal-initial-focus
                class="h-10 min-w-0 flex-1 rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:border-white/15 focus:outline-none"
              />
              <button
                type="submit"
                class="inline-flex h-10 shrink-0 items-center justify-center rounded-[8px] border border-[rgb(var(--border-divider))] px-4 text-sm font-medium text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))]"
              >
                Create
              </button>
            </div>
          </.form>
          <p :if={@create_shelf_error} class="mt-2 text-sm text-[rgb(255_99_99)]" role="alert">
            {@create_shelf_error}
          </p>

          <div class="mt-5 flex items-center justify-end gap-3">
            <button
              type="button"
              phx-click="close_list_dialog"
              data-modal-cancel
              class="h-11 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))]"
            >
              Cancel
            </button>
            <button
              :if={@shelves != []}
              type="submit"
              form="list-membership-form"
              disabled={!@has_list_changes?}
              class="h-11 min-w-[74px] rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-4 text-sm font-normal text-white transition hover:bg-[rgb(var(--button-background-brand-hover))] disabled:opacity-40 disabled:hover:bg-[rgb(var(--button-background-brand-default))]"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def recommendation_dialog(assigns) do
    ~H"""
    <div
      id="recommendation-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="recommendation-dialog-title"
        class="relative z-10 w-full max-w-[437px] rounded-t-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] shadow-2xl sm:rounded-t-[12px] sm:rounded-b-[16px]"
      >
        <div class="flex items-center justify-between gap-4 border-b border-[rgb(var(--border-divider))] py-3.5 pr-[21px] pl-6">
          <h2
            id="recommendation-dialog-title"
            class="text-xl font-medium text-[rgb(var(--foreground-primary))] sm:text-2xl"
          >
            Add Recommendation
          </h2>
          <button
            type="button"
            phx-click="close_recommendation_dialog"
            data-modal-cancel
            class="flex size-11 items-center justify-center rounded-full border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--border-divider))]"
            aria-label="Close recommendation search"
          >
            <Lucide.x class="size-5" aria-hidden="true" />
          </button>
        </div>
        <div class="p-6 pb-8">
          <KaguyaWeb.SharedComponents.Search.vn_select_search
            id="recommendation-search"
            select_event="add_recommendation"
            page_size={5}
            placeholder="Search visual novels"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :error, :string, default: nil

  def tag_dialog(assigns) do
    assigns = assign(assigns, :has_query?, String.trim(assigns.query || "") != "")

    ~H"""
    <div
      id="tag-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="tag-dialog-title"
        class="relative z-10 w-full max-w-[420px] overflow-hidden rounded-t-[14px] bg-[#0A0A0A] shadow-[0_8px_40px_rgba(0,0,0,0.55)] sm:rounded-[14px]"
      >
        <div class="px-5 pt-5 pb-4">
          <div class="mb-3 flex items-center justify-between gap-4">
            <h2
              id="tag-dialog-title"
              class="text-lg font-semibold text-[rgb(var(--foreground-primary))]"
            >
              Add tag
            </h2>
            <button
              type="button"
              phx-click="close_tag_dialog"
              data-modal-cancel
              class="flex size-8 items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] transition hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
              aria-label="Close tag dialog"
            >
              <Lucide.x class="size-4" aria-hidden="true" />
            </button>
          </div>
          <.form for={%{}} as={:tag_search} phx-change="search_tags" phx-submit="search_tags">
            <input
              type="search"
              name="tag_search[query]"
              value={@query}
              placeholder="Search tags..."
              data-modal-initial-focus
              phx-debounce="150"
              class="h-10 w-full rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:border-[rgb(var(--text-field-border-focus))] focus:outline-none"
            />
          </.form>
        </div>

        <div :if={@error} class="px-5 pb-4 text-sm text-red-400">{@error}</div>

        <div :if={@has_query? and is_nil(@error)} class="max-h-[280px] overflow-auto px-2 pb-3">
          <p
            :if={@results == []}
            class="px-3 py-4 text-sm text-[rgb(var(--foreground-tertiary))]"
          >
            No tags found
          </p>
          <button
            :for={tag <- @results}
            type="button"
            phx-click="add_tag"
            phx-value-tag-id={tag.id}
            class="flex w-full items-center justify-between gap-3 rounded-[6px] px-3 py-2 text-left transition-colors hover:bg-white/5"
          >
            <span class="min-w-0 truncate text-sm text-[rgb(var(--foreground-primary))]">
              {tag.name}
            </span>
            <span class="shrink-0 text-xs text-[rgb(var(--foreground-tertiary))]">
              {tag_category_label(tag)}
            </span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :characters, :list, default: []

  def quote_dialog(assigns) do
    ~H"""
    <div
      id="quote-dialog"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-end bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:justify-center sm:p-6"
      role="presentation"
    >
      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-labelledby="quote-dialog-title"
        class="relative z-10 w-full max-w-[560px] rounded-t-[16px] bg-[rgb(var(--surface-base))] p-0 shadow-[0_8px_40px_rgba(0,0,0,0.55)] sm:rounded-[16px]"
      >
        <div class="flex items-center justify-between gap-4">
          <h2
            id="quote-dialog-title"
            class="px-6 pt-5 text-lg font-semibold text-[rgb(var(--foreground-primary))]"
          >
            Add quote
          </h2>
          <button
            type="button"
            phx-click="close_quote_dialog"
            data-modal-cancel
            class="mt-4 mr-5 flex size-8 items-center justify-center rounded-full text-[rgb(var(--foreground-secondary))] transition hover:bg-white/6 hover:text-[rgb(var(--foreground-primary))]"
            aria-label="Close quote dialog"
          >
            <Lucide.x class="size-4" aria-hidden="true" />
          </button>
        </div>
        <.form for={%{}} as={:quote} phx-submit="save_quote" class="flex flex-col">
          <div class="flex flex-col gap-4 px-6 pt-4 pb-6">
            <div class="overflow-hidden rounded-lg border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]/30 transition-colors focus-within:border-[rgb(var(--text-field-border-focus))]">
              <textarea
                name="quote[text]"
                rows="5"
                required
                data-modal-initial-focus
                placeholder="Paste the quote here..."
                class="w-full resize-none rounded-none border-0 bg-transparent px-4 py-3.5 text-[16px] leading-[1.65] text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-quaternary))]/70 placeholder:italic focus:outline-none"
                style="font-family: var(--font-source-serif)"
              ></textarea>
            </div>
            <details :if={@characters != []} class="group">
              <summary class="w-fit cursor-pointer list-none text-left text-xs text-[rgb(var(--foreground-tertiary))] transition marker:hidden hover:text-[rgb(var(--foreground-secondary))] [&::-webkit-details-marker]:hidden">
                + Attribute to a character
              </summary>
              <div class="mt-3 flex flex-col gap-1">
                <div class="relative">
                  <.search_icon
                    class="pointer-events-none absolute top-1/2 left-3 size-3.5 -translate-y-1/2 text-[rgb(var(--foreground-tertiary))]"
                    aria-hidden="true"
                  />
                  <input
                    type="search"
                    placeholder="Search characters..."
                    aria-label="Search characters"
                    class="h-9 w-full rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] pr-3 pl-9 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:outline-none"
                  />
                </div>
                <div class="-mx-1 max-h-[200px] overflow-auto px-1">
                  <label class="flex w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-left transition hover:bg-white/4">
                    <input
                      type="radio"
                      name="quote[character_id]"
                      value=""
                      checked={true}
                      class="size-4 shrink-0"
                    />
                    <span class="size-7 shrink-0 rounded-full bg-[rgb(var(--surface-elevated))]">
                    </span>
                    <span class="truncate text-sm text-[rgb(var(--foreground-primary))]">
                      No character attribution
                    </span>
                  </label>
                  <label
                    :for={character <- @characters}
                    class="flex w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-left transition hover:bg-white/4"
                  >
                    <input
                      type="radio"
                      name="quote[character_id]"
                      value={character.id}
                      class="size-4 shrink-0"
                    />
                    <KaguyaWeb.SharedComponents.CharacterImage.character_image
                      character={character}
                      sizes="28px"
                      class="size-7 shrink-0 object-cover"
                      fallback_class="size-7 shrink-0 bg-[rgb(var(--surface-elevated))]"
                      rounded="rounded-full"
                    />
                    <span class="truncate text-sm text-[rgb(var(--foreground-primary))]">
                      {character_name(character)}
                    </span>
                  </label>
                </div>
              </div>
            </details>
          </div>

          <div class="flex justify-end gap-2 px-6 pb-5">
            <button
              type="button"
              phx-click="close_quote_dialog"
              data-modal-cancel
              class="h-9 rounded-[4px] bg-white/6 px-4 text-sm font-medium text-[rgb(var(--foreground-primary))] transition hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="h-9 rounded-[4px] bg-[rgb(var(--foreground-primary))] px-5 text-sm font-medium text-[rgb(var(--surface-base))] transition hover:opacity-90"
            >
              Add quote
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :media, :map, required: true

  def media_lightbox(assigns) do
    ~H"""
    <div
      id="media-lightbox"
      phx-hook="ModalDialog"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/85 p-0 backdrop-blur-[2px]"
      role="presentation"
    >
      <button
        type="button"
        phx-click="close_media_lightbox"
        data-modal-cancel
        class="absolute inset-0 cursor-pointer"
        aria-label="Close media preview"
      >
      </button>

      <div
        data-modal-panel
        role="dialog"
        aria-modal="true"
        aria-label="Media preview"
        class="pointer-events-none relative flex h-[95vh] max-h-[95vh] w-[95vw] max-w-[95vw] items-center justify-center"
      >
        <button
          type="button"
          phx-click="close_media_lightbox"
          data-modal-cancel
          data-modal-initial-focus
          class="pointer-events-auto absolute top-2 right-2 z-20 flex size-11 items-center justify-center rounded-full bg-black/70 text-white transition hover:bg-black/90 focus:outline-hidden focus-visible:ring-2 focus-visible:ring-white/70"
          aria-label="Close image viewer"
        >
          <Lucide.x class="size-5" aria-hidden="true" />
        </button>

        <button
          :if={@media.count > 1}
          type="button"
          phx-click="previous_media"
          class="pointer-events-auto absolute top-1/2 left-4 z-10 hidden size-10 -translate-y-1/2 items-center justify-center rounded-full border-none bg-black/70 text-white transition hover:bg-black/90 lg:inline-flex"
          aria-label="Previous image"
        >
          <Lucide.chevron_left class="size-5" aria-hidden="true" />
        </button>

        <div class="relative flex size-full items-center justify-center p-4">
          <img
            src={@media.src}
            alt={@media.alt || "Expanded image"}
            class="pointer-events-auto relative size-auto max-h-[90vh] max-w-[90vw] object-contain"
          />
        </div>

        <button
          :if={@media.count > 1}
          type="button"
          phx-click="next_media"
          class="pointer-events-auto absolute top-1/2 right-4 z-10 hidden size-10 -translate-y-1/2 items-center justify-center rounded-full border-none bg-black/70 text-white transition hover:bg-black/90 lg:inline-flex"
          aria-label="Next image"
        >
          <Lucide.chevron_right class="size-5" aria-hidden="true" />
        </button>

        <div
          :if={@media.count > 1}
          class="absolute bottom-6 left-1/2 z-10 -translate-x-1/2 rounded-full bg-black/70 px-4 py-2 text-sm text-white"
        >
          {@media.index + 1} / {@media.count}
        </div>
      </div>
    </div>
    """
  end

  defp review_form_rating(form) do
    case Float.parse(to_string(form["rating"] || "")) do
      {rating, ""} -> rating
      _ -> nil
    end
  end

  defp review_content_length(form) when is_map(form),
    do: form |> Map.get("content", "") |> to_string() |> String.trim() |> String.length()

  defp note_chars(form) when is_map(form),
    do: form |> Map.get("note", "") |> to_string() |> String.length()

  defp note_chars(_form), do: 0

  defp rating_value_string(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp vn_cover_src(vn) do
    images = Map.get(vn, :images) || %{}

    Map.get(images, :medium) ||
      Map.get(images, "medium") ||
      Map.get(images, :small) ||
      Map.get(images, "small") ||
      Map.get(images, :large) ||
      Map.get(images, "large")
  end

  defp shelf_vns_count(shelf) do
    Map.get(shelf, :vns_count) || Map.get(shelf, "vns_count") || 0
  end

  defp shelf_public?(shelf), do: Map.get(shelf, :is_public) || Map.get(shelf, "is_public")

  defp character_name(character),
    do: Map.get(character, :name) || Map.get(character, "name") || ""

  defp tag_category_label(%{category: :content}), do: "Content"
  defp tag_category_label(%{category: :sexual}), do: "Sexual"
  defp tag_category_label(%{category: :technical}), do: "Technical"
  defp tag_category_label(%{category: "CONTENT"}), do: "Content"
  defp tag_category_label(%{category: "SEXUAL"}), do: "Sexual"
  defp tag_category_label(%{category: "TECHNICAL"}), do: "Technical"
  defp tag_category_label(%{category: category}) when is_binary(category), do: category
  defp tag_category_label(_), do: "Tag"
end

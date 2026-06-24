defmodule KaguyaWeb.Reviews.ShowComponents do
  @moduledoc """
  HEEx components for the single-review show page (`ReviewLive.Show`).

  All components are stateless function components. They take normalized
  maps produced by `KaguyaWeb.ReviewLive.Data` so they never reach into
  Ecto schemas directly.

    * `review_header/1` — author row + VN title + rating stars (desktop)
    * `mobile_header/1` — compact mobile variant
    * `review_body/1`   — review prose (escaped, link-aware)
    * `actions_bar/1`   — like button + share + author/mod menu
    * `cover_panel/1`   — right rail VN cover (desktop)
    * `more_reviews_grid/1` — bottom grid "More from {author}"
    * `hidden_banner/1` / `locked_banner/1` — moderation banners
  """

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu

  alias KaguyaWeb.SharedComponents.Cover, as: SharedCover
  alias KaguyaWeb.SharedComponents.LikeButton
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  # ---------------------------------------------------------------------------
  # Desktop header
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :vn, :map, required: true
  attr :owner, :map, required: true

  def review_header(assigns) do
    ~H"""
    <header class="max-lg:hidden">
      <div class="flex items-center gap-2">
        <.author_avatar owner={@owner} size="size-6" />

        <div class="flex items-center gap-2">
          <p class="text-foreground-primary text-sm">
            Review by
            <.link
              navigate={profile_path(@owner)}
              class="text-foreground-primary font-semibold hover:underline"
            >
              {display_name(@owner)}
            </.link>
          </p>

          <span
            class="text-foreground-primary mt-[3px] text-xs font-light"
            title={SharedTime.format_datetime_tooltip(@review.inserted_at)}
          >
            {SharedTime.calendar_custom(@review.inserted_at)}
          </span>

          <span
            :if={@review.is_edited}
            class="text-foreground-primary mt-[3px] -ml-1.5 text-xs font-light"
          >
            (edited)
          </span>

          <.locked_chip :if={@review.is_locked} />
        </div>
      </div>

      <hr class="border-border-divider mt-3 mb-4 border-t" />

      <div class="flex flex-col gap-2">
        <.link
          navigate={vn_path(@vn)}
          class="font-source-serif lg:hover:text-foreground-secondary text-foreground-primary w-fit max-w-[693px] text-[28px] leading-[34px] font-semibold"
          style="font-family: var(--font-source-serif)"
        >
          {@vn.title}
        </.link>

        <.display_ratings rating={@review.rating} />
      </div>
    </header>
    """
  end

  # ---------------------------------------------------------------------------
  # Mobile header
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :vn, :map, required: true
  attr :owner, :map, required: true

  def mobile_header(assigns) do
    ~H"""
    <header class="px-5 lg:hidden">
      <div class="flex justify-between gap-7">
        <div class="flex flex-col gap-2">
          <div class="flex items-center gap-2">
            <.author_avatar owner={@owner} size="size-[26px]" />
            <.link
              navigate={profile_path(@owner)}
              class="text-foreground-primary text-xs font-semibold sm:text-sm"
            >
              {display_name(@owner)}
            </.link>
          </div>

          <.link
            navigate={vn_path(@vn)}
            class="text-foreground-primary line-clamp-2 text-2xl leading-[30px] font-semibold sm:text-[28px] sm:leading-[34px]"
            style="font-family: var(--font-source-serif)"
          >
            {@vn.title}
          </.link>

          <.display_ratings rating={@review.rating} />

          <div class="mt-1 flex items-center gap-0.5">
            <span
              class="text-foreground-tertiary text-xs font-normal"
              title={SharedTime.format_datetime_tooltip(@review.inserted_at)}
            >
              Reviewed {short_date(@review.inserted_at)}
            </span>
            <span :if={@review.is_edited} class="text-foreground-primary text-xs font-light">
              (edited)
            </span>
            <.locked_chip :if={@review.is_locked} class="ml-1" />
          </div>
        </div>

        <.link navigate={vn_path(@vn)} class="shrink-0">
          <SharedCover.cover
            vn={@vn}
            sizes="100px"
            class="h-[150px] w-[100px] rounded-[2px]"
          />
        </.link>
      </div>
    </header>
    """
  end

  # ---------------------------------------------------------------------------
  # Review body
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :class, :any, default: nil

  def review_body(assigns) do
    ~H"""
    <article
      :if={present?(@review.content)}
      class={
        [
          # Typography for the review body. The `review-content` class hooks
          # the scoped paragraph/list/blockquote rules in `assets/css/markdown.css`
          # that mirror frontend `ReviewReadMore`'s `prose-p:my-3 prose-p:leading-*`
          # output (the LV side doesn't load @tailwindcss/typography, so we apply
          # those rules manually).
          "review-content text-foreground-primary text-base font-normal sm:text-lg sm:leading-[28px]",
          @class
        ]
      }
    >
      <.spoiler_banner :if={@review.is_spoiler} />
      <div class="kaguya-markdown">
        <KaguyaWeb.SharedComponents.Markdown.markdown_inline content={@review.content} />
      </div>
    </article>
    """
  end

  defp spoiler_banner(assigns) do
    ~H"""
    <p class="mb-4 inline-flex items-center gap-2 rounded-md border border-amber-500/30 bg-amber-500/15 px-3 py-1.5 text-xs text-amber-500">
      <Lucide.triangle_alert class="size-3.5" aria-hidden /> Contains spoilers
    </p>
    """
  end

  # ---------------------------------------------------------------------------
  # Actions bar (like, share, author/mod menu)
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :liked_by_me, :boolean, default: false
  attr :is_mine, :boolean, default: false
  attr :can_moderate, :boolean, default: false
  attr :is_logged_in, :boolean, default: false
  attr :share_url, :string, required: true

  @doc """
  Like button + overflow menu (Share / Edit / Delete / Hide / Lock).

  Share is the first item *inside* the dropdown (not a separate button), so
  anonymous viewers and viewers without edit/mod rights still see the menu
  trigger.
  """
  def actions_bar(assigns) do
    ~H"""
    <%!--
      No `mt-5` here — the body wrapper above carries the spacing
      (actions sit flush below body with only `prose-p:my-3`'s trailing
      margin between them).
    --%>
    <div class="flex items-center gap-5">
      <LikeButton.like_button
        id={"review-#{@review.id}-like"}
        click="toggle_like"
        liked={@liked_by_me}
        likes_count={@review.likes_count}
      />

      <.review_menu
        review={@review}
        is_mine={@is_mine}
        can_moderate={@can_moderate}
      />
    </div>
    """
  end

  attr :review, :map, required: true
  attr :is_mine, :boolean, required: true
  attr :can_moderate, :boolean, required: true

  defp review_menu(assigns) do
    ~H"""
    <.menu id="review-menu-dropdown" align="end" side_offset={4}>
      <:trigger
        aria-label="Review actions"
        class="group -ml-2 flex size-9 cursor-pointer items-center justify-center rounded-full p-0 lg:size-8 lg:hover:bg-white/4"
      >
        <Lucide.ellipsis class="text-foreground-secondary size-4" aria-hidden />
      </:trigger>

      <div class="bg-surface-menu-item-default border-border-divider min-w-[140px] rounded-xl border p-1 shadow-[0_8px_24px_rgba(0,0,0,0.3)]">
        <button
          type="button"
          data-menu-dismiss
          data-share-button
          class="text-foreground-primary flex w-full cursor-pointer items-center justify-start gap-2.5 rounded-lg border-0 px-3 py-2 text-[13px] font-medium transition-colors hover:bg-white/4 active:bg-white/6"
        >
          <Lucide.share_2 class="text-foreground-secondary size-[15px]" aria-hidden /> Share
        </button>

        <.menu_item
          :if={@is_mine}
          event="open_edit"
          class="text-foreground-primary flex w-full cursor-pointer items-center justify-start gap-2.5 rounded-lg border-0 px-3 py-2 text-[13px] font-medium transition-colors hover:bg-white/4 active:bg-white/6"
        >
          <Lucide.pencil class="text-foreground-secondary size-[15px]" aria-hidden /> Edit
        </.menu_item>

        <.menu_item
          :if={@is_mine}
          event="confirm_delete"
          data-confirm="Delete this review? This can't be undone."
          class="flex w-full cursor-pointer items-center justify-start gap-2.5 rounded-lg border-0 px-3 py-2 text-[13px] font-medium text-[#f94441] transition-colors hover:bg-white/4 active:bg-white/6"
        >
          <Lucide.trash_2 class="size-[15px]" aria-hidden /> Delete
        </.menu_item>

        <.menu_item
          :if={@can_moderate and not @is_mine}
          event="toggle_hidden"
          class="text-foreground-primary flex w-full cursor-pointer items-center justify-start gap-2.5 rounded-lg border-0 px-3 py-2 text-[13px] font-medium transition-colors hover:bg-white/4 active:bg-white/6"
        >
          <Lucide.eye_off class="text-foreground-secondary size-[15px]" aria-hidden />
          {if @review.is_hidden, do: "Unhide", else: "Hide"}
        </.menu_item>

        <.menu_item
          :if={@can_moderate}
          event="toggle_locked"
          class="text-foreground-primary flex w-full cursor-pointer items-center justify-start gap-2.5 rounded-lg border-0 px-3 py-2 text-[13px] font-medium transition-colors hover:bg-white/4 active:bg-white/6"
        >
          <Lucide.lock class="text-foreground-secondary size-[15px]" aria-hidden />
          {if @review.is_locked, do: "Unlock comments", else: "Lock comments"}
        </.menu_item>
      </div>
    </.menu>
    """
  end

  # ---------------------------------------------------------------------------
  # Right rail cover panel
  # ---------------------------------------------------------------------------

  attr :vn, :map, required: true

  def cover_panel(assigns) do
    ~H"""
    <SharedCover.cover
      vn={@vn}
      sizes="180px"
      link
      eager
      class="w-full rounded-[8px]"
    />
    """
  end

  # ---------------------------------------------------------------------------
  # More reviews by the same user
  # ---------------------------------------------------------------------------

  attr :owner, :map, required: true
  attr :items, :list, required: true

  def more_reviews_grid(assigns) do
    ~H"""
    <section
      :if={@items != []}
      class="mt-7 flex flex-col gap-4 px-5 pb-8 lg:mt-0 lg:gap-0 lg:px-0 lg:pb-0"
    >
      <.link
        navigate={"/@#{@owner.username}/reviews"}
        class="hover:text-foreground-secondary text-foreground-primary text-base font-medium transition-colors"
      >
        More from {display_name(@owner)}
      </.link>

      <hr class="border-border-divider mt-3 mb-5 border-t max-lg:hidden" />

      <div class="grid grid-cols-3 gap-2 lg:grid-cols-5 lg:gap-4">
        <.link
          :for={item <- Enum.take(@items, 5)}
          navigate={review_path(@owner, item.visual_novel)}
          class="flex flex-col max-lg:nth-[n+4]:hidden"
        >
          <SharedCover.cover
            vn={item.visual_novel}
            sizes="(max-width: 640px) 100px, 146px"
            shadow
            class="w-full rounded-[6px]"
          />

          <span
            :if={positive_rating?(item.rating)}
            class="inline-flex items-center pt-[3px] leading-none text-[rgb(var(--icons-star-muted))]"
          >
            <span class="text-[11px] tracking-[-0.5px] lg:text-[12px]">
              {String.duplicate("★", full_star_count(item.rating))}
            </span>
            <span
              :if={fractional_rating?(item.rating)}
              class="relative top-px ml-px text-[9px] lg:text-[10px]"
            >
              ½
            </span>
          </span>
        </.link>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Banners
  # ---------------------------------------------------------------------------

  def hidden_banner(assigns) do
    ~H"""
    <div class="mb-4 inline-flex items-center gap-2 rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-1.5 text-xs text-amber-400">
      <Lucide.eye_off class="size-3.5" aria-hidden />
      Hidden by moderators. Only you and moderators can see it.
    </div>
    """
  end

  def locked_banner(assigns) do
    ~H"""
    <div class="text-foreground-tertiary mb-5 flex items-center gap-2 text-sm">
      <Lucide.lock class="size-3.5 shrink-0" aria-hidden />
      <span>Comments are disabled on this review.</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Edit dialog
  # ---------------------------------------------------------------------------

  attr :review, :map, required: true
  attr :form, :map, default: nil
  attr :saving, :boolean, default: false
  attr :error_message, :string, default: nil

  def edit_dialog(assigns) do
    ~H"""
    <div
      id="review-edit-dialog"
      role="dialog"
      aria-modal="true"
      class="fixed inset-0 z-120 flex items-center justify-center bg-black/50 p-4"
    >
      <form
        phx-submit="submit_edit"
        phx-click-away="close_edit"
        class="bg-surface-base w-full max-w-[640px] rounded-[14px] p-6 shadow-[0_24px_64px_rgba(0,0,0,0.4)]"
      >
        <h2 class="text-foreground-primary mb-4 text-lg font-semibold">Edit review</h2>
        <p :if={@error_message} class="mb-3 text-sm text-[rgb(255_99_99)]">{@error_message}</p>

        <label class="text-foreground-tertiary mb-2 block text-xs font-medium tracking-wider uppercase">
          Review
        </label>
        <textarea
          name="content"
          rows="10"
          maxlength="20000"
          class="bg-surface-elevated border-text-field-border focus:ring-button-background-brand-default placeholder:text-foreground-primary/40 text-foreground-primary w-full rounded-md border p-3 text-sm focus:ring-2 focus:outline-none"
          placeholder="Write your review..."
        ><%= @review.content || "" %></textarea>

        <label class="text-foreground-secondary mt-4 flex items-center gap-2 text-sm">
          <input type="checkbox" name="is_spoiler" value="true" checked={@review.is_spoiler} />
          Contains spoilers
        </label>

        <div class="mt-6 flex items-center justify-end gap-2">
          <button
            type="button"
            phx-click="close_edit"
            class="bg-button-background-neutral-default text-foreground-primary rounded-full px-4 py-2 text-sm font-semibold"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={@saving}
            class="bg-button-background-brand-default text-button-text-on-brand rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
          >
            {if @saving, do: "Saving…", else: "Save changes"}
          </button>
        </div>
      </form>
    </div>
    """
  end

  # ===========================================================================
  # Building blocks
  # ===========================================================================

  attr :rating, :float, default: nil
  attr :class, :any, default: nil
  attr :star_class, :any, default: nil

  @doc """
  Read-only 5-star rating display.
  """
  def display_ratings(assigns), do: KaguyaWeb.VN.Icons.display_ratings(assigns)

  attr :owner, :map, required: true
  attr :size, :string, required: true

  defp author_avatar(assigns) do
    ~H"""
    <.link navigate={profile_path(@owner)} class="shrink-0">
      <%= if @owner.avatar_url do %>
        <img
          src={@owner.avatar_url}
          alt={display_name(@owner)}
          class={[@size, "rounded-full object-cover"]}
        />
      <% else %>
        <div class={[
          @size,
          "bg-surface-banner text-foreground-secondary flex items-center justify-center rounded-full text-xs"
        ]}>
          {initials(@owner)}
        </div>
      <% end %>
    </.link>
    """
  end

  attr :class, :any, default: nil

  defp locked_chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-md border border-amber-500/30 bg-amber-500/15 px-1.5 py-0 text-xs font-semibold text-amber-500",
      @class
    ]}>
      <Lucide.lock class="size-2.5" aria-hidden />
      <span class="text-[11px]">Locked</span>
    </span>
    """
  end

  # ===========================================================================
  # Helpers (kept local; mirror conventions used in Lists.ShowComponents)
  # ===========================================================================

  defp profile_path(%{username: username}) when is_binary(username), do: "/@#{username}"
  defp profile_path(_), do: "/"

  defp vn_path(%{slug: slug}) when is_binary(slug), do: "/vn/#{slug}"
  defp vn_path(_), do: "/"

  defp review_path(%{username: username}, %{slug: vn_slug})
       when is_binary(username) and is_binary(vn_slug),
       do: "/@#{username}/reviews/#{vn_slug}"

  defp review_path(_, _), do: "/"

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp initials(%{display_name: name}) when is_binary(name) and name != "",
    do: initials_from(name)

  defp initials(%{username: name}) when is_binary(name) and name != "", do: initials_from(name)
  defp initials(_), do: "?"

  defp initials_from(name) do
    name
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", fn part -> part |> String.first() |> String.upcase() end)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp positive_rating?(rating) when is_integer(rating) or is_float(rating), do: rating > 0
  defp positive_rating?(_), do: false

  defp full_star_count(rating) when is_integer(rating),
    do: rating |> max(0) |> min(5)

  defp full_star_count(rating) when is_float(rating),
    do: rating |> Float.floor() |> trunc() |> max(0) |> min(5)

  defp full_star_count(_), do: 0

  defp fractional_rating?(rating) when is_float(rating) do
    rating > 0 and rating < 5 and rating != Float.floor(rating)
  end

  defp fractional_rating?(_), do: false

  # "DD MMM YYYY" formatter used in the mobile header.
  defp short_date(nil), do: ""

  defp short_date(%DateTime{} = dt) do
    "#{pad2(dt.day)} #{short_month(dt.month)} #{dt.year}"
  end

  defp short_date(%NaiveDateTime{} = dt) do
    dt |> DateTime.from_naive!("Etc/UTC") |> short_date()
  end

  defp short_date(_), do: ""

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)

  defp short_month(1), do: "Jan"
  defp short_month(2), do: "Feb"
  defp short_month(3), do: "Mar"
  defp short_month(4), do: "Apr"
  defp short_month(5), do: "May"
  defp short_month(6), do: "Jun"
  defp short_month(7), do: "Jul"
  defp short_month(8), do: "Aug"
  defp short_month(9), do: "Sep"
  defp short_month(10), do: "Oct"
  defp short_month(11), do: "Nov"
  defp short_month(12), do: "Dec"
end

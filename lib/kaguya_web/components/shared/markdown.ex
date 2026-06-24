defmodule KaguyaWeb.SharedComponents.Markdown do
  # NOTE: `~S"""` keeps the heredoc literal so the @vn / #{...} tokens in
  # the docstring examples don't get evaluated as module attributes /
  # interpolations at compile time.
  @moduledoc ~S"""
  Shared markdown rendering wrapper for user-authored markdown content.

  Wraps the existing `KaguyaWeb.Markdown.UserContent.to_html/1` pipeline
  with the right typographic CSS class, so review bodies, character
  descriptions, producer descriptions, user bios, and discussion posts all
  share the same look. Raw binaries are always treated as markdown; callers
  that already rendered trusted HTML must pass a `{:safe, iodata}` tuple.

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 3.

  ## API

      <%!-- Raw markdown string (most common — reviews, descriptions) --%>
      <.markdown content={@review.content} />

      <%!-- Already a {:safe, ...} tuple --%>
      <.markdown content={KaguyaWeb.Markdown.UserContent.to_html(@bio)} />

      <%!-- Legal pages --%>
      <.markdown content={Markdown.to_html(@page.body)} variant="policy" />

      <%!-- Truncated with read-more toggle --%>
      <.markdown content={@vn.description} read_more read_more_id={"vn-#{@vn.id}-desc"} read_more_lines={6} />

  ## Variants

  - `"user"` (default) — wraps in `<div class="kaguya-markdown">` for the
    user-content typography (paragraph spacing, word-wrap).
  - `"policy"` — no wrapper class; intended for already-safe policy tuples.
  - `"plain"` — no wrapper class; for places that need just the rendered
    body inside an existing styled container.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Markdown.UserContent

  import Phoenix.HTML, only: [safe_to_string: 1]

  attr :content, :any,
    required: true,
    doc: "Either a raw markdown binary, a `{:safe, iodata}` tuple, or `nil`."

  attr :variant, :string,
    default: "user",
    values: ~w(user comment bio policy plain),
    doc:
      "`user` wraps in `kaguya-markdown` typography; `comment` and `bio` use their tighter typography. `policy` and `plain` skip the wrapper class."

  attr :class, :any, default: nil, doc: "Extra classes on the wrapper element."

  attr :read_more, :boolean,
    default: false,
    doc: "Wrap the rendered content in `<.read_more>` for client-toggled truncation."

  attr :read_more_id, :string,
    default: nil,
    doc: "Required when `read_more={true}` — stable DOM id for the toggle."

  attr :read_more_lines, :integer,
    default: 6,
    doc: "Legacy line-clamp value; kept for existing callsites. Prefer `read_more_limit`."

  attr :read_more_limit, :integer,
    default: 794,
    doc:
      "Single-breakpoint character budget. Ignored when both `read_more_mobile_limit` and `read_more_desktop_limit` are set."

  attr :read_more_mobile_limit, :integer,
    default: nil,
    doc:
      "Mobile (`<lg`) character budget. Set both this and `read_more_desktop_limit` to render two collapsed variants and swap via CSS — matches Next.js's responsive truncation (e.g. 330/794 for descriptions, 330/428 for reviews)."

  attr :read_more_desktop_limit, :integer,
    default: nil,
    doc: "Desktop (`lg`) character budget. See `read_more_mobile_limit`."

  attr :read_more_expand_label, :string, default: "more"
  attr :read_more_collapse_label, :string, default: "less"

  attr :rest, :global

  def markdown(assigns) do
    assigns =
      assigns
      |> assign(:rendered, render_content(assigns.content, assigns.variant))
      |> assign(:wrapper_class, wrapper_class(assigns.variant))
      |> assign(:read_more_data, read_more_data(assigns))

    ~H"""
    <%= if @read_more && @read_more_data[:truncated?] do %>
      <div
        id={@read_more_id || raise_missing_id()}
        phx-hook="ReadMore"
        data-readmore
        data-expanded="false"
        class={[@wrapper_class, @class]}
        {@rest}
      >
        <%= if @read_more_data[:responsive?] do %>
          <div data-readmore-collapsed-mobile class="lg:hidden">
            {@read_more_data.collapsed_mobile}
          </div>
          <div data-readmore-collapsed-desktop class="hidden lg:block">
            {@read_more_data.collapsed_desktop}
          </div>
        <% else %>
          <div data-readmore-collapsed>{@read_more_data.collapsed}</div>
        <% end %>
        <div data-readmore-expanded class="hidden">{@read_more_data.expanded}</div>
      </div>
    <% else %>
      <div class={[@wrapper_class, @class]} {@rest}>
        {@rendered}
      </div>
    <% end %>
    """
  end

  @doc """
  Inline variant of `markdown/1` — renders the body without any wrapping
  `<div>`. Use when the parent already provides typography (e.g. a review
  card with `line-clamp-5` + `[&_p]:my-1` styles).

  Use `markdown/1` for stand-alone descriptions; use `markdown_inline/1`
  inside containers that own their own typography. The goal is to make
  this the single entry point for rendering raw markdown binaries.
  """
  attr :content, :any, required: true
  attr :variant, :string, default: "user", values: ~w(user comment bio policy plain)

  def markdown_inline(assigns) do
    assigns = assign(assigns, :rendered, render_content(assigns.content, assigns.variant))

    ~H"""
    {@rendered}
    """
  end

  # ---------------------------------------------------------------------------
  # Content normalization
  # ---------------------------------------------------------------------------

  # Already a safe tuple — render verbatim.
  defp render_content({:safe, _iodata} = safe, _variant), do: safe

  # nil or empty → render nothing.
  defp render_content(nil, _variant), do: {:safe, ""}
  defp render_content("", _variant), do: {:safe, ""}

  # Markdown source — compile through the user-content pipeline with the
  # preset matching the surface variant.
  defp render_content(content, variant) when is_binary(content) do
    UserContent.to_html(content, preset: preset_for(variant))
  end

  defp render_content(_other, _variant), do: {:safe, ""}

  defp preset_for("comment"), do: :comment
  defp preset_for("bio"), do: :bio
  defp preset_for(_), do: :default

  defp read_more_data(%{read_more: true, content: content} = assigns) when is_binary(content) do
    preset = preset_for(assigns.variant)
    mobile = assigns.read_more_mobile_limit
    desktop = assigns.read_more_desktop_limit

    if is_integer(mobile) and is_integer(desktop) do
      responsive_read_more_data(content, preset, mobile, desktop, assigns)
    else
      single_read_more_data(content, preset, assigns.read_more_limit, assigns)
    end
  end

  defp read_more_data(_assigns), do: %{truncated?: false}

  defp single_read_more_data(content, preset, limit, assigns) do
    case truncate_markdown(content, limit) do
      {:ok, source} ->
        %{
          truncated?: true,
          responsive?: false,
          collapsed: render_collapsed(source, preset, assigns),
          expanded: render_expanded(content, preset, assigns)
        }

      :not_truncated ->
        %{truncated?: false}
    end
  end

  defp responsive_read_more_data(content, preset, mobile, desktop, assigns) do
    mobile_result = truncate_markdown(content, mobile)
    desktop_result = truncate_markdown(content, desktop)

    case {mobile_result, desktop_result} do
      {:not_truncated, :not_truncated} ->
        %{truncated?: false}

      _ ->
        %{
          truncated?: true,
          responsive?: true,
          collapsed_mobile: render_collapsed_or_full(mobile_result, content, preset, assigns),
          collapsed_desktop: render_collapsed_or_full(desktop_result, content, preset, assigns),
          expanded: render_expanded(content, preset, assigns)
        }
    end
  end

  # When one breakpoint doesn't need truncation, render the full content
  # at that breakpoint — no toggle, since there's nothing to expand from.
  defp render_collapsed_or_full({:ok, source}, _content, preset, assigns),
    do: render_collapsed(source, preset, assigns)

  defp render_collapsed_or_full(:not_truncated, content, preset, _assigns),
    do: UserContent.to_html(content, preset: preset)

  defp render_collapsed(source, preset, assigns) do
    source
    |> UserContent.to_html(preset: preset)
    |> append_inline_toggle(
      "... ",
      assigns.read_more_expand_label,
      "read-more",
      "data-readmore-expand"
    )
  end

  defp render_expanded(content, preset, assigns) do
    content
    |> UserContent.to_html(preset: preset)
    |> append_inline_toggle(
      " ",
      assigns.read_more_collapse_label,
      "read-less",
      "data-readmore-collapse"
    )
  end

  defp truncate_markdown(content, limit) when is_integer(limit) and limit > 0 do
    normalized = String.trim(content)

    if String.length(normalized) > limit do
      collapsed =
        normalized
        |> String.slice(0, limit)
        |> truncate_to_word()
        |> String.trim_trailing()

      {:ok, collapsed}
    else
      :not_truncated
    end
  end

  defp truncate_markdown(_content, _limit), do: :not_truncated

  defp truncate_to_word(text) do
    case Regex.run(~r/\A(.+)\s+\S*\z/s, text) do
      [_, prefix] when prefix != "" -> prefix
      _ -> text
    end
  end

  defp append_inline_toggle(html, prefix, label, class, attr) do
    rendered = safe_to_string(html)

    toggle =
      ~s(#{prefix}<button type="button" #{attr} class="#{read_more_toggle_class(class)}">#{label}</button>)

    rendered
    |> append_to_last_paragraph(toggle)
    |> Phoenix.HTML.raw()
  end

  defp append_to_last_paragraph(html, toggle) do
    case :binary.matches(html, "</p>") do
      [] ->
        html <> toggle

      matches ->
        {index, _length} = List.last(matches)

        binary_part(html, 0, index) <>
          toggle <> binary_part(html, index, byte_size(html) - index)
    end
  end

  defp read_more_toggle_class(class) do
    Enum.join(
      [
        class,
        "inline cursor-pointer border-0 bg-transparent p-0 text-inherit font-medium hover:text-[rgb(var(--foreground-primary))] focus-visible:outline-none focus-visible:underline"
      ],
      " "
    )
  end

  # ---------------------------------------------------------------------------
  # Wrapper class per variant
  # ---------------------------------------------------------------------------

  defp wrapper_class("user"), do: "kaguya-markdown"
  defp wrapper_class("comment"), do: "kaguya-markdown"
  defp wrapper_class("bio"), do: nil
  defp wrapper_class("policy"), do: nil
  defp wrapper_class("plain"), do: nil
  # Safety net — never crash a page render just because a new variant
  # name slipped past `values:` validation. Falls back to "no wrapper"
  # which is the most conservative choice; callers can always pass an
  # explicit `:class` if they need typography.
  defp wrapper_class(_other), do: nil

  defp raise_missing_id do
    raise ArgumentError, "`<.markdown read_more>` requires `read_more_id` to be set"
  end
end

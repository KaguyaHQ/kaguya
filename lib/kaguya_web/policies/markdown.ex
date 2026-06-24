defmodule KaguyaWeb.Policies.Markdown do
  @moduledoc """
  Tiny markdown → HTML renderer for static policy pages.

  Mirrors the production `LegalMarkdown.tsx` component
  (`../personal/legacy-next-app/src/components/legal/LegalMarkdown.tsx`):

    * `## Heading` / `### Heading` with the production class set, plus
      the production split for numbered headings ("1. Title" → a
      `.no-underline` number span and a title span).
    * `- item` / `* item` unordered lists.
    * `1. item` ordered lists.
    * `---` horizontal rules.
    * Paragraphs with the production typography.
    * Inline `**bold**`, `*italic*`, `~~strikethrough~~`,
      `` `code` `` and `[label](url)` links (links open in a new tab
      with `noopener noreferrer nofollow`).

  Content is project-owned, not user-supplied, so this is meant to be
  used only for trusted policy markdown. All text is HTML-escaped via
  `Phoenix.HTML.html_escape/1` before emission; only the structural
  tags this module knows about are inserted as raw HTML.

  Returns a `Phoenix.HTML.safe()` tuple suitable for direct rendering
  inside HEEx (e.g. `{KaguyaWeb.Policies.Markdown.to_html(@body)}`).
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  @link_class "text-foreground-link hover:text-text-link-hover underline-offset-2 hover:underline"

  @doc """
  Render policy markdown to a safe HTML iodata tuple.
  """
  def to_html(content) when is_binary(content) do
    html =
      content
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> blocks([])
      |> Enum.reverse()
      |> Enum.map_join("\n", &render_block/1)

    {:safe, html}
  end

  # ---------------------------------------------------------------------------
  # Block parser — folds lines into a reversed list of block tuples.
  # ---------------------------------------------------------------------------

  defp blocks([], acc), do: acc

  defp blocks([line | rest], acc) do
    cond do
      line == "" ->
        blocks(rest, acc)

      line == "---" ->
        blocks(rest, [:hr | acc])

      String.starts_with?(line, "## ") ->
        blocks(rest, [{:h2, String.trim_leading(line, "## ")} | acc])

      String.starts_with?(line, "### ") ->
        blocks(rest, [{:h3, String.trim_leading(line, "### ")} | acc])

      String.starts_with?(line, "# ") ->
        blocks(rest, [{:h1, String.trim_leading(line, "# ")} | acc])

      ul_item?(line) ->
        {items, rest} = collect(rest, &ul_item?/1, [strip_ul(line)], &strip_ul/1)
        blocks(rest, [{:ul, items} | acc])

      ol_item?(line) ->
        {items, rest} = collect(rest, &ol_item?/1, [strip_ol(line)], &strip_ol/1)
        blocks(rest, [{:ol, items} | acc])

      true ->
        {lines, rest} = collect(rest, &paragraph_line?/1, [line], & &1)
        blocks(rest, [{:p, Enum.join(lines, " ")} | acc])
    end
  end

  defp collect([line | rest], pred, acc, normalize) do
    if pred.(line) do
      collect(rest, pred, [normalize.(line) | acc], normalize)
    else
      {Enum.reverse(acc), [line | rest]}
    end
  end

  defp collect([], _pred, acc, _normalize), do: {Enum.reverse(acc), []}

  defp ul_item?(line), do: String.starts_with?(line, "- ") or String.starts_with?(line, "* ")
  defp strip_ul("- " <> rest), do: rest
  defp strip_ul("* " <> rest), do: rest

  defp ol_item?(line), do: Regex.match?(~r/^\d+\.\s+/, line)
  defp strip_ol(line), do: Regex.replace(~r/^\d+\.\s+/, line, "")

  defp paragraph_line?(""), do: false
  defp paragraph_line?("---"), do: false

  defp paragraph_line?(line) do
    not (ul_item?(line) or ol_item?(line) or
           String.starts_with?(line, "## ") or
           String.starts_with?(line, "### ") or
           String.starts_with?(line, "# "))
  end

  # ---------------------------------------------------------------------------
  # Block renderers
  # ---------------------------------------------------------------------------

  defp render_block(:hr), do: ~s(<hr class="my-10 border-t border-border-divider" />)

  defp render_block({:h1, text}) do
    ~s(<h1 class="mt-4 mb-2 text-xl font-semibold text-foreground-primary sm:text-2xl">) <>
      ~s(<span>) <> inline(text) <> ~s(</span></h1>)
  end

  defp render_block({:h2, text}), do: numbered_heading("h2", h2_class(), text)
  defp render_block({:h3, text}), do: numbered_heading("h3", h3_class(), text)

  defp render_block({:ul, items}) do
    lis =
      items
      |> Enum.map_join("", fn item ->
        ~s(<li class="#{li_class()}">) <> inline(item) <> ~s(</li>)
      end)

    ~s(<ul class="mt-2 list-disc space-y-1 pl-4 sm:space-y-2 sm:pl-8">) <> lis <> ~s(</ul>)
  end

  defp render_block({:ol, items}) do
    lis =
      items
      |> Enum.map_join("", fn item ->
        ~s(<li class="#{li_class()}">) <> inline(item) <> ~s(</li>)
      end)

    ~s(<ol class="mt-2 list-decimal space-y-4 pl-4 sm:space-y-5">) <> lis <> ~s(</ol>)
  end

  defp render_block({:p, text}) do
    ~s(<p class="mt-4 text-base leading-7 text-foreground-secondary sm:text-lg">) <>
      inline(text) <> ~s(</p>)
  end

  defp numbered_heading(tag, class, text) do
    case Regex.run(~r/^(\d+)\.\s*(.*)$/, text) do
      [_, number, title] ->
        ~s(<#{tag} class="#{class}">) <>
          ~s(<span class="no-underline">) <>
          escape(number) <>
          ~s(.</span> ) <>
          ~s(<span>) <> inline(title) <> ~s(</span></#{tag}>)

      _ ->
        ~s(<#{tag} class="#{class}"><span>) <> inline(text) <> ~s(</span></#{tag}>)
    end
  end

  defp h2_class,
    do: "mt-10 mb-3 text-xl font-semibold text-foreground-primary sm:mt-12 sm:text-2xl"

  defp h3_class, do: "mt-8 mb-2 text-lg font-semibold text-foreground-primary"

  defp li_class,
    do:
      "ml-2 text-base leading-7 font-normal text-foreground-secondary marker:font-semibold sm:ml-4 sm:text-lg"

  # ---------------------------------------------------------------------------
  # Inline parser — applies bold/italic/strike/code/link transforms over an
  # escaped string. We escape first, then introduce known-safe tags so the
  # tags themselves can't be smuggled in via content.
  # ---------------------------------------------------------------------------

  defp inline(text) when is_binary(text) do
    # Extract code spans first so their contents aren't re-scanned for bold/
    # italic/strike. Replace each with an opaque placeholder, run the other
    # transforms, then swap the rendered <code> tags back in at the end.
    {with_placeholders, codes} = extract_codes(text)

    with_placeholders
    |> escape()
    |> apply_links()
    |> apply_strikethrough()
    |> apply_bold()
    |> apply_italic()
    |> restore_codes(codes)
  end

  defp escape(text), do: text |> html_escape() |> safe_to_string()

  defp extract_codes(text) do
    Regex.scan(~r/`([^`]+)`/, text, capture: :all)
    |> Enum.with_index()
    |> Enum.reduce({text, []}, fn {[full, inner], i}, {acc_text, acc_codes} ->
      placeholder = "\x00CODE#{i}\x00"

      {String.replace(acc_text, full, placeholder, global: false),
       [{placeholder, inner} | acc_codes]}
    end)
    |> then(fn {final_text, codes} -> {final_text, Enum.reverse(codes)} end)
  end

  defp restore_codes(text, codes) do
    Enum.reduce(codes, text, fn {placeholder, inner}, acc ->
      String.replace(acc, placeholder, code_tag(inner))
    end)
  end

  defp code_tag(inner) do
    escaped = escape(inner)

    ~s(<code class="rounded bg-surface-elevated px-1.5 py-0.5 font-mono text-[0.875em] text-foreground-primary">#{escaped}</code>)
  end

  defp apply_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, text, fn _, label, href ->
      safe_href = sanitize_href(href)

      ~s(<a href="#{safe_href}" class="#{@link_class}" target="_blank" rel="noopener noreferrer nofollow">#{label}</a>)
    end)
  end

  defp sanitize_href(href) do
    cond do
      String.starts_with?(href, "https://") -> href
      String.starts_with?(href, "http://") -> href
      String.starts_with?(href, "mailto:") -> href
      String.starts_with?(href, "/") -> href
      String.starts_with?(href, "#") -> href
      true -> "#"
    end
  end

  defp apply_strikethrough(text) do
    Regex.replace(~r/~~([^~]+)~~/, text, fn _, inner ->
      ~s(<del class="line-through">#{inner}</del>)
    end)
  end

  defp apply_bold(text) do
    Regex.replace(~r/\*\*([^*]+)\*\*/, text, fn _, inner ->
      ~s(<strong class="font-semibold">#{inner}</strong>)
    end)
  end

  defp apply_italic(text) do
    Regex.replace(~r/(^|[^*])\*([^*\n]+)\*(?!\*)/, text, fn _, lead, inner ->
      lead <> ~s(<em>#{inner}</em>)
    end)
  end
end

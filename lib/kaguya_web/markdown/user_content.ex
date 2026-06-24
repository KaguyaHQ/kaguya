defmodule KaguyaWeb.Markdown.UserContent do
  @moduledoc """
  Safe markdown renderer for user-authored content.

  Mirrors the Next.js pipeline: CommonMark + GFM via Earmark, then an AST
  transform pass for Discord-style `||spoilers||`, link sanitization +
  VNDB-relative href rewriting, and a tag allowlist that matches the
  `ALLOWED_TAGS` set used by DOMPurify on the Next.js side.

  Output is bare semantic HTML — styling (paragraph spacing, blockquote
  borders, etc.) lives in the caller's `.kaguya-markdown` container, not
  here.
  """

  @link_class "text-foreground-link no-underline hover:underline"
  @vndb_relative_pattern ~r{^/[a-z]\d+(?:[#?/.].*)?$}i

  # Matches the Next.js DOMPurify allowlist in `src/utils/readMoreUtils.tsx`.
  @default_allowed_tags ~w(p br strong b em i del a span blockquote ul ol li pre code)
  @comment_allowed_tags @default_allowed_tags
  # Matches `BioContent.tsx` exactly — no anchors, no lists/code/blockquotes,
  # no `<b>`/`<i>`/`<span>` (the wider set the comment preset allows).
  @bio_allowed_tags ~w(p br strong em del)

  # Presets bundle an allowlist with a preprocess fn so callers pick one name
  # instead of wiring both. Mirrors the Next.js render configs:
  # - :default  / :comment → CommentContent.tsx + DescriptionReadMore (full block markdown)
  # - :bio                  → BioContent.tsx (no links, no lists, escaped numbered prefixes)
  @presets %{
    default: {@default_allowed_tags, :identity},
    comment: {@comment_allowed_tags, :comment_preprocess},
    bio: {@bio_allowed_tags, :bio_preprocess}
  }

  # Private-Use Area sentinels — chosen because Earmark/CommonMark won't
  # treat them as syntactically meaningful, so we can stash spoilers in
  # the source string and reliably find them in the parsed AST.
  @spoiler_open <<0xE000::utf8>>
  @spoiler_close <<0xE001::utf8>>
  @spoiler_escape <<0xE002::utf8>>

  def to_html(content), do: to_html(content, [])

  def to_html(content, _opts) when not is_binary(content), do: {:safe, ""}
  def to_html("", _opts), do: {:safe, ""}

  def to_html(content, opts) do
    preset = Keyword.get(opts, :preset, :default)
    {preset_tags, preset_pre} = Map.get(@presets, preset, Map.fetch!(@presets, :default))

    allowed = Keyword.get(opts, :allowed_tags, preset_tags) |> MapSet.new()
    preprocess = Keyword.get(opts, :preprocess, preset_pre)

    content = apply_preprocess(content, preprocess)
    {source, spoilers} = stash_spoilers(content)

    case Earmark.as_ast(source, gfm: true, breaks: true, smartypants: false) do
      {result, ast, _messages} when result in [:ok, :error] ->
        html =
          ast
          |> walk(spoilers)
          |> filter(allowed)
          |> Earmark.Transform.transform()
          |> String.replace(@spoiler_escape, "||")

        {:safe, html}

      _ ->
        {:safe, ""}
    end
  end

  # ---------------------------------------------------------------------------
  # Spoiler stash — runs over the source string before Earmark parses, so
  # spoilers can wrap markdown that gets parsed normally inside.
  # ---------------------------------------------------------------------------

  defp stash_spoilers(content) do
    # `\||` is the documented escape for a literal `||` — swap to a
    # sentinel that survives Earmark and gets restored at the end.
    content = String.replace(content, "\\||", @spoiler_escape)

    {final, inners, _idx} =
      Regex.scan(~r/\|\|([\s\S]+?)\|\|/, content, capture: :all)
      |> Enum.reduce({content, %{}, 0}, fn [full, inner], {acc, inners, idx} ->
        placeholder = @spoiler_open <> Integer.to_string(idx) <> @spoiler_close

        {String.replace(acc, full, placeholder, global: false), Map.put(inners, idx, inner),
         idx + 1}
      end)

    {final, inners}
  end

  # ---------------------------------------------------------------------------
  # AST walk — inflate spoiler placeholders + sanitize anchors. Code spans
  # and code blocks are left literal so their contents aren't touched.
  # ---------------------------------------------------------------------------

  defp walk(ast, spoilers) when is_list(ast),
    do: Enum.flat_map(ast, &walk_node(&1, spoilers))

  defp walk_node(text, spoilers) when is_binary(text), do: inflate_spoilers(text, spoilers)

  defp walk_node({"code", _, _, _} = node, _spoilers), do: [node]
  defp walk_node({"pre", _, _, _} = node, _spoilers), do: [node]

  defp walk_node({"a", attrs, children, meta}, spoilers) do
    href =
      attrs
      |> List.keyfind("href", 0, {"href", ""})
      |> elem(1)
      |> sanitize_href()

    new_attrs = [
      {"href", href},
      {"class", @link_class},
      {"target", "_blank"},
      {"rel", "noopener noreferrer nofollow"}
    ]

    [{"a", new_attrs, walk(children, spoilers), meta}]
  end

  defp walk_node({tag, attrs, children, meta}, spoilers),
    do: [{tag, attrs, walk(children, spoilers), meta}]

  # ---------------------------------------------------------------------------
  # Spoiler inflation — split text on `IDX`, render each
  # stashed inner as inline markdown, and wrap in a spoiler span.
  # ---------------------------------------------------------------------------

  defp inflate_spoilers(text, spoilers) do
    case Regex.split(~r/\x{E000}(\d+)\x{E001}/u, text, include_captures: true) do
      [^text] ->
        [text]

      parts ->
        parts
        |> Enum.flat_map(fn chunk ->
          case Regex.run(~r/^\x{E000}(\d+)\x{E001}$/u, chunk) do
            [_, idx_str] ->
              idx = String.to_integer(idx_str)
              inner_md = Map.get(spoilers, idx, "")
              [spoiler_node(render_inline(inner_md, spoilers))]

            _ ->
              if chunk == "", do: [], else: [chunk]
          end
        end)
    end
  end

  # Render a spoiler's inner content as inline markdown — parse with
  # Earmark, then unwrap the surrounding `<p>` so the children land
  # inside the spoiler span without producing a block.
  defp render_inline(text, spoilers) do
    case Earmark.as_ast(text, gfm: true, breaks: false, smartypants: false) do
      {result, [{"p", _, children, _}], _} when result in [:ok, :error] ->
        walk(children, spoilers)

      {result, ast, _} when result in [:ok, :error] ->
        walk(ast, spoilers)

      _ ->
        [text]
    end
  end

  defp spoiler_node(children) do
    {"span",
     [
       {"data-spoiler", ""},
       {"class", "spoiler"},
       {"role", "button"},
       {"tabindex", "0"},
       {"aria-label", "Spoiler, click to reveal"},
       {"aria-hidden", "true"}
     ], children, %{}}
  end

  # ---------------------------------------------------------------------------
  # Allowlist filter — disallowed wrappers drop, children bubble up
  # (matches DOMPurify's KEEP_CONTENT=true default on the Next.js side).
  # ---------------------------------------------------------------------------

  defp filter(ast, allowed) when is_list(ast), do: Enum.flat_map(ast, &filter_node(&1, allowed))

  defp filter_node(text, _allowed) when is_binary(text), do: [text]

  defp filter_node({tag, attrs, children, meta}, allowed) do
    filtered_children = filter(children, allowed)

    if MapSet.member?(allowed, tag) do
      [{tag, attrs, filtered_children, meta}]
    else
      filtered_children
    end
  end

  # ---------------------------------------------------------------------------
  # Href sanitization
  # ---------------------------------------------------------------------------

  defp sanitize_href(href) do
    href = href |> String.trim() |> normalize_href()
    if safe_href?(href), do: href, else: "#"
  end

  defp normalize_href("/" <> _rest = href) do
    if Regex.match?(@vndb_relative_pattern, href),
      do: "https://vndb.org" <> href,
      else: href
  end

  defp normalize_href(href), do: href

  defp safe_href?("https://" <> rest), do: rest != ""
  defp safe_href?("http://" <> rest), do: rest != ""
  defp safe_href?("/" <> rest), do: rest != "" and not String.starts_with?(rest, "/")
  defp safe_href?(_), do: false

  # ---------------------------------------------------------------------------
  # Preprocess presets — applied to the raw markdown source before spoiler
  # stashing + Earmark. Public so tests + future surfaces can reuse them
  # directly; the `:preprocess` opt also accepts an arbitrary 1-arity fn.
  # ---------------------------------------------------------------------------

  defp apply_preprocess(content, :identity), do: content
  defp apply_preprocess(content, :comment_preprocess), do: comment_preprocess(content)
  defp apply_preprocess(content, :bio_preprocess), do: bio_preprocess(content)
  defp apply_preprocess(content, fun) when is_function(fun, 1), do: fun.(content)
  defp apply_preprocess(content, _), do: content

  @doc """
  Comment preprocessing — mirrors `CommentContent.tsx` lines 16–26.

  - Drop lone-backslash lines (a Discord quirk where users add `\\` to force
    a newline).
  - Convert escaped trailing newlines (`\\\n`) to plain newlines.
  - Pad runs of blank lines with NBSP so they render as `<br>` spacing
    instead of paragraph breaks (preserves visual rhythm in tight comment
    typography).
  """
  def comment_preprocess(content) when is_binary(content) do
    content
    |> normalize_newlines()
    |> drop_lone_backslash_lines()
    |> unescape_trailing_newlines()
    |> pad_blank_lines()
  end

  @doc """
  Bio preprocessing — mirrors `BioContent.tsx` lines 11–18.

  Stricter than comments: link syntax is stripped to plain text (the bio
  surface doesn't render `<a>`) and numbered-list prefixes are escaped so
  users can write `1. foo` without it rendering as an `<ol>`.
  """
  def bio_preprocess(content) when is_binary(content) do
    content
    |> normalize_newlines()
    |> drop_lone_backslash_lines()
    |> unescape_trailing_newlines()
    |> strip_link_syntax()
    |> escape_numbered_list_prefix()
    |> pad_blank_lines()
  end

  defp normalize_newlines(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  defp drop_lone_backslash_lines(content),
    do: String.replace(content, ~r/^[ \t]*\\[ \t]*$/m, "")

  defp unescape_trailing_newlines(content), do: String.replace(content, "\\\n", "\n")

  # Replace runs of 2+ consecutive newlines with `\n\xA0\n…\n`, putting an
  # NBSP on every "blank" line so Earmark (with breaks: true) renders them as
  # soft breaks inside one paragraph rather than splitting into multiple.
  defp pad_blank_lines(content) do
    Regex.replace(~r/(?:[ \t]*\n){2,}/, content, fn match ->
      newline_count = match |> :binary.matches("\n") |> length()
      String.duplicate("\n ", newline_count - 1) <> "\n"
    end)
  end

  defp strip_link_syntax(content),
    do: Regex.replace(~r/\[([^\]]+)\]\([^\)]+\)/, content, "\\1")

  defp escape_numbered_list_prefix(content),
    do: Regex.replace(~r/^(\d+)\. /m, content, "\\1\\\\. ")
end

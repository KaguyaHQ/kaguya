defmodule VndbToMarkdown do
  @moduledoc """
  Converts VNDB BBCode text to Markdown.

  Used for all VNDB-sourced content: descriptions, release notes, and reviews.
  Pure string transformation — no HTML intermediary, no DOM parsing.
  """

  @doc """
  Converts VNDB BBCode text to Markdown.
  """
  def convert(nil), do: ""
  def convert(""), do: ""
  def convert(text), do: convert(text, %{})

  @doc """
  Converts VNDB BBCode text to Markdown with vn_link_map for VN ID linking.
  vn_link_map: %{"25288" => %{slug: "being-a-dik", title: "Being a DIK"}, ...}
  """
  def convert(nil, _vn_link_map), do: ""
  def convert("", _vn_link_map), do: ""

  def convert(text, vn_link_map) when is_binary(text) do
    text
    |> String.trim()
    |> normalize_newlines()
    |> maybe_fast_path(vn_link_map)
  end

  # ---------------------------------------------------------------------------
  # Fast path
  # ---------------------------------------------------------------------------

  # Pattern to match VNDB VN IDs (v123 or v123.4)
  @vn_id_pattern ~r/\bv(\d+)(?:\.\d+)?\b/

  defp maybe_fast_path(text, vn_link_map) do
    if needs_conversion?(text, vn_link_map) do
      do_convert(text, vn_link_map)
    else
      text
    end
  end

  defp needs_conversion?(text, vn_link_map) do
    String.contains?(text, "[") or
      String.contains?(text, "http") or
      (map_size(vn_link_map) > 0 and Regex.match?(@vn_id_pattern, text))
  end

  # ---------------------------------------------------------------------------
  # Main conversion pipeline
  # ---------------------------------------------------------------------------

  defp do_convert(text, vn_link_map) do
    text
    |> fix_malformed_url_tags()
    |> handle_raw_tags()
    |> convert_vn_ids(vn_link_map)
    |> convert_bare_urls()
    |> convert_bbcode_tags()
    |> clean_up()
  end

  # Fix [url=href[/url] where [/url] leaked into the href attribute — emit bare URL
  defp fix_malformed_url_tags(text) do
    String.replace(text, ~r/\[url=([^\]\[]*?)\[\/url\]/i, "\\1")
  end

  # ---------------------------------------------------------------------------
  # Preprocessing
  # ---------------------------------------------------------------------------

  defp normalize_newlines(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  # ---------------------------------------------------------------------------
  # [raw] tags — escape markdown special chars so content is rendered literally
  # ---------------------------------------------------------------------------

  # Characters that have meaning in markdown and need escaping
  # Backslash MUST be first so we don't re-escape backslashes added by later replacements
  @markdown_special_chars ["\\", "*", "_", "[", "]", "(", ")", "|", "`", ">", "#", "~"]

  defp handle_raw_tags(text) do
    Regex.replace(~r/\[raw\](.*?)\[\/raw\]/is, text, fn _, content ->
      escape_markdown(content)
    end)
  end

  @doc false
  def escape_markdown(text) do
    Enum.reduce(@markdown_special_chars, text, fn char, acc ->
      String.replace(acc, char, "\\#{char}")
    end)
  end

  # ---------------------------------------------------------------------------
  # VN ID linking
  # ---------------------------------------------------------------------------

  defp convert_vn_ids(text, vn_link_map) when map_size(vn_link_map) == 0, do: text

  defp convert_vn_ids(text, vn_link_map) do
    if Regex.match?(@vn_id_pattern, text) do
      Regex.replace(@vn_id_pattern, text, fn match, id ->
        case Map.get(vn_link_map, id) do
          nil -> match
          %{slug: slug, title: title} -> "[#{title}](/vn/#{slug})"
        end
      end)
    else
      text
    end
  end

  # ---------------------------------------------------------------------------
  # Bare URL conversion
  # ---------------------------------------------------------------------------

  # Match bare URLs not already inside [url] tags
  @bare_url_pattern ~r/(?<!\[url=)(?<!\[url\])(?<!")(https?:\/\/[^\s\[\]<>"]+)/

  defp convert_bare_urls(text) do
    if String.contains?(text, "http") do
      Regex.replace(@bare_url_pattern, text, fn _full, url ->
        {clean_url, trailing} = clean_url_trailing_chars(url)
        clean_url <> trailing
      end)
    else
      text
    end
  end

  # Strip trailing punctuation that's likely not part of the URL
  defp clean_url_trailing_chars(url) do
    open_parens = url |> String.graphemes() |> Enum.count(&(&1 == "("))
    close_parens = url |> String.graphemes() |> Enum.count(&(&1 == ")"))

    {url, ""}
    |> maybe_strip_trailing_parens(close_parens - open_parens)
    |> maybe_strip_trailing_char(".")
    |> maybe_strip_trailing_char(",")
    |> maybe_strip_trailing_char(";")
    |> maybe_strip_trailing_char(":")
  end

  defp maybe_strip_trailing_parens({url, trailing}, excess) when excess > 0 do
    if String.ends_with?(url, ")") do
      maybe_strip_trailing_parens({String.slice(url, 0..-2//1), ")" <> trailing}, excess - 1)
    else
      {url, trailing}
    end
  end

  defp maybe_strip_trailing_parens(acc, _), do: acc

  defp maybe_strip_trailing_char({url, trailing}, char) do
    if String.ends_with?(url, char) do
      {String.slice(url, 0..-2//1), char <> trailing}
    else
      {url, trailing}
    end
  end

  # ---------------------------------------------------------------------------
  # BBCode → Markdown
  # ---------------------------------------------------------------------------

  defp convert_bbcode_tags(text) do
    text
    # Block-level: quote (must come before inline to handle multiline)
    |> convert_quotes()
    # Block-level: code
    |> convert_code()
    # Inline/block: spoiler
    |> convert_spoilers()
    # Inline formatting
    |> convert_inline(:bold)
    |> convert_inline(:italic)
    |> convert_inline(:underline)
    |> convert_inline(:strikethrough)
    # Links
    |> convert_url_with_text()
    |> convert_url_bare()
  end

  # --- [quote] -> > prefixed lines ---

  defp convert_quotes(text) do
    Regex.replace(~r/\[quote\](.*?)\[\/quote\]/is, text, fn _, content ->
      content
      |> String.trim()
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> "> #{line}" end)
    end)
  end

  # --- [code] -> ` or ``` ---

  defp convert_code(text) do
    Regex.replace(~r/\[code\](.*?)\[\/code\]/is, text, fn _, content ->
      if String.contains?(content, "\n") do
        "```\n#{content}\n```"
      else
        "`#{content}`"
      end
    end)
  end

  # --- [spoiler] -> || ---

  defp convert_spoilers(text) do
    # Proper close: [spoiler]...[/spoiler]
    text =
      Regex.replace(~r/\[spoiler\](.*?)\[\/spoiler\]/is, text, fn _, content ->
        "||#{content}||"
      end)

    # Fallback: [spoiler]...[spoiler] (opening tag reused as closing tag)
    text =
      Regex.replace(~r/\[spoiler\](.*?)\[spoiler\]/is, text, fn _, content ->
        "||#{content}||"
      end)

    # Unclosed [spoiler] (truncated description) — rest of text is spoiler
    Regex.replace(~r/\[spoiler\](.*)\z/is, text, fn _, content ->
      "||#{content}||"
    end)
  end

  # --- Inline formatting ---

  defp convert_inline(text, :bold) do
    text
    |> String.replace(~r/\[b\](.*?)\[\/b\]/is, "**\\1**")
    |> String.replace(~r/\[b\](.*)\z/is, "**\\1**")
  end

  defp convert_inline(text, :italic) do
    text
    |> String.replace(~r/\[i\](.*?)\[\/i\]/is, "*\\1*")
    |> String.replace(~r/\[i\](.*)\z/is, "*\\1*")
  end

  defp convert_inline(text, :underline) do
    # No markdown equivalent for underline — just drop the tags
    text
    |> String.replace(~r/\[u\](.*?)\[\/u\]/is, "\\1")
    |> String.replace(~r/\[u\](.*)\z/is, "\\1")
  end

  defp convert_inline(text, :strikethrough) do
    text
    |> String.replace(~r/\[s\](.*?)\[\/s\]/is, "~~\\1~~")
    |> String.replace(~r/\[s\](.*)\z/is, "~~\\1~~")
  end

  # --- [url=href]text[/url] -> [text](href) ---

  defp convert_url_with_text(text) do
    text
    |> String.replace(~r/\[url=([^\]]+)\](.*?)\[\/url\]/is, "[\\2](\\1)")
    # Malformed: [url=href]text[url] (opening tag reused as closing)
    |> String.replace(~r/\[url=([^\]]+)\](.*?)\[url\]/is, "[\\2](\\1)")
    # Unclosed: [url=href]text (rest of text is link text)
    |> String.replace(~r/\[url=([^\]]+)\](.*)\z/is, "[\\2](\\1)")
  end

  # --- [url]href[/url] -> bare href ---

  defp convert_url_bare(text) do
    String.replace(text, ~r/\[url\](.*?)\[\/url\]/is, "\\1")
  end

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  defp clean_up(text) do
    text
    |> String.replace(~r/[ \t]+$/m, "")
  end
end

defmodule Kaguya.Releases.ReleaseTitleHelper do
  @moduledoc """
  Computes a display title for VN releases by stripping redundant VN name prefixes.

  Accepts a list of all known VN title variants (across languages). For each variant,
  both the full title and "base" (before ` ~` / ` -` / `: ` separators) are tried.
  Longest match wins, case-insensitive.

  If exact matching fails, a space-collapsed fallback is tried to catch spelling
  variants like "Fatamorgana" vs "Fata Morgana".

  After stripping, leading separator characters are cleaned. Characters that open
  meaningful content groups (`(`, `[`, `"`, `'`, `<`, `#`) are preserved.
  If the result is empty or has no letters/digits, the original release title is returned.
  """

  @doc """
  Compute display title given a release title and a list of all known VN title variants.
  """
  def compute_display_title(release_title, vn_title_variants) when is_list(vn_title_variants) do
    prefixes = build_prefixes(vn_title_variants)

    # Try exact prefix matching first
    result =
      Enum.find_value(prefixes, fn prefix ->
        try_strip_prefix(release_title, prefix)
      end)

    # Fallback: try space-collapsed matching for spelling variants
    result =
      if is_nil(result) do
        try_spaceless_match(release_title, prefixes)
      else
        result
      end

    case result do
      nil -> release_title
      "" -> release_title
      suffix -> if has_word_chars?(suffix), do: suffix, else: release_title
    end
  end

  @doc """
  Convenience form: compute display title from a VN's primary title and Japanese latin.
  """
  def compute_display_title(release_title, vn_title, vn_latin_title) do
    variants = [vn_title, vn_latin_title] |> Enum.reject(&is_nil/1)
    compute_display_title(release_title, variants)
  end

  # Build prefix candidates sorted longest-first
  defp build_prefixes(title_variants) do
    title_variants
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn title -> [title | extract_bases(title)] end)
    |> Enum.uniq()
    |> Enum.sort_by(&String.length/1, :desc)
  end

  # Extract "base title" before common VN separators
  defp extract_bases(title) do
    [" ~", " -", ": "]
    |> Enum.flat_map(fn sep ->
      case String.split(title, sep, parts: 2) do
        [base, _] when byte_size(base) >= 5 -> [String.trim(base)]
        _ -> []
      end
    end)
  end

  defp try_strip_prefix(release_title, prefix) do
    prefix_len = String.length(prefix)

    if String.downcase(String.slice(release_title, 0, prefix_len)) == String.downcase(prefix) do
      release_title
      |> String.slice(prefix_len..-1//1)
      |> clean_stripped_suffix()
    end
  end

  # Try matching with spaces removed from both sides.
  # Walk the original release title to find the cut point where the
  # space-collapsed prefix ends, then strip from there.
  defp try_spaceless_match(release_title, prefixes) do
    collapsed_release = release_title |> String.downcase() |> String.replace(" ", "")

    Enum.find_value(prefixes, fn prefix ->
      collapsed_prefix = prefix |> String.downcase() |> String.replace(" ", "")
      prefix_len = String.length(collapsed_prefix)

      if prefix_len > 0 and
           String.slice(collapsed_release, 0, prefix_len) == collapsed_prefix do
        # Find the cut point in the original string: walk characters, skip spaces
        cut_pos = find_cut_position(release_title, prefix_len)

        release_title
        |> String.slice(cut_pos..-1//1)
        |> clean_stripped_suffix()
      end
    end)
  end

  # Walk the original string counting non-space characters until we've consumed
  # `target_non_space` of them, returning the byte position to cut at.
  defp find_cut_position(string, target_non_space) do
    string
    |> String.graphemes()
    |> Enum.reduce_while({0, 0}, fn char, {pos, count} ->
      if count >= target_non_space do
        {:halt, {pos, count}}
      else
        new_count = if char == " ", do: count, else: count + 1
        {:cont, {pos + 1, new_count}}
      end
    end)
    |> elem(0)
  end

  defp clean_stripped_suffix(string) do
    string
    |> String.replace(~r/\A[^\p{L}\p{N}(\["'<#]+/u, "")
    |> unwrap_leading_brackets()
    |> String.trim()
  end

  # Unwrap leading [subtitle] or (edition) → content without brackets/parens
  # e.g. "[Realta Nua] - Ultimate Edition" → "Realta Nua - Ultimate Edition"
  #      "(Demo)" → "Demo"
  defp unwrap_leading_brackets(string) do
    string
    |> String.replace(~r/\A\[([^\]]+)\]/, "\\1")
    |> String.replace(~r/\A\(([^\)]+)\)/, "\\1")
  end

  defp has_word_chars?(string), do: String.match?(string, ~r/[\p{L}\p{N}]/u)
end

defmodule VndbToMarkdownTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Empty / nil input
  # ---------------------------------------------------------------------------

  describe "convert/1 with nil or empty input" do
    test "nil returns empty string" do
      assert VndbToMarkdown.convert(nil) == ""
    end

    test "empty string returns empty string" do
      assert VndbToMarkdown.convert("") == ""
    end
  end

  describe "convert/2 with nil or empty input" do
    test "nil returns empty string" do
      assert VndbToMarkdown.convert(nil, %{}) == ""
    end

    test "empty string returns empty string" do
      assert VndbToMarkdown.convert("", %{}) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # Plain text (fast path)
  # ---------------------------------------------------------------------------

  describe "plain text (fast path)" do
    test "plain text passes through unchanged" do
      assert VndbToMarkdown.convert("Hello world") == "Hello world"
    end

    test "multiline plain text passes through unchanged" do
      input = "First line\nSecond line\n\nThird paragraph"
      assert VndbToMarkdown.convert(input) == input
    end

    test "text with no BBCode, URLs, or VN IDs skips conversion" do
      input = "This is just a regular review with no special formatting."
      assert VndbToMarkdown.convert(input) == input
    end
  end

  # ---------------------------------------------------------------------------
  # Individual BBCode tags
  # ---------------------------------------------------------------------------

  describe "[b] bold" do
    test "converts to markdown bold" do
      assert VndbToMarkdown.convert("[b]bold text[/b]") == "**bold text**"
    end

    test "case insensitive" do
      assert VndbToMarkdown.convert("[B]bold[/B]") == "**bold**"
    end
  end

  describe "[i] italic" do
    test "converts to markdown italic" do
      assert VndbToMarkdown.convert("[i]italic text[/i]") == "*italic text*"
    end
  end

  describe "[u] underline" do
    test "drops underline tags (no markdown equivalent)" do
      assert VndbToMarkdown.convert("[u]underlined[/u]") == "underlined"
    end
  end

  describe "[s] strikethrough" do
    test "converts to markdown strikethrough" do
      assert VndbToMarkdown.convert("[s]deleted[/s]") == "~~deleted~~"
    end
  end

  describe "[url] links" do
    test "url with display text" do
      input = "[url=https://example.com]Example[/url]"
      assert VndbToMarkdown.convert(input) == "[Example](https://example.com)"
    end

    test "url without display text (bare)" do
      input = "[url]https://example.com[/url]"
      assert VndbToMarkdown.convert(input) == "https://example.com"
    end

    test "url with path" do
      input = "[url=https://example.com/path/to/page]Click here[/url]"
      assert VndbToMarkdown.convert(input) == "[Click here](https://example.com/path/to/page)"
    end
  end

  describe "[spoiler]" do
    test "inline spoiler" do
      assert VndbToMarkdown.convert("[spoiler]secret[/spoiler]") == "||secret||"
    end

    test "multiline spoiler" do
      input = "[spoiler]line one\nline two[/spoiler]"
      assert VndbToMarkdown.convert(input) == "||line one\nline two||"
    end
  end

  describe "[quote]" do
    test "single line quote" do
      assert VndbToMarkdown.convert("[quote]quoted text[/quote]") == "> quoted text"
    end

    test "multiline quote prefixes each line" do
      input = "[quote]line one\nline two\nline three[/quote]"
      expected = "> line one\n> line two\n> line three"
      assert VndbToMarkdown.convert(input) == expected
    end
  end

  describe "[code]" do
    test "inline code (no newlines)" do
      assert VndbToMarkdown.convert("[code]some_function()[/code]") == "`some_function()`"
    end

    test "multiline code uses fenced code block" do
      input = "[code]line 1\nline 2[/code]"
      expected = "```\nline 1\nline 2\n```"
      assert VndbToMarkdown.convert(input) == expected
    end
  end

  describe "[raw]" do
    test "escapes markdown special characters" do
      input = "[raw]**not bold** and *not italic*[/raw]"
      expected = "\\*\\*not bold\\*\\* and \\*not italic\\*"
      assert VndbToMarkdown.convert(input) == expected
    end

    test "escapes brackets and pipes" do
      input = "[raw][link](url) and ||spoiler||[/raw]"
      expected = "\\[link\\]\\(url\\) and \\|\\|spoiler\\|\\|"
      assert VndbToMarkdown.convert(input) == expected
    end

    test "escapes backticks and angle brackets" do
      input = "[raw]`code` and > quote and # heading[/raw]"
      expected = "\\`code\\` and \\> quote and \\# heading"
      assert VndbToMarkdown.convert(input) == expected
    end

    test "raw content is not processed as BBCode" do
      input = "[raw][b]not bold[/b][/raw]"
      # The [ and ] inside raw are escaped, so [b] becomes \[b\]
      # The BBCode converter won't match the escaped tags
      expected = "\\[b\\]not bold\\[/b\\]"
      assert VndbToMarkdown.convert(input) == expected
    end
  end

  # ---------------------------------------------------------------------------
  # Nested tags
  # ---------------------------------------------------------------------------

  describe "nested tags" do
    test "bold + italic" do
      input = "[b][i]bold italic[/i][/b]"
      assert VndbToMarkdown.convert(input) == "***bold italic***"
    end

    test "italic inside bold text" do
      input = "[b]bold and [i]also italic[/i] text[/b]"
      assert VndbToMarkdown.convert(input) == "**bold and *also italic* text**"
    end

    test "bold + strikethrough" do
      input = "[b][s]bold strike[/s][/b]"
      assert VndbToMarkdown.convert(input) == "**~~bold strike~~**"
    end

    test "spoiler with bold inside" do
      input = "[spoiler][b]bold spoiler[/b][/spoiler]"
      assert VndbToMarkdown.convert(input) == "||**bold spoiler**||"
    end
  end

  # ---------------------------------------------------------------------------
  # VN ID linking
  # ---------------------------------------------------------------------------

  describe "VN ID linking" do
    @vn_link_map %{
      "25288" => %{slug: "being-a-dik", title: "Being a DIK"},
      "7771" => %{slug: "steins-gate", title: "Steins;Gate"}
    }

    test "converts VN ID to markdown link when in map" do
      result = VndbToMarkdown.convert("Check out v25288 for a great VN", @vn_link_map)
      assert result == "Check out [Being a DIK](/vn/being-a-dik) for a great VN"
    end

    test "converts VN ID with suffix (sub-item)" do
      result = VndbToMarkdown.convert("v25288.3 is interesting", @vn_link_map)
      assert result == "[Being a DIK](/vn/being-a-dik) is interesting"
    end

    test "leaves VN ID as-is when not in map" do
      result = VndbToMarkdown.convert("Also try v99999", @vn_link_map)
      assert result == "Also try v99999"
    end

    test "handles multiple VN IDs in same text" do
      input = "Both v25288 and v7771 are classics"
      result = VndbToMarkdown.convert(input, @vn_link_map)

      assert result ==
               "Both [Being a DIK](/vn/being-a-dik) and [Steins;Gate](/vn/steins-gate) are classics"
    end

    test "empty vn_link_map leaves VN IDs as plain text" do
      result = VndbToMarkdown.convert("Check out v25288", %{})
      assert result == "Check out v25288"
    end
  end

  # ---------------------------------------------------------------------------
  # Bare URL conversion
  # ---------------------------------------------------------------------------

  describe "bare URL conversion" do
    test "bare URL is preserved as-is" do
      input = "Visit https://example.com for more"
      result = VndbToMarkdown.convert(input)
      assert result == "Visit https://example.com for more"
    end

    test "strips trailing period from URL" do
      input = "Visit https://example.com."
      result = VndbToMarkdown.convert(input)
      assert result == "Visit https://example.com."
    end

    test "strips unbalanced trailing parenthesis" do
      input = "(see https://example.com/path)"
      result = VndbToMarkdown.convert(input)
      # The URL captured is "https://example.com/path)" with one ) and zero (
      # So the trailing ) is stripped
      assert result == "(see https://example.com/path)"
    end

    test "preserves balanced parentheses in URL" do
      input = "https://en.wikipedia.org/wiki/Title_(disambiguation)"
      result = VndbToMarkdown.convert(input)
      assert result == "https://en.wikipedia.org/wiki/Title_(disambiguation)"
    end

    test "http URL also works" do
      input = "Visit http://example.com"
      result = VndbToMarkdown.convert(input)
      assert result == "Visit http://example.com"
    end

    test "URL already inside [url] tag is not double-processed" do
      input = "[url=https://example.com]Example[/url]"
      result = VndbToMarkdown.convert(input)
      # Should become a markdown link, not double-wrapped
      assert result == "[Example](https://example.com)"
    end
  end

  # ---------------------------------------------------------------------------
  # Mixed content
  # ---------------------------------------------------------------------------

  describe "mixed content" do
    test "multiple tags in one text" do
      input = "[b]Bold[/b] and [i]italic[/i] with a [url=https://example.com]link[/url]"

      expected =
        "**Bold** and *italic* with a [link](https://example.com)"

      assert VndbToMarkdown.convert(input) == expected
    end

    test "VN IDs mixed with BBCode" do
      vn_link_map = %{"25288" => %{slug: "being-a-dik", title: "Being a DIK"}}
      input = "[b]Review of v25288[/b]\n\nThis VN is [i]amazing[/i]."
      result = VndbToMarkdown.convert(input, vn_link_map)

      expected =
        "**Review of [Being a DIK](/vn/being-a-dik)**\n\nThis VN is *amazing*."

      assert result == expected
    end

    test "real-world-ish review snippet" do
      vn_link_map = %{"17" => %{slug: "ever17", title: "Ever17"}}

      input =
        "[b]A Classic[/b]\n\nI recently replayed v17 and [i]it still holds up[/i]. The [spoiler]twist at the end[/spoiler] is incredible.\n\n[quote]Best VN ever made[/quote]\n\nHighly recommended. See https://example.com/review for my full thoughts."

      result = VndbToMarkdown.convert(input, vn_link_map)

      assert result =~ "**A Classic**"
      assert result =~ "[Ever17](/vn/ever17)"
      assert result =~ "*it still holds up*"
      assert result =~ "||twist at the end||"
      assert result =~ "> Best VN ever made"
      assert result =~ "https://example.com/review"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "newline normalization (CRLF to LF)" do
      input = "[b]bold[/b]\r\nline two"
      result = VndbToMarkdown.convert(input)
      assert result == "**bold**\nline two"
    end

    test "trailing whitespace is cleaned up" do
      input = "[b]bold[/b]   \nline two  "
      result = VndbToMarkdown.convert(input)
      assert result == "**bold**\nline two"
    end

    test "whitespace-only input is trimmed to empty" do
      assert VndbToMarkdown.convert("   ") == ""
    end

    test "text with brackets but no valid BBCode passes through" do
      input = "array[0] = value"
      result = VndbToMarkdown.convert(input)
      # Contains "[" so it goes through conversion pipeline, but no BBCode matches
      assert result == "array[0] = value"
    end
  end
end

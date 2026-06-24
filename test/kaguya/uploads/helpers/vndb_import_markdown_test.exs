defmodule VndbImportMarkdownTest do
  @moduledoc """
  Tests for the VNDB import flow with markdown output.

  Verifies that VndbToMarkdown produces correct markdown for real-world
  VNDB BBCode patterns.
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Realistic VNDB review content (based on actual imports)
  # ---------------------------------------------------------------------------

  describe "realistic VNDB review: Being a DIK style" do
    @vn_link_map %{
      "25288" => %{slug: "being-a-dik", title: "Being a DIK"},
      "7771" => %{slug: "steins-gate", title: "Steins;Gate"},
      "44476" => %{slug: "errant-heart", title: "Errant Heart"}
    }

    @being_a_dik_review """
    i remember every character. the soundtrack is one of the best i've heard.

    i've replayed it multiple times. [b]being a dik[/b] has complete awesome humor. like in a dnd game you play with friends, you get to choose [b]"spank sally"[/b] as an option in the most ridiculous time when you're fighting monsters and it is so funny. the dialogue is like:

    [quote]""[i]well, what else am i gonna do sally, i'm useless as a bard in this game[/i]""[/quote]

    and sally just glares at you.

    you meet maya, your roommate, she seems like a normal film girl into feminism. you meet derek who is just naked anywhere for no reason but [spoiler]surprisingly as you get more into the story, you learn maya's his sister, he cares for her so deeply the only reason he came to college is to be near her.[/spoiler]

    you see sage who's the sorority leader and she comes across as the bimbo slut and then [spoiler]as you go on her route, you learn she's an orphan, she has a trouble speaking about her feelings, it literally makes her so uncomfortable to go on a date with you even though you both have sex on a dime everyday, and likes you a lot. it takes so long when she finally says "i love you" after 50 hours, it feels like the world.[/spoiler]

    we see chad, the meathead jock, bullying the MC first. but then later [spoiler]we learn he's gay and was being blackmailed to out him and his frat would push him out if they learned.[/spoiler]

    i remember the MC saying something like [i]"my dad always says follow your heart. that's the best way to make a decision. somehow your heart already knows what's right for you."[/i] and you're given an option of [spoiler]choosing to have a throuple with maya and josy even though society wouldn't understand[/spoiler] or to remain as friends. it's stuck with me so far.

    there's all these complex characters that I don't really see that often.

    you see, the [s]~~American-pie ish college frat story~~[/s], and crashing parties, that's just the facade for a deeper story that's around characters.

    Related: Check out v25288 and v44476 for similar vibes.
    """

    test "converts full review preserving all formatting" do
      result = VndbToMarkdown.convert(@being_a_dik_review, @vn_link_map)

      # Bold text preserved
      assert result =~ "**being a dik**"
      assert result =~ "**\"spank sally\"**"

      # Italic preserved
      assert result =~ "*well, what else am i gonna do sally"
      assert result =~ "*\"my dad always says follow your heart"

      # Blockquote preserved
      assert result =~ "> "

      # Spoilers converted to ||
      assert result =~ "||surprisingly as you get more into the story"

      assert result =~
               "he cares for her so deeply the only reason he came to college is to be near her.||"

      assert result =~ "||as you go on her route"
      assert result =~ "||we learn he's gay"
      assert result =~ "||choosing to have a throuple"

      # VN links converted
      assert result =~ "[Being a DIK](/vn/being-a-dik)"
      assert result =~ "[Errant Heart](/vn/errant-heart)"

      # Strikethrough preserved
      assert result =~ "~~"

      # Paragraph breaks preserved
      assert result =~ "\n\n"
    end

    test "spoilers are self-contained (opening and closing || on same content)" do
      result = VndbToMarkdown.convert(@being_a_dik_review, @vn_link_map)

      # Each spoiler should have matching || pairs
      # Extract all || positions and verify they're balanced
      parts = String.split(result, "||")
      # Odd number of parts means even number of || markers (balanced)
      assert rem(length(parts), 2) == 1,
             "Spoiler markers || should be balanced (got #{length(parts) - 1} markers)"
    end

    test "no double-wrapped formatting" do
      result = VndbToMarkdown.convert(@being_a_dik_review, @vn_link_map)

      # Should not have quadruple stars (double bold)
      refute result =~ "****"
      # Should not have double || || (nested spoilers from BBCode)
      refute result =~ "||||"
    end

    test "output is a plain string, not a map or struct" do
      result = VndbToMarkdown.convert(@being_a_dik_review, @vn_link_map)
      assert is_binary(result)
    end
  end

  # ---------------------------------------------------------------------------
  # VNDB-specific edge cases for import
  # ---------------------------------------------------------------------------

  describe "VNDB-specific patterns" do
    test "single newlines within paragraph (VNDB style)" do
      # VNDB users often use single newlines within what they consider one paragraph
      input = "Line one of the review.\nLine two continues the thought.\nLine three wraps up."

      result = VndbToMarkdown.convert(input)

      # Single newlines should be preserved as-is in markdown
      # (remark-breaks on frontend will render them as <br>)
      assert result ==
               "Line one of the review.\nLine two continues the thought.\nLine three wraps up."
    end

    test "multiple consecutive newlines" do
      input = "First paragraph.\n\n\n\nSecond paragraph after big gap."

      result = VndbToMarkdown.convert(input)

      # The extra newlines should be preserved
      assert result =~ "First paragraph."
      assert result =~ "Second paragraph"
    end

    test "spoiler spanning multiple lines" do
      input =
        "[spoiler]This is a long spoiler\nthat spans multiple lines\nwith important plot details[/spoiler]"

      result = VndbToMarkdown.convert(input)

      assert result ==
               "||This is a long spoiler\nthat spans multiple lines\nwith important plot details||"
    end

    test "nested bold inside spoiler" do
      input = "[spoiler][b]Major reveal:[/b] the protagonist dies[/spoiler]"

      result = VndbToMarkdown.convert(input)

      assert result == "||**Major reveal:** the protagonist dies||"
    end

    test "VN IDs at sentence boundaries" do
      vn_map = %{"25288" => %{slug: "being-a-dik", title: "Being a DIK"}}

      # VN ID at end of sentence with period
      result = VndbToMarkdown.convert("I recommend v25288.", vn_map)
      assert result == "I recommend [Being a DIK](/vn/being-a-dik)."

      # VN ID in parentheses
      result = VndbToMarkdown.convert("(see also v25288)", vn_map)
      assert result == "(see also [Being a DIK](/vn/being-a-dik))"

      # VN ID at start
      result = VndbToMarkdown.convert("v25288 is my favorite", vn_map)
      assert result == "[Being a DIK](/vn/being-a-dik) is my favorite"
    end

    test "bare URLs in review text" do
      input = "Check my full review at https://myblog.com/review"

      result = VndbToMarkdown.convert(input)

      assert result =~ "https://myblog.com/review"
    end

    test "URL inside BBCode url tag with display text" do
      input =
        "Check out [url=https://vndb.org/v25288]this VN[/url] and [url=https://vndb.org/v7771]that one[/url]"

      result = VndbToMarkdown.convert(input)

      assert result ==
               "Check out [this VN](https://vndb.org/v25288) and [that one](https://vndb.org/v7771)"
    end

    test "review with only formatting, no special content" do
      input = "Great VN, 10/10 would recommend"

      result = VndbToMarkdown.convert(input)

      assert result == input
    end

    test "[raw] tag preserves literal text" do
      input = "[raw]||not a spoiler|| and **not bold**[/raw]"

      result = VndbToMarkdown.convert(input)

      # All markdown-special chars should be escaped
      assert result =~ "\\|\\|not a spoiler\\|\\|"
      assert result =~ "\\*\\*not bold\\*\\*"
    end

    test "code block in review" do
      input = "Here's a config:\n[code]route = true\npath = \"best_girl\"[/code]\nAnd that's it."

      result = VndbToMarkdown.convert(input)

      assert result =~ "```\nroute = true\npath = \"best_girl\"\n```"
    end
  end

  # ---------------------------------------------------------------------------
  # Import data shape: what gets stored in the database
  # ---------------------------------------------------------------------------

  describe "import data shape" do
    test "output is always a binary string" do
      assert is_binary(VndbToMarkdown.convert(nil))
      assert is_binary(VndbToMarkdown.convert(""))
      assert is_binary(VndbToMarkdown.convert("plain text"))
      assert is_binary(VndbToMarkdown.convert("[b]bold[/b]"))
    end

    test "nil and empty return empty string (not nil)" do
      assert VndbToMarkdown.convert(nil) == ""
      assert VndbToMarkdown.convert("") == ""
    end

    test "output does not contain BBCode tags" do
      input =
        "[b]bold[/b] [i]italic[/i] [spoiler]secret[/spoiler] [s]strike[/s] [url=http://example.com]link[/url] [quote]quote[/quote] [code]code[/code]"

      result = VndbToMarkdown.convert(input)

      refute result =~ "[b]"
      refute result =~ "[/b]"
      refute result =~ "[i]"
      refute result =~ "[/i]"
      refute result =~ "[spoiler]"
      refute result =~ "[/spoiler]"
      refute result =~ "[s]"
      refute result =~ "[/s]"
      refute result =~ "[url="
      refute result =~ "[/url]"
      refute result =~ "[quote]"
      refute result =~ "[/quote]"
      refute result =~ "[code]"
      refute result =~ "[/code]"
    end

    test "output uses correct markdown syntax" do
      input = "[b]bold[/b] [i]italic[/i] [spoiler]secret[/spoiler] [s]strike[/s]"

      result = VndbToMarkdown.convert(input)

      assert result =~ "**bold**"
      assert result =~ "*italic*"
      assert result =~ "||secret||"
      assert result =~ "~~strike~~"
    end
  end
end

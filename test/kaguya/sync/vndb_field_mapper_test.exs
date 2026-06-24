defmodule Kaguya.Sync.VndbFieldMapperTest do
  use ExUnit.Case, async: true

  alias Kaguya.Sync.VndbFieldMapper

  describe "clean_description/1" do
    test "nil returns nil" do
      assert VndbFieldMapper.clean_description(nil) == nil
    end

    test "plain text passes through unchanged" do
      assert VndbFieldMapper.clean_description("A simple description.") == "A simple description."
    end

    test "converts bold BBCode to markdown" do
      assert VndbFieldMapper.clean_description("A [b]bold[/b] word") == "A **bold** word"
    end

    test "converts italic BBCode to markdown" do
      assert VndbFieldMapper.clean_description("An [i]italic[/i] word") == "An *italic* word"
    end

    test "converts spoiler BBCode to markdown" do
      assert VndbFieldMapper.clean_description("A [spoiler]secret[/spoiler] thing") ==
               "A ||secret|| thing"
    end

    test "converts strikethrough BBCode to markdown" do
      assert VndbFieldMapper.clean_description("A [s]deleted[/s] word") == "A ~~deleted~~ word"
    end

    test "strips underline tags (no markdown equivalent)" do
      assert VndbFieldMapper.clean_description("An [u]underlined[/u] word") ==
               "An underlined word"
    end

    test "strips [url] tags and keeps link text, then converts other BBCode" do
      input = "[url=https://vndb.org/v1]Hajimete no Otaku[/url] is a [b]great[/b] VN."
      result = VndbFieldMapper.clean_description(input)
      assert result == "Hajimete no Otaku is a **great** VN."
    end

    test "strips attribution brackets" do
      input = "A cool VN about cats.\n[From itch.io]"
      assert VndbFieldMapper.clean_description(input) == "A cool VN about cats."
    end

    test "handles combined url stripping + attribution + bbcode conversion" do
      input =
        "[url=/v123]Another VN[/url] has a [i]nice[/i] story.\n[Translated from Getchu]"

      result = VndbFieldMapper.clean_description(input)
      assert result == "Another VN has a *nice* story."
    end

    test "empty string after cleaning returns nil" do
      assert VndbFieldMapper.clean_description("[From itch.io]") == nil
    end

    test "non-binary returns nil" do
      assert VndbFieldMapper.clean_description(42) == nil
    end
  end

  describe "clean_release_notes/1" do
    test "nil returns nil" do
      assert VndbFieldMapper.clean_release_notes(nil) == nil
    end

    test "plain text passes through unchanged" do
      assert VndbFieldMapper.clean_release_notes("Patch 1.2 fixes crashes.") ==
               "Patch 1.2 fixes crashes."
    end

    test "converts [url] tags to markdown links" do
      input = "See [url=https://example.com]release page[/url] for details."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "See [release page](https://example.com) for details."
    end

    test "expands VNDB-relative release links to full URLs" do
      input = "Bundled with [url=/r115473]Hiveswap Friendsim[/url]."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "Bundled with [Hiveswap Friendsim](https://vndb.org/r115473)."
    end

    test "expands VNDB-relative VN links to full URLs" do
      input = "See [url=/v12345]the original[/url]."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "See [the original](https://vndb.org/v12345)."
    end

    test "linkifies bare release IDs" do
      input = "Supersedes r12345."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "Supersedes [r12345](https://vndb.org/r12345)."
    end

    test "converts formatting BBCode to markdown" do
      input = "This patch adds [b]new routes[/b] and [i]bug fixes[/i]."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "This patch adds **new routes** and *bug fixes*."
    end

    test "converts spoiler tags" do
      input = "Contains [spoiler]ending changes[/spoiler]."
      result = VndbFieldMapper.clean_release_notes(input)
      assert result == "Contains ||ending changes||."
    end

    test "empty string returns nil" do
      assert VndbFieldMapper.clean_release_notes("") == nil
    end

    test "non-binary returns nil" do
      assert VndbFieldMapper.clean_release_notes(123) == nil
    end
  end
end

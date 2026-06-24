defmodule KaguyaWeb.SharedComponents.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KaguyaWeb.SharedComponents.Markdown

  describe "variant coverage" do
    # Every value declared in `attr :variant, values: ...` must round-trip
    # through `markdown/1` without raising. Catches the case where someone
    # adds a new variant to the attr list but forgets to wire it into one
    # of the dispatch fns (preset_for, wrapper_class) — a regression that
    # crashed `/@:username` profile renders once.
    for variant <- ~w(user comment bio policy plain) do
      test "markdown/1 renders cleanly for variant=#{variant}" do
        html =
          render_component(&Markdown.markdown/1,
            content: "**hello** ||spoiler||",
            variant: unquote(variant)
          )

        assert is_binary(html)
        assert html =~ "hello"
      end

      test "markdown_inline/1 renders cleanly for variant=#{variant}" do
        html =
          render_component(&Markdown.markdown_inline/1,
            content: "**hello**",
            variant: unquote(variant)
          )

        assert html =~ "<strong>hello</strong>"
      end
    end
  end

  describe "markdown_inline/1" do
    test "compiles raw markdown through the safe user-content renderer" do
      html =
        render_component(&Markdown.markdown_inline/1,
          content: "**bold** ||twist|| <script>alert(1)</script>"
        )

      assert html =~ "<strong>bold</strong>"
      assert html =~ ~s(data-spoiler)
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "markdown/1" do
    test "renders short read-more markdown without a toggle" do
      html =
        render_component(&Markdown.markdown/1,
          content: "A **long** description",
          read_more: true,
          read_more_id: "description-read-more-test",
          read_more_limit: 80
        )

      refute html =~ ~s(phx-hook="ReadMore")
      refute html =~ "data-readmore-expand"
      assert html =~ "A <strong>long</strong> description"
    end

    test "renders long read-more markdown with inline more and less toggles" do
      html =
        render_component(&Markdown.markdown/1,
          content: String.duplicate("A **long** d'être description with more words. ", 8),
          read_more: true,
          read_more_id: "description-read-more-test",
          read_more_limit: 80
        )

      assert html =~ ~s(id="description-read-more-test")
      assert html =~ ~s(phx-hook="ReadMore")
      assert html =~ "data-readmore-collapsed"
      assert html =~ "data-readmore-expanded"
      assert html =~ "data-readmore-expand"
      assert html =~ "data-readmore-collapse"
      assert html =~ "... "
      assert html =~ "font-medium"
      assert html =~ ">more</button>"
      assert html =~ ">less</button>"
      refute html =~ "&lt;/p&gt;"
      refute html =~ "less/p&gt;"
    end
  end

  describe "markdown/1 responsive read-more" do
    test "renders separate mobile and desktop collapsed variants when both limits are set" do
      content = String.duplicate("A long description with many words to truncate. ", 20)

      html =
        render_component(&Markdown.markdown/1,
          content: content,
          read_more: true,
          read_more_id: "responsive-read-more-test",
          read_more_mobile_limit: 80,
          read_more_desktop_limit: 400
        )

      assert html =~ ~s(data-readmore-collapsed-mobile)
      assert html =~ ~s(data-readmore-collapsed-desktop)
      refute html =~ ~s(data-readmore-collapsed=)
      assert html =~ ~s(class="lg:hidden")
      assert html =~ ~s(class="hidden lg:block")
      assert html =~ ">more</button>"
      assert html =~ ">less</button>"
    end

    test "mobile-truncates-only when content fits desktop budget but exceeds mobile" do
      # 200-char content: fits 400 (desktop), exceeds 80 (mobile)
      content = String.duplicate("word ", 40)

      html =
        render_component(&Markdown.markdown/1,
          content: content,
          read_more: true,
          read_more_id: "mobile-only-truncate-test",
          read_more_mobile_limit: 80,
          read_more_desktop_limit: 400
        )

      assert html =~ ~s(data-readmore-collapsed-mobile)
      assert html =~ ~s(data-readmore-collapsed-desktop)
      # Mobile variant has the toggle; desktop renders the full content
      # without a "more" button since there's nothing to expand from.
      mobile_more_count =
        ~r/data-readmore-collapsed-mobile.*?>more</s
        |> Regex.scan(html)
        |> length()

      assert mobile_more_count == 1
    end

    test "falls back to single-limit path when only one breakpoint limit is set" do
      content = String.duplicate("A long description with words. ", 10)

      html =
        render_component(&Markdown.markdown/1,
          content: content,
          read_more: true,
          read_more_id: "single-limit-fallback-test",
          read_more_limit: 80,
          read_more_mobile_limit: 60
          # desktop_limit omitted → single-limit path (uses read_more_limit)
        )

      assert html =~ ~s(data-readmore-collapsed)
      refute html =~ ~s(data-readmore-collapsed-mobile)
      refute html =~ ~s(data-readmore-collapsed-desktop)
    end
  end
end

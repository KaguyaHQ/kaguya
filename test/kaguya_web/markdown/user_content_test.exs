defmodule KaguyaWeb.Markdown.UserContentTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Markdown.UserContent

  import Phoenix.HTML, only: [safe_to_string: 1]

  defp render(markdown), do: markdown |> UserContent.to_html() |> safe_to_string()
  defp render(markdown, opts), do: UserContent.to_html(markdown, opts) |> safe_to_string()

  describe "emphasis" do
    test "renders **bold** and *italic*" do
      html = render("**bold** and *italic*")

      assert html =~ "<strong>bold</strong>"
      assert html =~ "<em>italic</em>"
    end

    test "renders _underscore italic_ and __underscore bold__" do
      html = render("This is _italic_ and __bold__ together")

      assert html =~ "<em>italic</em>"
      assert html =~ "<strong>bold</strong>"
    end

    test "underscores inside words stay literal" do
      html = render("snake_case_var and word_inside_word")

      refute html =~ "<em>"
      refute html =~ "<strong>"
      assert html =~ "snake_case_var"
      assert html =~ "word_inside_word"
    end

    test "renders ~~strikethrough~~" do
      html = render("~~gone~~")
      assert html =~ "<del>gone</del>"
    end
  end

  describe "links" do
    test "renders inline markdown links with target+rel and link class" do
      html = render("[Kaguya](https://kaguya.io)")

      assert html =~ ~s(href="https://kaguya.io")
      assert html =~ ~s(target="_blank")
      assert html =~ "noopener noreferrer nofollow"
      assert html =~ "text-foreground-link"
    end

    test "autolinks bare URLs" do
      html = render("Visit https://example.com directly")

      assert html =~ ~s(<a href="https://example.com")
      assert html =~ ~s(target="_blank")
    end

    test "rewrites VNDB-relative paths to vndb.org" do
      html = render("See [release](/r115473) and [vn](/v12345).")

      assert html =~ ~s(href="https://vndb.org/r115473")
      assert html =~ ~s(href="https://vndb.org/v12345")
    end

    test "keeps local /@user links relative" do
      html = render("[profile](/@reader)")
      assert html =~ ~s(href="/@reader")
    end

    test "blocks protocol-relative + javascript: hrefs" do
      html = render("[bad](//evil.example/path) [worse](javascript:alert(1))")
      assert html =~ ~s(href="#")
      refute html =~ "javascript:"
      refute html =~ "//evil.example"
    end
  end

  describe "spoilers" do
    test "wraps ||text|| in a spoiler span" do
      html = render("before ||hidden|| after")

      assert html =~ ~s(data-spoiler)
      assert html =~ ~s(class="spoiler")
      assert html =~ ~s(role="button")
      assert html =~ "hidden"
    end

    test "renders nested markdown inside spoilers" do
      html = render("||hidden **bold** text||")

      assert html =~ ~s(data-spoiler)
      assert html =~ "<strong>bold</strong>"
    end

    test "leaves escaped spoiler markers literal when both sides are escaped" do
      html = render("\\||not hidden\\|| and ||hidden||")

      assert html =~ "||not hidden||"
      assert html =~ ~s(data-spoiler)
      assert html =~ "hidden"
    end

    test "supports multiple spoilers in one line" do
      html = render("||first|| middle ||second||")

      matches = Regex.scan(~r/data-spoiler/, html)
      assert length(matches) == 2
      assert html =~ "first"
      assert html =~ "second"
      assert html =~ "middle"
    end
  end

  describe "blocks" do
    test "renders paragraphs as bare <p> with no inline classes" do
      html = render("first paragraph\n\nsecond paragraph")

      assert html =~ ~r"<p>\s*first paragraph"
      assert html =~ ~r"<p>\s*second paragraph"
      refute html =~ ~s(<p class=)
    end

    test "renders bare blockquote and lists (styled via .kaguya-markdown CSS)" do
      html =
        render("""
        > quoted line

        - one
        - two

        1. first
        2. second
        """)

      assert html =~ "<blockquote>"
      refute html =~ ~s(<blockquote class=)
      assert html =~ "<ul>"
      refute html =~ ~s(<ul class=)
      assert html =~ "<ol>"
      refute html =~ ~s(<ol class=)
      assert html =~ "<li>"
    end

    test "renders fenced code blocks as bare <pre><code>" do
      html =
        render("""
        ```
        fn x -> x + 1 end
        ```
        """)

      assert html =~ "<pre>"
      assert html =~ "<code>"
      assert html =~ "fn x -&gt; x + 1 end"
      refute html =~ ~s(<pre class=)
    end

    test "renders inline `code`" do
      html = render("use `Enum.map/2` here")
      assert html =~ "<code"
      assert html =~ "Enum.map/2"
    end
  end

  describe "tag allowlist (review/comment default)" do
    test "strips headings but keeps inline content" do
      html = render("# Big title\n\nbody paragraph")

      refute html =~ "<h1"
      refute html =~ "<h2"
      assert html =~ "Big title"
      assert html =~ "body paragraph"
    end

    test "strips raw <script> tags as escaped text" do
      html = render("safe ||hidden|| <script>alert('x')</script>")

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "tag allowlist (bio surface with :allowed_tags opt)" do
    test "keeps headings when h-tags are in :allowed_tags" do
      allowed = ~w(p br strong b em i del a span blockquote ul ol li pre code h1 h2 h3)
      html = render("# Big title\n\nbody", allowed_tags: allowed)

      assert html =~ "<h1>"
      assert html =~ "Big title"
    end
  end

  describe "comment preset" do
    test "preserves blank-line visual spacing as soft breaks (NBSP trick)" do
      # Two paragraphs separated by a blank line. Without the comment preprocess
      # this would render as two <p> blocks; with it, we get a single paragraph
      # with the blank position filled by NBSP so Earmark's break: true makes it
      # a soft break instead of a paragraph boundary.
      html = render("first\n\nsecond", preset: :comment)

      paragraph_count = Regex.scan(~r/<p>/, html) |> length()
      assert paragraph_count == 1
      assert html =~ "first"
      assert html =~ "second"
      # NBSP between them (U+00A0 → C2 A0 in UTF-8)
      assert String.contains?(html, <<0xC2, 0xA0>>)
    end

    test "drops lone-backslash lines" do
      html = render("hello\n\\\nworld", preset: :comment)
      refute html =~ "\\"
      assert html =~ "hello"
      assert html =~ "world"
    end

    test "still renders full block markdown (blockquote, lists, code)" do
      html =
        render(
          """
          intro

          > quoted

          - one
          - two

          ```
          code
          ```
          """,
          preset: :comment
        )

      assert html =~ "<blockquote>"
      assert html =~ "<ul>"
      assert html =~ "<li>"
      assert html =~ "<pre>"
      assert html =~ "<code>"
    end

    test "spoilers still work inside comment preset" do
      html = render("a ||hidden|| b", preset: :comment)
      assert html =~ ~s(data-spoiler)
      assert html =~ "hidden"
    end
  end

  describe "bio preset" do
    test "strips link syntax to plain text" do
      html = render("see [my site](https://example.com) for more", preset: :bio)
      refute html =~ "<a "
      refute html =~ "example.com"
      assert html =~ "my site"
    end

    test "escapes numbered-list prefixes so 1. text doesn't render as a list" do
      html = render("1. first\n2. second", preset: :bio)
      refute html =~ "<ol>"
      refute html =~ "<li>"
      assert html =~ "1. first"
      assert html =~ "2. second"
    end

    test "strips disallowed tags (blockquote, lists, code) — bio allowlist excludes them" do
      html =
        render(
          """
          > quoted

          - one
          - two

          ```
          code
          ```
          """,
          preset: :bio
        )

      refute html =~ "<blockquote>"
      refute html =~ "<ul>"
      refute html =~ "<ol>"
      refute html =~ "<pre>"
      assert html =~ "quoted"
      assert html =~ "one"
    end

    test "keeps emphasis but strips spoilers (bio surface excludes <span>)" do
      # Matches `BioContent.tsx`: allowedElements excludes `span`, so spoiler
      # wrappers get unwrapped and the inner text bubbles up as plain content.
      # Bios on Next.js don't render spoilers; we keep that contract.
      html = render("**bold** and ||hidden||", preset: :bio)
      assert html =~ "<strong>bold</strong>"
      refute html =~ ~s(data-spoiler)
      refute html =~ ~s(class="spoiler")
      assert html =~ "hidden"
    end
  end

  describe "preprocess option" do
    test "accepts a custom 1-arity fn" do
      uppercase = fn s -> String.upcase(s) end
      html = render("hello", preprocess: uppercase)
      assert html =~ "HELLO"
    end

    test "explicit :allowed_tags overrides preset allowlist" do
      # Bio normally strips lists; but allowed_tags wins.
      allowed = ~w(p br strong em ul ol li)
      html = render("- one\n- two", preset: :bio, allowed_tags: allowed)
      assert html =~ "<ul>"
      assert html =~ "<li>"
    end
  end

  describe "edge cases" do
    test "nil and empty content render as empty safe" do
      assert {:safe, ""} = UserContent.to_html(nil)
      assert {:safe, ""} = UserContent.to_html("")
    end

    test "non-binary content renders as empty safe" do
      assert {:safe, ""} = UserContent.to_html(%{nope: true})
      assert {:safe, ""} = UserContent.to_html(123)
    end
  end
end

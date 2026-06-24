defmodule KaguyaWeb.SharedComponents.CoverTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KaguyaWeb.SharedComponents.Cover

  @vn %{
    slug: "steins-gate",
    title: "Steins;Gate",
    images: %{
      small: "https://cdn/example/s.webp",
      medium: "https://cdn/example/m.webp",
      large: "https://cdn/example/l.webp",
      xl: "https://cdn/example/xl.webp"
    }
  }

  describe "cover/1" do
    test "renders an <img> with full srcset and the requested sizes attr" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px")

      assert html =~ ~s|src="https://cdn/example/m.webp"|
      assert html =~ "128w"
      assert html =~ "256w"
      assert html =~ "512w"
      assert html =~ "1024w"
      assert html =~ ~s|sizes="180px"|
      # Doesn't wrap in a link unless asked.
      refute html =~ ~r|<a[^>]+href="/vn/steins-gate"|
    end

    test "link={true} wraps the image in an <a> to /vn/:slug" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px", link: true)

      assert html =~ ~s|href="/vn/steins-gate"|
      assert html =~ ~r|<a[^>]*\s+title="Steins;Gate"|
    end

    test "show_title_tooltip stamps data-cover-title for the tooltip hook" do
      html =
        render_component(&Cover.cover/1,
          vn: @vn,
          sizes: "180px",
          link: true,
          show_title_tooltip: true
        )

      assert html =~ ~s|data-cover-title="Steins;Gate"|
      refute html =~ ~r|<a[^>]*\s+title="Steins;Gate"|
    end

    test "no data-cover-title attribute when show_title_tooltip is false" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px", link: true)

      refute html =~ "data-cover-title"
    end

    test "shadow={true} applies the Letterboxd-style drop shadow inline style" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px", shadow: true)

      assert html =~ "box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.35)"
    end

    test "sensitive covers get the production NSFW blur data attribute and blur size" do
      vn = Map.merge(@vn, %{is_image_nsfw: true})

      html = render_component(&Cover.cover/1, vn: vn, sizes: "180px")

      assert html =~ ~s|data-nsfw-blur="1"|
      assert html =~ "--nsfw-blur-size: 180;"
      refute html =~ ~s|style="false |
    end

    test "sensitive cover blur size uses the default sizes segment like the Next component" do
      vn = Map.merge(@vn, %{is_image_nsfw: true})

      html =
        render_component(&Cover.cover/1,
          vn: vn,
          sizes: "(max-width: 640px) 124px, 144px"
        )

      assert html =~ "--nsfw-blur-size: 144;"
      refute html =~ "--nsfw-blur-size: 640;"
    end

    test "has_ero alone does not blur a safe cover image" do
      vn = Map.merge(@vn, %{has_ero: true, is_image_nsfw: false, is_image_suggestive: false})

      html = render_component(&Cover.cover/1, vn: vn, sizes: "180px")

      refute html =~ "data-nsfw-blur"
      refute html =~ "--nsfw-blur-size"
    end

    test "blur_nsfw={false} opts a sensitive cover out of the blur contract" do
      vn = Map.merge(@vn, %{is_image_suggestive: true})

      html = render_component(&Cover.cover/1, vn: vn, sizes: "180px", blur_nsfw: false)

      refute html =~ "data-nsfw-blur"
      refute html =~ "--nsfw-blur-size"
    end

    test "enable_nsfw_reveal stamps the click-to-reveal data contract" do
      vn = Map.merge(@vn, %{is_image_nsfw: true})

      html = render_component(&Cover.cover/1, vn: vn, sizes: "180px", enable_nsfw_reveal: true)

      assert html =~ ~s|data-nsfw-blur="1"|
      assert html =~ ~s|data-nsfw-reveal="1"|
    end

    test "eager={true} sets loading=eager and fetchpriority=high" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px", eager: true)

      assert html =~ ~s|loading="eager"|
      assert html =~ ~s|fetchpriority="high"|
    end

    test "defaults to loading=lazy with no fetchpriority" do
      html = render_component(&Cover.cover/1, vn: @vn, sizes: "180px")

      assert html =~ ~s|loading="lazy"|
      refute html =~ "fetchpriority"
    end

    test "object_fit=contain picks the object-contain class" do
      html =
        render_component(&Cover.cover/1, vn: @vn, sizes: "180px", object_fit: "contain")

      assert html =~ "object-contain"
      refute html =~ "object-cover"
    end

    test "no images falls back to a title card and no <img>" do
      vn_no_image = %{slug: "no-image", title: "Some VN", images: %{}}

      html = render_component(&Cover.cover/1, vn: vn_no_image, sizes: "180px")

      refute html =~ "<img"
      assert html =~ "Some VN"
    end

    test "no slug ignores link={true} and renders the inline span wrapper" do
      vn_no_slug = %{title: "Title only", images: @vn.images}

      html = render_component(&Cover.cover/1, vn: vn_no_slug, sizes: "180px", link: true)

      refute html =~ "<a "
      assert html =~ "<img"
    end
  end

  describe "cover_tooltip_provider/1" do
    defmodule Wrapper do
      use Phoenix.Component
      alias KaguyaWeb.SharedComponents.Cover

      def render(assigns) do
        ~H"""
        <Cover.cover_tooltip_provider id="test-tooltip" delay={500} skip_delay={800}>
          <span>inner content</span>
        </Cover.cover_tooltip_provider>
        """
      end
    end

    test "mounts the CoverTooltip hook with the configured delays and renders inner block" do
      html = render_component(&Wrapper.render/1, %{})

      assert html =~ ~s|phx-hook="CoverTooltip"|
      assert html =~ ~s|id="test-tooltip"|
      assert html =~ ~s|data-delay-duration="500"|
      assert html =~ ~s|data-skip-delay-duration="800"|
      assert html =~ "inner content"
    end
  end
end

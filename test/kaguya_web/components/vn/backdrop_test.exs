defmodule KaguyaWeb.VN.BackdropTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KaguyaWeb.VN.Backdrop

  describe "vn_backdrop/1" do
    test "renders desktop + mobile backdrops with no NSFW attributes when adult=false" do
      html =
        render_component(&Backdrop.vn_backdrop/1,
          image_url: "https://cdn/example/desktop.webp",
          mobile_image_url: "https://cdn/example/mobile.webp",
          adult: false
        )

      assert html =~ ~s|src="https://cdn/example/desktop.webp"|
      assert html =~ ~s|src="https://cdn/example/mobile.webp"|
      refute html =~ "data-nsfw-blur"
      refute html =~ "--nsfw-blur-size"
    end

    test "stamps data-nsfw-blur + --nsfw-blur-size on both images when adult=true" do
      html =
        render_component(&Backdrop.vn_backdrop/1,
          image_url: "https://cdn/example/desktop.webp",
          mobile_image_url: "https://cdn/example/mobile.webp",
          adult: true
        )

      # The desktop backdrop spans the 1200px container.
      assert html =~ ~s|data-nsfw-blur="1"|
      assert html =~ "--nsfw-blur-size: 1200;"
      # The mobile backdrop spans the viewport (smaller blur radius).
      assert html =~ "--nsfw-blur-size: 800;"
    end

    test "renders nothing when both image URLs are nil" do
      html =
        render_component(&Backdrop.vn_backdrop/1,
          image_url: nil,
          mobile_image_url: nil,
          adult: false
        )

      refute html =~ "<img"
    end
  end
end

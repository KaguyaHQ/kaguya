defmodule KaguyaWeb.VN.SidebarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KaguyaWeb.VN.Sidebar

  describe "vn_sidebar/1" do
    test "uses shared proportional blur and click-to-reveal overlay for sensitive covers" do
      vn = %{
        title: "Once in a Lifetime",
        slug: "once-in-a-lifetime",
        images: %{
          small: "https://cdn/example/s.webp",
          medium: "https://cdn/example/m.webp",
          large: "https://cdn/example/l.webp",
          xl: "https://cdn/example/xl.webp"
        },
        is_image_nsfw: true,
        is_image_suggestive: false
      }

      html =
        render_component(&Sidebar.vn_sidebar/1,
          vn: vn,
          display_vn: vn,
          viewer: nil,
          viewer_vn: nil,
          auth: nil,
          current_path: "/vn/once-in-a-lifetime"
        )

      assert html =~ ~s|data-nsfw-blur="1"|
      assert html =~ ~s|data-nsfw-reveal="1"|
      assert html =~ "--nsfw-blur-size: 220;"
      assert html =~ "data-nsfw-cover-reveal-overlay"
      assert html =~ "data-nsfw-revealed"
      refute html =~ "blur-md"
    end

    test "renders interactive controls (not the sign-in prompt) while an authenticated viewer loads" do
      vn = %{
        title: "Limelight Lemonade Jam",
        slug: "limelight-lemonade-jam",
        images: %{
          small: "https://cdn/example/s.webp",
          medium: "https://cdn/example/m.webp",
          large: "https://cdn/example/l.webp",
          xl: "https://cdn/example/xl.webp"
        },
        is_image_nsfw: false,
        is_image_suggestive: false
      }

      # Cold reload window: the user is authenticated (auth present) but the
      # async viewer bundle hasn't landed yet. Controls render optimistically
      # in their resting state and stay interactive — they must never push the
      # auth prompt at a signed-in user, and there is no dead loading placeholder.
      html =
        render_component(&Sidebar.vn_sidebar/1,
          vn: vn,
          display_vn: vn,
          viewer: nil,
          viewer_vn: nil,
          auth: %{ok: true},
          current_path: "/vn/limelight-lemonade-jam"
        )

      # Signed-in review affordance is present and wired to open the editor…
      assert html =~ ~s|phx-click="open_review_dialog"|
      # …not the signed-out auth prompt, and not a dead loading placeholder.
      refute html =~ "Sign in to write a review"
      refute html =~ "Loading your account…"
    end
  end
end

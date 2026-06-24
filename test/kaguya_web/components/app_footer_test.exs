defmodule KaguyaWeb.AppFooterTest do
  use KaguyaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "app_footer/1" do
    test "create links use the /contribute/:type namespace, never entity slugs" do
      html = render_component(&KaguyaWeb.AppFooter.app_footer/1)

      # Create lives under /contribute/* so it can't collide with a real
      # entity slug (a VN named "New" owns /vn/new).
      assert html =~ ~s(href="/contribute/vn")
      assert html =~ ~s(href="/contribute/character")
      assert html =~ ~s(href="/contribute/developer")
      refute html =~ ~s(href="/character/new")

      # The series create form isn't ported yet, so it has no footer link.
      # It belongs at /contribute/series when added — and no create link may
      # ever point back at the colliding /vn/new style paths.
      refute html =~ ~s(href="/vn/new")
      refute html =~ ~s(href="/developer/new")
      refute html =~ ~s(href="/series/new")

      assert html =~ ~s(href="/history")
    end
  end
end

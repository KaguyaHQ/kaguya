defmodule KaguyaWeb.NotFoundControllerTest do
  use KaguyaWeb.ConnCase, async: true

  describe "unmatched routes" do
    test "render the branded 404 page with HTTP 404", %{conn: conn} do
      conn = get(conn, "/this-route-does-not-exist")
      body = html_response(conn, 404)

      assert body =~ "https://images.kaguya.io/ui/404.webp"
      assert body =~ "Return home"
      assert body =~ "Art from Sengoku Rance"
      assert body =~ "phx-hook=\"NotFoundButton\""
    end

    test "renders 404 for nested unmatched paths", %{conn: conn} do
      conn = get(conn, "/something/nested/that-does-not-exist")
      assert html_response(conn, 404) =~ "Return home"
    end
  end
end

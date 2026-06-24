defmodule KaguyaWeb.SitemapControllerTest do
  use KaguyaWeb.ConnCase, async: true

  describe "sitemap redirects" do
    test "redirects the sitemap index to the generated R2 object" do
      conn = get(build_conn(), "/sitemap.xml")

      assert redirected_to(conn, 302) == "https://images.kaguya.io/sitemaps/sitemap.xml"

      assert get_resp_header(conn, "cache-control") == [
               "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800"
             ]
    end

    test "redirects known sitemap chunk ids to generated R2 objects" do
      conn = get(build_conn(), "/sitemap/vns-0.xml")

      assert redirected_to(conn, 302) == "https://images.kaguya.io/sitemaps/vns-0.xml"
    end

    test "returns 404 for unknown sitemap ids" do
      conn = get(build_conn(), "/sitemap/nope-0.xml")

      assert response(conn, 404) == "Not found"
    end
  end
end

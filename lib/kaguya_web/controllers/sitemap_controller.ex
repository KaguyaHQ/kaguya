defmodule KaguyaWeb.SitemapController do
  use KaguyaWeb, :controller

  alias Kaguya.Sitemaps
  alias Kaguya.Sitemaps.Publisher

  @cache_control "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800"

  def index(conn, _params) do
    redirect_to_sitemap(conn, "sitemap.xml")
  end

  def show(conn, %{"id" => id}) do
    if Sitemaps.valid_chunk_filename?(id) and id != "sitemap.xml" do
      redirect_to_sitemap(conn, id)
    else
      send_resp(conn, 404, "Not found")
    end
  end

  defp redirect_to_sitemap(conn, filename) do
    conn
    |> put_resp_header("cache-control", @cache_control)
    |> redirect(external: Publisher.public_url(filename))
  end
end

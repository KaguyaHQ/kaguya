defmodule KaguyaWeb.AssetController do
  use KaguyaWeb, :controller

  alias KaguyaWeb.BrowseLive.TagSnapshot

  def vn_tags(conn, %{"hash" => hash}) do
    if hash == TagSnapshot.asset_hash() do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, TagSnapshot.asset_body())
    else
      send_resp(conn, 404, "not found")
    end
  end
end

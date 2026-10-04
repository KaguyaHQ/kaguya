defmodule KaguyaWeb.Plugs.LiveViewReloadCookieTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Plugs.LiveViewReloadCookie

  @cookie "__phoenix_reload_status__"

  test "clears an invalid reload cookie before LiveView renders" do
    conn =
      Plug.Test.conn(:get, "/vn/example")
      |> Plug.Conn.put_req_header("cookie", "#{@cookie}=invalid")
      |> LiveViewReloadCookie.call([])

    refute Map.has_key?(conn.req_cookies, @cookie)
    refute Map.has_key?(conn.cookies, @cookie)
    assert conn.resp_cookies[@cookie].max_age == 0
  end

  test "preserves a valid reload cookie for LiveView to handle" do
    token =
      Phoenix.LiveView.Static.sign_token(KaguyaWeb.Endpoint, %{
        status: 404,
        view: "KaguyaWeb.VNLive.Show",
        exception: nil,
        stack: []
      })

    conn =
      Plug.Test.conn(:get, "/vn/example")
      |> Plug.Conn.put_req_header("cookie", "#{@cookie}=#{token}")
      |> LiveViewReloadCookie.call([])

    assert conn.req_cookies[@cookie] == token
    refute Map.has_key?(conn.resp_cookies, @cookie)
  end
end

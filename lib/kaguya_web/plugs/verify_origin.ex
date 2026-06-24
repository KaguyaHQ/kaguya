defmodule KaguyaWeb.Plugs.VerifyOriginHeader do
  import Plug.Conn

  @header "x-origin-sig"
  # match this with your Cloudflare transform rule
  @secret "GFQmpvOu56R+AElbJmVSfx+fV2zrUxCG"

  def init(_opts) do
    Application.get_env(:kaguya, :protect_origin_header, false)
  end

  def call(conn, false), do: conn

  def call(conn, true) do
    case get_req_header(conn, @header) do
      [@secret] ->
        conn

      _ ->
        conn
        |> send_resp(:forbidden, "Forbidden: Missing or invalid origin signature.")
        |> halt()
    end
  end
end

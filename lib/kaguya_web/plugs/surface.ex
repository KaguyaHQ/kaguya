defmodule KaguyaWeb.Plugs.Surface do
  @moduledoc """
  Plug to determine the current surface from the request.

  Resolution order:
  1. X-Kaguya-Surface header (mobile app/testing)
  2. Host header (web subdomain: vn.kaguya.io)
  3. Default: :vn
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    surface = resolve_surface(conn)
    assign(conn, :surface, surface)
  end

  defp resolve_surface(conn) do
    explicit = get_req_header(conn, "x-kaguya-surface") |> List.first()

    if explicit == "vn", do: :vn, else: :vn
  end
end

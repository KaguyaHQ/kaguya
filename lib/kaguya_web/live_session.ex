defmodule KaguyaWeb.LiveSession do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2, get_session: 2]

  def session(conn) do
    %{
      "cf_ipcountry" => get_req_header(conn, "cf-ipcountry") |> List.first(),
      "user_token" => get_session(conn, "user_token"),
      "current_user_id" =>
        get_session(conn, "current_user_id") || get_session(conn, :current_user_id)
    }
  end
end

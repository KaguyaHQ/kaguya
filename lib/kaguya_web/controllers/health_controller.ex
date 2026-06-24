defmodule KaguyaWeb.HealthController do
  use KaguyaWeb, :controller

  def check(conn, _params) do
    db_ok =
      try do
        Kaguya.Repo.query!("SELECT 1")
        true
      rescue
        _ -> false
      end

    oban_ok =
      try do
        # Returns nil if the queue isn't running, a map if it is
        Oban.check_queue(queue: :maintenance) != nil
      rescue
        _ -> false
      end

    healthy = db_ok and oban_ok

    status = if healthy, do: :ok, else: :service_unavailable

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{
      status: if(healthy, do: "healthy", else: "degraded"),
      db: if(db_ok, do: "ok", else: "fail"),
      oban: if(oban_ok, do: "ok", else: "fail")
    })
  end
end

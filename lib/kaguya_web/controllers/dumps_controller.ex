defmodule KaguyaWeb.DumpsController do
  use KaguyaWeb, :controller

  alias Kaguya.PublicDump.Publisher

  def index(conn, _params) do
    case publisher().list_published() do
      {:ok, payload} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=300, s-maxage=300")
        |> json(payload)

      {:error, _reason} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:bad_gateway)
        |> json(%{error: "list failed"})
    end
  end

  defp publisher, do: Application.get_env(:kaguya, :public_dump_publisher, Publisher)
end

defmodule KaguyaWeb.NotFoundController do
  @moduledoc """
  Catch-all controller for unmatched URLs in the `:browser` pipeline.

  Renders the 404 view with HTTP 404 so unknown routes look identical
  to a missing-resource page rendered from inside a LiveView.
  """

  use KaguyaWeb, :controller

  def call(conn, _opts) do
    conn
    |> put_status(:not_found)
    |> put_view(html: KaguyaWeb.ErrorHTML)
    |> render(:"404")
  end
end

defmodule KaguyaWeb.Plugs.ObservabilityContext do
  @moduledoc """
  Pushes the current user + request metadata into `Logger.metadata` and
  `Sentry.Context` once `conn.assigns.current_user` has been resolved.

  Mirrors the LiveView `on_mount` observability setup in
  `KaguyaWeb.UserAuth` so every error — regardless of the surface it
  originated from — carries the same `user_id`, `live_view`,
  `request_path`, `operation` fields.

  Insert this plug **after** the auth plug that populates
  `:current_user` (after `:fetch_current_user` for the browser pipeline).
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user_id = get_in(conn.assigns, [:current_user, :id])

    Logger.metadata(
      user_id: user_id,
      request_path: conn.request_path
    )

    Sentry.Context.set_user_context(%{id: user_id})

    Sentry.Context.set_tags_context(%{
      "source" => "http",
      "method" => conn.method,
      "request_path" => conn.request_path
    })

    conn
  rescue
    _ -> conn
  end
end

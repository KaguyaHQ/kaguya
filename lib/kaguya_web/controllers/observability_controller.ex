defmodule KaguyaWeb.ObservabilityController do
  @moduledoc """
  Browser → Axiom proxy for client-side observability events.

  Accepts a small
  allow-list of `event_type` values and emits a Logger call so the
  existing `Kaguya.Observability.AxiomLogHandler` ships the event with the same
  structured columns as server-side telemetry.

  Web Vitals are emitted at `:warning` only when `rating == "poor"`,
  so healthy page loads don't burn quota (the JS reporter also drops
  `"good"` ratings before they reach the wire — defense in depth).
  """

  use KaguyaWeb, :controller
  require Logger

  @allowed_event_types ~w(WEB_VITAL CLIENT_ERROR LIVE_SOCKET_ERROR)
  @web_vital_names ~w(CLS INP LCP FCP TTFB)

  @doc false
  def ingest(conn, %{"event_type" => "WEB_VITAL"} = body) do
    name = Map.get(body, "name")
    rating = Map.get(body, "rating", "good")
    value = sanitize_number(Map.get(body, "value"))
    page = sanitize_path(Map.get(body, "page"))

    if name in @web_vital_names do
      log_fun =
        case rating do
          "poor" -> &Logger.warning/2
          _ -> &Logger.info/2
        end

      log_fun.("web_vital",
        event_type: "WEB_VITAL",
        operation: "browser.web_vital",
        name: name,
        # web-vitals reports CLS as a float and timings as ms; rough is fine
        # for dashboards and reusing the duration_ms column keeps queries simple.
        duration_ms: value,
        result: rating,
        request_path: page,
        user_id: viewer_id(conn)
      )
    end

    send_resp(conn, 204, "")
  end

  def ingest(conn, %{"event_type" => type} = body) when type in @allowed_event_types do
    Logger.warning("client event",
      event_type: type,
      operation: "browser.#{String.downcase(type)}",
      reason: truncate(Map.get(body, "reason"), 500),
      request_path: sanitize_path(Map.get(body, "page")),
      user_id: viewer_id(conn)
    )

    send_resp(conn, 204, "")
  end

  def ingest(conn, _), do: send_resp(conn, 400, "")

  defp viewer_id(conn), do: get_in(conn.assigns, [:current_user, :id])

  defp sanitize_number(n) when is_integer(n) or is_float(n), do: n
  defp sanitize_number(_), do: nil

  defp sanitize_path(path) when is_binary(path) do
    # Drop query strings + fragments so dashboards group by route instead of
    # one row per ?utm_… variant.
    path |> String.split(["?", "#"], parts: 2) |> List.first() |> String.slice(0, 200)
  end

  defp sanitize_path(_), do: nil

  defp truncate(s, n) when is_binary(s) and byte_size(s) > n, do: binary_part(s, 0, n)
  defp truncate(s, _) when is_binary(s), do: s
  defp truncate(_, _), do: nil
end

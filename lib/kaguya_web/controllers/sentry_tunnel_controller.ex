defmodule KaguyaWeb.SentryTunnelController do
  @moduledoc """
  Same-origin proxy for Sentry browser envelopes — bypasses adblockers
  that filter `*.ingest.sentry.io`.

  The browser SDK
  POSTs envelopes here (Content-Type: `application/x-sentry-envelope`);
  this controller extracts the embedded DSN from the envelope header,
  validates it matches our configured `:sentry_browser` DSN (so we're
  not an open relay), and forwards the raw body to Sentry's ingest
  endpoint via the existing Finch pool.

  Envelope format (line-delimited JSON):

      {"event_id":"…","sent_at":"…","dsn":"https://<key>@<host>/<project>"}
      {"type":"event","length":N}
      <event JSON>
      …
  """

  use KaguyaWeb, :controller
  require Logger

  # Sentry envelopes can include Replay attachments. Keep this generous
  # but bounded so a single malicious POST can't OOM us.
  @max_envelope_bytes 5_000_000

  def tunnel(conn, _params) do
    with {:ok, body, conn} <- read_envelope(conn),
         {:ok, dsn} <- extract_dsn(body),
         :ok <- validate_dsn(dsn),
         {:ok, url} <- envelope_url(dsn) do
      forward(conn, url, body)
    else
      {:error, reason} ->
        Logger.warning("sentry tunnel rejected",
          event_type: "SENTRY_TUNNEL_REJECT",
          operation: "sentry.tunnel",
          reason: to_string(reason)
        )

        send_resp(conn, 400, "")
    end
  end

  # ── Body read ────────────────────────────────────────────────────────

  defp read_envelope(conn) do
    case Plug.Conn.read_body(conn, length: @max_envelope_bytes) do
      {:ok, body, conn} when byte_size(body) > 0 -> {:ok, body, conn}
      {:ok, "", _conn} -> {:error, :empty_body}
      {:more, _, _} -> {:error, :body_too_large}
      {:error, _} -> {:error, :body_read_failed}
    end
  end

  # ── DSN extraction + validation ──────────────────────────────────────

  defp extract_dsn(body) do
    with [header | _] <- String.split(body, "\n", parts: 2),
         {:ok, %{"dsn" => dsn}} when is_binary(dsn) <- Jason.decode(header) do
      {:ok, dsn}
    else
      _ -> {:error, :no_dsn_in_envelope}
    end
  end

  defp validate_dsn(dsn) do
    case Application.get_env(:kaguya, :sentry_browser, [])[:dsn] do
      expected when is_binary(expected) and expected == dsn -> :ok
      _ -> {:error, :dsn_mismatch}
    end
  end

  # ── DSN → envelope URL ──────────────────────────────────────────────
  #
  # DSN: https://<public_key>@<host>/<project_id>
  # Envelope endpoint: https://<host>/api/<project_id>/envelope/?sentry_key=<public_key>

  defp envelope_url(dsn) do
    case URI.parse(dsn) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: "/" <> project,
        userinfo: key
      }
      when is_binary(scheme) and is_binary(host) and is_binary(key) and project != "" ->
        {:ok, "#{scheme}://#{host}:#{port}/api/#{project}/envelope/?sentry_key=#{key}"}

      _ ->
        {:error, :malformed_dsn}
    end
  end

  # ── Forward to Sentry ────────────────────────────────────────────────

  defp forward(conn, url, body) do
    request =
      Finch.build(
        :post,
        url,
        [{"content-type", "application/x-sentry-envelope"}],
        body
      )

    case Finch.request(request, Kaguya.Finch, receive_timeout: 5_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        send_resp(conn, status, "")

      {:ok, %{status: status}} ->
        # Sentry replies with 4xx/5xx — forward the status so the SDK retries / gives up.
        send_resp(conn, status, "")

      {:error, reason} ->
        Logger.warning("sentry tunnel forward failed",
          event_type: "SENTRY_TUNNEL_FORWARD_FAIL",
          operation: "sentry.tunnel",
          reason: inspect(reason)
        )

        send_resp(conn, 502, "")
    end
  end
end

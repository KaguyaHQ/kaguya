defmodule Kaguya.Observability.SentryFilter do
  @moduledoc """
  Drops noisy / non-actionable errors before they ship to Sentry, and applies
  per-event sampling so quota survives traffic spikes.

  Events tagged `critical=true` go through at 100%, everything else is
  sampled at `@general_sample_rate`.

  Wired in via `config :sentry, before_send: {Kaguya.Observability.SentryFilter, :before_send}`.
  """

  alias DBConnection.ConnectionError
  alias Sentry.Event
  alias Sentry.Interfaces.Request

  @general_sample_rate 0.25
  @db_pool_sample_rate 0.01
  @browse_db_pool_sample_rate 0.001
  @filtered "[Filtered]"

  # Exceptions that fire during normal request handling and aren't a code
  # bug — Phoenix raises NoRouteError on /not-a-real-path requests, the
  # parsers reject oversized bodies, and CSRF protection rejects stale
  # tokens. None of these are something a developer needs paged on.
  @ignored_exceptions [
    Phoenix.Router.NoRouteError,
    Phoenix.NotAcceptableError,
    Plug.Parsers.RequestTooLargeError,
    Plug.Parsers.UnsupportedMediaTypeError,
    Plug.CSRFProtection.InvalidCSRFTokenError,
    Plug.CSRFProtection.InvalidCrossOriginRequestError,
    Ecto.NoResultsError
  ]

  def before_send(%Event{} = event) do
    event = scrub_request(event)

    cond do
      ignored?(event) -> nil
      critical?(event) -> event
      db_pool_exhaustion_on_browse?(event) -> sample(event, @browse_db_pool_sample_rate)
      db_pool_exhaustion?(event) -> sample(event, @db_pool_sample_rate)
      :rand.uniform() > @general_sample_rate -> nil
      true -> event
    end
  end

  defp critical?(%Event{tags: tags}) when is_map(tags) do
    Map.get(tags, "critical") == "true" or Map.get(tags, :critical) == "true"
  end

  defp critical?(_), do: false

  defp ignored?(%Event{original_exception: %mod{}}), do: mod in @ignored_exceptions
  defp ignored?(_), do: false

  defp db_pool_exhaustion_on_browse?(%Event{} = event) do
    db_pool_exhaustion?(event) and browse_request?(event)
  end

  defp db_pool_exhaustion?(%Event{original_exception: %ConnectionError{} = exception}) do
    connection_unavailable?(Exception.message(exception))
  end

  defp db_pool_exhaustion?(%Event{exception: exceptions}) when is_list(exceptions) do
    Enum.any?(exceptions, fn
      %{type: "DBConnection.ConnectionError", value: value} when is_binary(value) ->
        connection_unavailable?(value)

      %{type: "Elixir.DBConnection.ConnectionError", value: value} when is_binary(value) ->
        connection_unavailable?(value)

      _other ->
        false
    end)
  end

  defp db_pool_exhaustion?(_event), do: false

  defp connection_unavailable?(message) do
    String.contains?(message, "connection not available") and
      String.contains?(message, "request was dropped from queue")
  end

  defp browse_request?(%Event{request: %Request{url: url}}) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: "/browse"} -> true
      _other -> false
    end
  end

  defp browse_request?(%Event{tags: tags}) when is_map(tags) do
    Map.get(tags, "request_path") == "/browse" or Map.get(tags, :request_path) == "/browse"
  end

  defp browse_request?(_event), do: false

  defp sample(%Event{} = event, rate) do
    if sampled?(event, rate), do: event, else: nil
  end

  defp sampled?(%Event{event_id: event_id}, rate) when is_binary(event_id) do
    threshold = trunc(rate * 10_000)

    event_id
    |> :erlang.phash2(10_000)
    |> Kernel.<(threshold)
  end

  defp sampled?(_event, rate), do: :rand.uniform() <= rate

  defp scrub_request(%Event{request: %Request{} = request} = event) do
    %{
      event
      | request: %{
          request
          | data: scrub_value(request.data),
            query_string: scrub_query_string(request.query_string)
        }
    }
  end

  defp scrub_request(event), do: event

  defp scrub_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key) do
        {key, @filtered}
      else
        {key, scrub_value(value)}
      end
    end)
  end

  defp scrub_value(values) when is_list(values) do
    Enum.map(values, fn
      {key, value} when is_binary(key) or is_atom(key) ->
        if sensitive_key?(key), do: {key, @filtered}, else: {key, scrub_value(value)}

      value ->
        scrub_value(value)
    end)
  end

  defp scrub_value(value), do: value

  defp scrub_query_string(query_string) when is_binary(query_string) do
    Regex.replace(
      ~r/((?:^|&)(?:[^=&]*)(?:email|password|token|secret|csrf)(?:[^=&]*)=)[^&]*/i,
      query_string,
      "\\1#{@filtered}"
    )
  end

  defp scrub_query_string(query_string), do: scrub_value(query_string)

  defp sensitive_key?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(fn key ->
      String.contains?(key, "email") or
        String.contains?(key, "password") or
        String.contains?(key, "token") or
        String.contains?(key, "secret") or
        String.contains?(key, "csrf")
    end)
  end
end

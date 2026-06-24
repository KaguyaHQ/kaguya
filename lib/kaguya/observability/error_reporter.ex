defmodule Kaguya.Observability.ErrorReporter do
  @moduledoc """
  Single entry point for reporting errors to Sentry with a consistent
  tag/extra shape.

  Replaces ad-hoc `Sentry.capture_exception(_, extra: %{...})` boilerplate
  scattered through workers, plugs, and resolvers. Direct port of
  `../personal/legacy-next-app/src/lib/errors/reporter.ts` so the Next.js and Phoenix
  surfaces share field names ("operation", "resource_id", "critical").

  ## Usage

      Kaguya.Observability.ErrorReporter.report(error,
        operation: "vn.merge",
        resource_type: "visual_novel",
        resource_id: vn.id,
        critical: true,
        metadata: %{canonical_id: canonical_id}
      )

  Callers that have a stacktrace (typically inside a `rescue` block)
  should pass `stacktrace: __STACKTRACE__` so Sentry symbolicates the
  frame instead of pointing at this module.

  Events tagged `critical: true` bypass the sample rate filter in
  `Kaguya.Observability.SentryFilter`.
  """

  @type opt ::
          {:operation, String.t()}
          | {:resource_type, String.t() | nil}
          | {:resource_id, term()}
          | {:critical, boolean()}
          | {:metadata, map()}
          | {:stacktrace, Exception.stacktrace()}

  def report(error, opts) when is_list(opts) do
    operation = Keyword.fetch!(opts, :operation)
    metadata = Keyword.get(opts, :metadata, %{})
    resource_id = Keyword.get(opts, :resource_id)
    resource_type = Keyword.get(opts, :resource_type)
    critical = Keyword.get(opts, :critical, false)
    stacktrace = Keyword.get(opts, :stacktrace)

    tags =
      %{"operation" => operation, "critical" => to_string(critical)}
      |> maybe_put("resource_type", resource_type)

    extras =
      metadata
      |> Map.new()
      |> maybe_put(:resource_id, resource_id)

    capture_opts =
      [tags: tags, extra: extras]
      |> maybe_put_kw(:stacktrace, stacktrace)

    do_capture(error, capture_opts)
    :ok
  end

  defp do_capture(%_{__exception__: true} = exception, opts) do
    Sentry.capture_exception(exception, opts)
  end

  defp do_capture(message, opts) when is_binary(message) do
    Sentry.capture_message(message, [level: :error] ++ opts)
  end

  defp do_capture(other, opts) do
    Sentry.capture_message(inspect(other), [level: :error] ++ opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_kw(kw, _key, nil), do: kw
  defp maybe_put_kw(kw, key, value), do: Keyword.put(kw, key, value)
end

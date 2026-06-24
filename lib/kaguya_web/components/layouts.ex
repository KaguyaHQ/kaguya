defmodule KaguyaWeb.Layouts do
  use KaguyaWeb, :html

  embed_templates "layouts/*"

  @doc """
  Returns a value from the `:sentry_browser` runtime config or nil.

  Populated by `config/runtime.exs` from env vars (`SENTRY_BROWSER_DSN`,
  `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE`). Surfaced as meta tags in
  `root.html.heex` and consumed by `assets/js/sentry.js`.

  Missing keys collapse to nil — the JS init bails when `dsn` is nil,
  so omitting the env var in dev is a clean no-op.
  """
  def sentry_browser_meta(key) do
    case Application.get_env(:kaguya, :sentry_browser, [])[key] do
      v when is_binary(v) and v != "" -> v
      _ -> nil
    end
  end

  # Encoded once at compile time — the WebSite JSON-LD payload is static and
  # rendered on every page for SEO parity with the Next.js root layout.
  @website_json_ld KaguyaWeb.SEO.encode(KaguyaWeb.SEO.JsonLd.website())

  @doc "Returns the root WebSite JSON-LD as an encoded JSON string."
  def website_json_ld, do: @website_json_ld
end

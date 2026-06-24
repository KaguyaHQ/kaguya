defmodule KaguyaWeb.DumpsLive.Index do
  @moduledoc """
  Public database dump download page.

  Reads the published archive listing directly from
  `Kaguya.PublicDump.Publisher`.
  """

  use KaguyaWeb, :live_view

  alias Kaguya.PublicDump.Publisher

  @retention 3

  @impl true
  def mount(_params, _session, socket) do
    payload =
      case publisher().list_published() do
        {:ok, payload} -> payload
        {:error, _reason} -> %{latest: nil, past: []}
      end

    {:ok,
     socket
     |> assign(:page_title, "Database Dump")
     |> assign(:meta_description, "Download a snapshot of Kaguya's public database.")
     |> assign(:latest, Map.get(payload, :latest))
     |> assign(:older, payload |> Map.get(:past, []) |> Enum.take(@retention - 1))
     |> assign(:retention, @retention)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-6 mb-16 w-full max-w-[75ch] px-5 sm:mt-16 sm:mb-32 sm:px-8">
      <h1 class="text-foreground-primary mb-6 text-2xl font-semibold sm:text-3xl">
        Database Dump
      </h1>

      <p :if={!@latest} class="text-foreground-secondary">
        No dump is currently available. Publishes run every Sunday 00:00 UTC.
      </p>

      <div
        :if={@latest}
        class="bg-surface-elevated border-border-divider mb-6 rounded-[8px] border p-5"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <code class="text-foreground-primary truncate text-sm font-medium">
            {archive_field(@latest, :filename)}
          </code>
          <span class="text-foreground-tertiary text-xs whitespace-nowrap">
            {format_bytes(archive_field(@latest, :size))} &middot; {format_datetime(
              archive_field(@latest, :last_modified)
            )}
          </span>
        </div>

        <a
          href={archive_field(@latest, :url)}
          download={archive_field(@latest, :filename)}
          rel="noopener"
          class="bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand text-style-body2Medium mt-4 inline-flex h-10 w-full items-center justify-center rounded-[8px] px-4 transition sm:w-auto"
        >
          Download
        </a>
      </div>

      <div :if={@older != []} class="mb-6">
        <h2 class="text-foreground-secondary mb-2 text-xs font-medium tracking-wider uppercase">
          Older versions
        </h2>
        <ul class="space-y-1.5">
          <li :for={archive <- @older} class="flex items-baseline justify-between gap-3">
            <a
              href={archive_field(archive, :url)}
              download={archive_field(archive, :filename)}
              rel="noopener"
              class="text-foreground-primary truncate underline-offset-2 hover:underline"
            >
              <code class="text-xs">{archive_field(archive, :filename)}</code>
            </a>
            <span class="text-foreground-tertiary text-xs whitespace-nowrap">
              {format_bytes(archive_field(archive, :size))}
            </span>
          </li>
        </ul>
      </div>

      <p class="text-foreground-tertiary mt-6 text-xs/relaxed">
        Refreshed every Sunday 00:00 UTC. We keep the last {@retention} weekly
        archives. Database structure under
        <a
          href="https://opendatacommons.org/licenses/odbl/1.0/"
          class="underline-offset-2 hover:underline"
          rel="noopener"
        >
          ODbL
        </a>
        , records under
        <a
          href="https://opendatacommons.org/licenses/dbcl/1.0/"
          class="underline-offset-2 hover:underline"
          rel="noopener"
        >
          DbCL
        </a>
        . Catalog data partly derived from
        <a
          href="https://vndb.org/d14"
          class="underline-offset-2 hover:underline"
          rel="noopener"
        >
          VNDB.org
        </a>
        . See <code>README.txt</code>
        + <code>import.sql</code>
        inside the archive
        for full instructions.
      </p>
    </div>
    """
  end

  defp publisher, do: Application.get_env(:kaguya, :public_dump_publisher, Publisher)

  defp archive_field(archive, key) when is_map(archive) do
    Map.get(archive, key) || Map.get(archive, to_string(key))
  end

  defp format_bytes(nil), do: "-"

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 0) |> trunc()} KiB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 0) |> trunc()} MiB"
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    "#{:erlang.float_to_binary(bytes / (1024 * 1024 * 1024), decimals: 2)} GiB"
  end

  defp format_bytes(bytes) when is_binary(bytes) do
    bytes
    |> String.to_integer()
    |> format_bytes()
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> format_datetime(datetime)
      _ -> "-"
    end
  end
end

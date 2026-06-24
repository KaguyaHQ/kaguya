defmodule Kaguya.Sitemaps.Publisher do
  @moduledoc """
  Publishes generated sitemap XML to R2.
  """

  require Logger

  alias ExAws.S3
  alias Kaguya.Sitemaps

  @key_prefix "sitemaps/"
  @public_url_base "https://images.kaguya.io"
  @cache_control "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800"

  @doc "Public URL for a sitemap object in R2."
  def public_url(filename), do: @public_url_base <> "/" <> key_for(filename)

  @doc """
  Generate and publish sitemap files.

  Options:
    * `:mode` - `:full` or `:user_content` (default: `:full`)
    * `:dry_run` - generate and log, but do not upload
  """
  def run(opts \\ []) do
    mode = Keyword.get(opts, :mode, :full)
    dry_run? = Keyword.get(opts, :dry_run, false)
    types = types_for_mode(mode)
    generated = Sitemaps.generate(types)

    Logger.info("Sitemaps.Publisher: generated #{map_size(generated)} chunk files",
      mode: mode,
      dry_run: dry_run?
    )

    if dry_run? do
      :ok
    else
      publish(generated, types)
    end
  end

  defp publish(generated, types) do
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    with {:ok, existing} <- list_existing_chunks(bucket),
         :ok <- upload_chunks(generated, bucket),
         :ok <- delete_stale_chunks(existing, generated, types, bucket) do
      final_chunks =
        existing
        |> MapSet.difference(stale_chunk_names(existing, generated, types))
        |> MapSet.union(MapSet.new(Map.keys(generated)))
        |> MapSet.to_list()

      index = Sitemaps.render_index(final_chunks)

      with {:ok, _} <- upload("sitemap.xml", index, bucket) do
        Logger.info("Sitemaps.Publisher: published sitemap index",
          chunks: length(final_chunks),
          url: public_url("sitemap.xml")
        )

        :ok
      end
    end
  end

  defp types_for_mode(:full), do: Sitemaps.all_types()
  defp types_for_mode("full"), do: Sitemaps.all_types()
  defp types_for_mode(:user_content), do: Sitemaps.user_content_types()
  defp types_for_mode("user_content"), do: Sitemaps.user_content_types()

  defp types_for_mode(other) do
    raise ArgumentError, "unknown sitemap publish mode: #{inspect(other)}"
  end

  defp upload_chunks(generated, bucket) do
    Enum.reduce_while(generated, :ok, fn {filename, xml}, :ok ->
      case upload(filename, xml, bucket) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upload(filename, xml, bucket) do
    Logger.info("Sitemaps.Publisher: uploading #{key_for(filename)}")

    bucket
    |> S3.put_object(key_for(filename), xml,
      content_type: "application/xml",
      cache_control: @cache_control
    )
    |> ExAws.request()
  end

  defp delete_stale_chunks(existing, generated, types, bucket) do
    stale = stale_chunk_names(existing, generated, types)

    Enum.each(stale, fn filename ->
      Logger.info("Sitemaps.Publisher: deleting stale #{key_for(filename)}")
      _ = bucket |> S3.delete_object(key_for(filename)) |> ExAws.request()
    end)

    :ok
  end

  defp stale_chunk_names(existing, generated, types) do
    generated_names = generated |> Map.keys() |> MapSet.new()
    selected_prefixes = Enum.map(types, &"#{&1}-")

    existing
    |> Enum.filter(fn filename ->
      Enum.any?(selected_prefixes, &String.starts_with?(filename, &1)) and
        not MapSet.member?(generated_names, filename)
    end)
    |> MapSet.new()
  end

  defp list_existing_chunks(bucket) do
    case bucket |> S3.list_objects_v2(prefix: @key_prefix) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        chunks =
          contents
          |> Enum.map(&Path.basename(&1.key))
          |> Enum.filter(&(&1 != "sitemap.xml" and Sitemaps.valid_chunk_filename?(&1)))
          |> MapSet.new()

        {:ok, chunks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp key_for(filename), do: @key_prefix <> filename
end

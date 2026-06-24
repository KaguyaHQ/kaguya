defmodule KaguyaWeb.BrowseLive.TagSnapshot do
  @moduledoc """
  Read-mostly snapshot of the browse tag vocabulary, cached in `:persistent_term`.

  The single source of truth is the database: `Kaguya.VNTags.list_vn_tags/0`
  returns every tag with at least one non-spoiler, non-overruled VN vote,
  ordered by popularity. This module shapes that into the JSON the browse tag
  picker fetches, derives a content-hashed asset path for immutable caching,
  and computes a sexual-tag-filtered variant for browse surfaces.

  The snapshot is built lazily on first read and held in `:persistent_term`
  for fast concurrent reads. It is rebuilt by `invalidate/0`, called from the
  dump-sync post-sync step whenever tags change, so it never drifts from the DB.
  """

  alias Kaguya.VNTags

  @key {__MODULE__, :snapshot}

  def list(opts \\ []) do
    case Keyword.get(opts, :include_sexual, false) do
      true -> snapshot().tags
      false -> snapshot().filtered_tags
    end
  end

  def find(slug) do
    slug = to_string(slug)
    Enum.find(snapshot().tags, &(Map.get(&1, "slug") == slug))
  end

  def title(slug) do
    case find(slug) do
      nil -> humanize_slug(slug)
      tag -> Map.get(tag, "name") || humanize_slug(slug)
    end
  end

  def asset_path, do: snapshot().asset_path
  def asset_body, do: snapshot().asset_body
  def asset_hash, do: snapshot().asset_hash

  @doc """
  Drops the cached snapshot so the next read rebuilds it from the DB.
  Called after the dump sync changes tags.
  """
  def invalidate do
    :persistent_term.erase(@key)
    :ok
  end

  defp snapshot do
    :persistent_term.get(@key, nil) || load_snapshot()
  end

  # The whole vocabulary (~hundreds of tags) is held in one persistent_term
  # entry. Comfortably under the OTP term-size ceiling at current corpus size.
  defp load_snapshot do
    {:ok, rows} = VNTags.list_vn_tags()
    tags = Enum.map(rows, &to_tag_map/1)
    filtered_tags = Enum.reject(tags, &sexual?/1)
    body = filtered_tags |> Jason.encode_to_iodata!() |> IO.iodata_to_binary()

    hash =
      body
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    snapshot = %{
      tags: tags,
      filtered_tags: filtered_tags,
      asset_body: body,
      asset_hash: hash,
      asset_path: "/data/#{hash}/vn-tags.json"
    }

    :persistent_term.put(@key, snapshot)
    snapshot
  end

  # Shapes a DB row into the JSON map the frontend tag picker consumes. Enum
  # atoms (:content, :meta) become the uppercase strings the picker expects.
  # `id` is intentionally omitted — the frontend keys off slug/name only.
  defp to_tag_map(row) do
    %{
      "name" => row.name,
      "slug" => row.slug,
      "category" => upcase_enum(row.category),
      "kind" => upcase_enum(row.kind),
      "contentWarning" => row.content_warning || false,
      "vnsCount" => row.vns_count
    }
  end

  defp upcase_enum(nil), do: nil
  defp upcase_enum(atom), do: atom |> Atom.to_string() |> String.upcase()

  defp sexual?(tag) do
    Map.get(tag, "category") == "SEXUAL" or Map.get(tag, "kind") == "SEXUAL"
  end

  defp humanize_slug(slug) do
    slug
    |> to_string()
    |> String.split("-", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

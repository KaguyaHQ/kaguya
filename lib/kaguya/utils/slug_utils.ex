defmodule Kaguya.Utils.SlugUtils do
  @moduledoc false
  # Collision-free, pretty slugs for bulk imports.

  import Ecto.Query
  alias Kaguya.Repo

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Builds unique slugs for a list of items, checking for collisions in the DB.

  Each item is a map. `key_fun` extracts the string to slugify (e.g. `& &1.title`).
  Returns items with a `:_slug` key containing the unique slug.

  ## Options

    * `:year_fun` - when provided, extracts a year (integer or nil) from each item.
      Collisions are resolved as `base-year`, then `base-year-1`, etc. instead of
      `base-1`, `base-2`. Items without a year fall back to numeric suffixes.
  """
  def build_unique_slugs(items, schema, slug_field, key_fun, opts \\ [])
      when is_list(items) and is_atom(slug_field) do
    year_fun = Keyword.get(opts, :year_fun)

    # 1) Precompute each item's "base" and optional year
    pairs =
      for itm <- items do
        base =
          itm
          |> key_fun.()
          |> Slug.slugify(truncate: 45)
          |> root_slug()

        year = if year_fun, do: year_fun.(itm)
        {itm, base, year}
      end

    bases = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    if year_fun do
      # Year-based slug assignment: fetch all existing slugs matching any base
      existing = fetch_existing_slug_set(schema, slug_field, bases)

      {out, _taken} =
        Enum.map_reduce(pairs, existing, fn {itm, base, year}, taken ->
          slug = pick_year_slug(base, year, taken)

          updated =
            itm
            |> Map.put(:_slug, slug)
            |> Map.put(:_slug_base, base)

          {updated, MapSet.put(taken, slug)}
        end)

      ensure_db_uniqueness(out, schema, slug_field)
    else
      # Original counter-based assignment (for characters, producers, tags, etc.)
      counters = fetch_slug_counters(schema, slug_field, bases)

      {out, _} =
        Enum.map_reduce(pairs, %{}, fn {itm, base, _year}, acc ->
          first_free = Map.get(counters, base, -1) + 1
          suffix_index = Map.get(acc, base, first_free)
          slug = if suffix_index == 0, do: base, else: "#{base}-#{suffix_index}"

          updated =
            itm
            |> Map.put(:_slug, slug)
            |> Map.put(:_slug_base, base)

          {updated, Map.put(acc, base, suffix_index + 1)}
        end)

      ensure_db_uniqueness(out, schema, slug_field)
    end
  end

  # ---------------------------------------------------------------------------
  # Year-based slug helpers
  # ---------------------------------------------------------------------------

  defp pick_year_slug(base, year, taken) do
    if MapSet.member?(taken, base) do
      if year do
        year_slug = "#{base}-#{year}"

        if MapSet.member?(taken, year_slug) do
          n =
            Stream.iterate(1, &(&1 + 1))
            |> Enum.find(fn n -> not MapSet.member?(taken, "#{year_slug}-#{n}") end)

          "#{year_slug}-#{n}"
        else
          year_slug
        end
      else
        # No year available — numeric fallback
        n =
          Stream.iterate(1, &(&1 + 1))
          |> Enum.find(fn n -> not MapSet.member?(taken, "#{base}-#{n}") end)

        "#{base}-#{n}"
      end
    else
      base
    end
  end

  defp fetch_existing_slug_set(_schema, _field, []), do: MapSet.new()

  defp fetch_existing_slug_set(schema, field, bases) do
    # Match exact base slugs and any slug starting with "base-"
    dash_patterns = Enum.map(bases, &(&1 <> "-%"))

    schema
    |> where(
      [s],
      field(s, ^field) in ^bases or
        fragment("? LIKE ANY(?::text[])", field(s, ^field), ^dash_patterns)
    )
    |> select([s], field(s, ^field))
    |> Repo.all()
    |> MapSet.new()
  end

  # -------------------------------------------------
  # "flight-12-3" → "flight-12"
  # "flight-12"   → "flight-12"   (title really ends in 12)
  # "flight"      → "flight"
  @digits_regex ~r/^\d+$/

  defp root_slug(nil), do: "item"
  defp root_slug(""), do: "item"

  defp root_slug(slug) do
    parts = String.split(slug, "-")

    # Only treat the last `-<digits>` as a generated uniqueness suffix when the slug already
    # ends in a numeric segment *and* the preceding segment is also numeric.
    #
    # This preserves meaningful numeric titles like:
    #   "steins-gate-0"   (title ends in 0)  => stays "steins-gate-0"
    #   "flight-12"       (title ends in 12) => stays "flight-12"
    #
    # While still treating generated suffixes like:
    #   "flight-12-3"     (3 is the collision suffix) => root becomes "flight-12"
    if length(parts) >= 3 and List.last(parts) =~ @digits_regex and
         Enum.at(parts, -2) =~ @digits_regex do
      parts |> Enum.drop(-1) |> Enum.join("-")
    else
      slug
    end
  end

  # ---------------------------------------------------------------------------
  # Counter-based helpers (original numeric suffix approach)
  # ---------------------------------------------------------------------------
  defp fetch_slug_counters(_schema, _field, []), do: %{}

  defp fetch_slug_counters(schema, field, bases) when is_list(bases) do
    patterns = Enum.map(bases, &(&1 <> "%"))

    query =
      from(s in schema,
        where: fragment("? LIKE ANY(?::text[])", field(s, ^field), ^patterns),
        where:
          fragment(
            """
            CASE
              WHEN ? ~ '-[0-9]+$'
              THEN regexp_replace(?, '-[0-9]+$','')
              ELSE ?
            END = ANY(?::text[])
            """,
            field(s, ^field),
            field(s, ^field),
            field(s, ^field),
            ^bases
          ),
        group_by:
          fragment(
            """
            CASE
              WHEN ? ~ '-[0-9]+$'
              THEN regexp_replace(?, '-[0-9]+$','')
              ELSE ?
            END
            """,
            field(s, ^field),
            field(s, ^field),
            field(s, ^field)
          ),
        select: {
          fragment(
            """
            CASE
              WHEN ? ~ '-[0-9]+$'
              THEN regexp_replace(?, '-[0-9]+$','')
              ELSE ?
            END
            """,
            field(s, ^field),
            field(s, ^field),
            field(s, ^field)
          ),
          fragment(
            """
            COALESCE(
              MAX(
                CASE
                  WHEN ? ~ '-[0-9]+$'
                  THEN substring(?, '-([0-9]+)$')::int
                  ELSE 0
                END
              ),
              0
            )
            """,
            field(s, ^field),
            field(s, ^field)
          )
        }
      )

    Repo.all(query)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # DB uniqueness safety net (handles race conditions)
  # ---------------------------------------------------------------------------
  defp ensure_db_uniqueness(items, _schema, _field) when items == [], do: []

  defp ensure_db_uniqueness(items, schema, field) do
    slugs =
      items
      |> Enum.map(&Map.get(&1, :_slug))
      |> Enum.reject(&is_nil/1)

    existing_slugs =
      if slugs == [] do
        MapSet.new()
      else
        schema
        |> where([s], field(s, ^field) in ^slugs)
        |> select([s], field(s, ^field))
        |> Repo.all()
        |> MapSet.new()
      end

    {final, _taken, _next_per_base} =
      Enum.reduce(items, {[], existing_slugs, %{}}, fn item, {acc, taken, next_per_base} ->
        {slug, taken, next_per_base} = reserve_slug(item, taken, next_per_base)
        {[%{item | _slug: slug} | acc], taken, next_per_base}
      end)

    final
    |> Enum.reverse()
    |> Enum.map(&Map.delete(&1, :_slug_base))
  end

  defp reserve_slug(%{_slug: slug} = item, taken, next_per_base) do
    cond do
      is_nil(slug) ->
        base = Map.get(item, :_slug_base)
        {base, taken, next_per_base}

      not MapSet.member?(taken, slug) ->
        {slug, MapSet.put(taken, slug), next_per_base}

      true ->
        base = Map.get(item, :_slug_base) || root_slug(slug)

        start_index =
          case Map.get(next_per_base, base) do
            nil ->
              case slug_suffix(slug) do
                nil -> 1
                suffix -> suffix + 1
              end

            value ->
              value
          end

        {new_slug, taken, next_index} = next_available_slug(base, start_index, taken)
        {new_slug, taken, Map.put(next_per_base, base, next_index)}
    end
  end

  defp next_available_slug(base, index, taken) do
    candidate =
      case index do
        0 -> base
        _ -> "#{base}-#{index}"
      end

    cond do
      candidate in [nil, ""] ->
        {candidate, taken, index + 1}

      MapSet.member?(taken, candidate) ->
        next_available_slug(base, index + 1, taken)

      true ->
        {candidate, MapSet.put(taken, candidate), index + 1}
    end
  end

  defp slug_suffix(nil), do: nil

  defp slug_suffix(slug) do
    slug
    |> String.split("-")
    |> List.last()
    |> case do
      nil ->
        nil

      part ->
        case Integer.parse(part) do
          {int, ""} -> int
          _ -> nil
        end
    end
  end
end

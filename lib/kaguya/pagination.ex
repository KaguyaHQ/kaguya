defmodule Kaguya.Pagination do
  import Ecto.Query, only: [limit: 2, offset: 2]
  alias Kaguya.Repo

  @max_pages 100
  @max_page_size 200

  @doc """
  Paginates an Ecto query.

  - `query`: The Ecto query to paginate.
  - `page`: The current page.
  - `page_size`: How many items per page.
  - `total_count`:
    - `nil` (default) — count is deferred; the query is attached to the
      pagination meta so `resolve_count/1` can resolve it lazily. No COUNT
      query runs unless the caller asks for it.
    - An integer — used as-is (pre-calculated count).
    - `:skip` — no count, no query attached. `total_count` / `total_pages`
      will be nil.

  Returns a tuple of `{items, pagination}`.
  """
  def paginate(query, page, page_size, total_count \\ nil) do
    page_size = page_size |> max(1) |> min(@max_page_size)

    case total_count do
      :skip -> paginate_without_count(query, page, page_size)
      n when is_integer(n) -> paginate_with_count(query, page, page_size, n)
      nil -> paginate_lazy(query, page, page_size)
    end
  end

  # Count is known upfront — clamp page and return.
  defp paginate_with_count(query, page, page_size, total_count) do
    total_pages = div(total_count + page_size - 1, page_size)
    total_pages = min(total_pages, @max_pages)

    page = max(min(page, total_pages), 1)
    offset = (page - 1) * page_size

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {items,
     %{
       page: page,
       page_size: page_size,
       total_pages: total_pages,
       total_count: total_count
     }}
  end

  # Count deferred — attach the query so callers can resolve lazily.
  # A unique ref is stored so resolve_count/resolve_total_pages can share one
  # DB call via process-dictionary memoization (cleaned up when the request ends).
  defp paginate_lazy(query, page, page_size) do
    page = max(page, 1)
    offset = (page - 1) * page_size

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {items,
     %{
       page: page,
       page_size: page_size,
       total_pages: nil,
       total_count: nil,
       _count_query: query,
       _count_ref: make_ref()
     }}
  end

  # Explicitly skipped — no count, no query.
  defp paginate_without_count(query, page, page_size) do
    page = max(page, 1)
    offset = (page - 1) * page_size

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    {items,
     %{
       page: page,
       page_size: page_size,
       total_pages: nil,
       total_count: nil
     }}
  end

  @doc """
  Resolves a deferred total_count.
  """
  def resolve_count(%{total_count: n}) when is_integer(n), do: n
  def resolve_count(%{_count_query: _} = meta), do: lazy_count(meta)
  def resolve_count(_), do: nil

  @doc """
  Resolves a deferred total_pages.
  """
  def resolve_total_pages(%{total_pages: n}) when is_integer(n), do: n

  def resolve_total_pages(%{_count_query: _, page_size: page_size} = meta) do
    count = lazy_count(meta)
    div(count + page_size - 1, page_size) |> min(@max_pages)
  end

  def resolve_total_pages(_), do: nil

  # Memoize the count per pagination result so resolve_count and
  # resolve_total_pages share a single DB call within the same request.
  defp lazy_count(%{_count_ref: ref, _count_query: query}) do
    case Process.get(ref) do
      nil ->
        count = safe_count(query)
        Process.put(ref, count)
        count

      count ->
        count
    end
  end

  defp lazy_count(%{_count_query: query}), do: safe_count(query)

  # Safely count rows
  defp safe_count(query) do
    Repo.aggregate(query, :count, :id)
  rescue
    _ -> Repo.aggregate(query, :count)
  end
end

defmodule Kaguya.CursorPagination do
  @moduledoc """
  Cursor-based pagination helpers.

  * `paginate_by_cursor/5` – low-level, expects a typed cursor value (or tuple)
  * `paginate/6`          – high-level: raw cursor string in, encoded string out
  * `encode_cursor/1` / `decode_cursor/2` – helpers you can reuse elsewhere
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Decimal

  @max_page_size 64
  @sep "|"

  @type field_type :: :datetime | :int | :decimal | :float | :string
  @type order_dir :: :asc | :desc

  # ────────────────────────────────────────────────────────────
  # Public High-Level API
  # ────────────────────────────────────────────────────────────

  @doc """
  High-level helper:

    - `fields`: [:last_activity_at, :series_id]
    - `types`:  [:datetime,       :int]
    - `raw_cursor`: what the client sent (string or nil)
    - returns `{items, next_cursor_string, has_next?}`

  Internally decodes the incoming cursor, runs `paginate_by_cursor/5`,
  then encodes the returned cursor.

  """
  def paginate(query, fields, types, raw_cursor, limit, order \\ :desc) do
    decoded = decode_cursor(raw_cursor, types)

    {rows, next_raw, has_next} =
      paginate_by_cursor(query, fields, decoded, limit, order)

    encoded = encode_cursor(next_raw)
    {rows, encoded, has_next}
  end

  # ────────────────────────────────────────────────────────────
  # Low-Level Core (unchanged behavior)
  # ────────────────────────────────────────────────────────────

  @doc """
  Paginates a query using cursor-based pagination.

  ## Parameters
  - query: The Ecto query or schema.
  - field_or_fields: Field(s) used as cursor (atom or list of two atoms).
  - cursor_value: Typed cursor (or tuple) or nil.
  - limit: Items per page.
  - order: :desc or :asc

  ## Returns
  `{items, next_cursor_value, has_next?}`

  For **cursor-based pagination to work correctly**:
  - The SQL query *must* be ordered **only** by the exact fields used for the cursor (`field_or_fields`), in the exact order and direction.
  - **Never add additional `order_by` clauses** outside this function, or reorder elsewhere, or you can get duplicates, skips, or inconsistent pages.
  - In other words: the paginator owns the ordering!
  If you want to paginate by a composite key like `[:gr_reviews_count, :series_id]`, both the query and the cursor must match this ordering, and no extra ordering should be added.
  Here, the sorting contract is strict: **ordering and cursor must always match!**
  """
  def paginate_by_cursor(
        query,
        field_or_fields \\ :inserted_at,
        cursor \\ nil,
        limit \\ 10,
        order \\ :desc
      ) do
    real_limit = clamp_limit(limit)

    rows =
      query
      |> add_filter(field_or_fields, cursor, order)
      |> add_order(field_or_fields, order)
      # fetch one extra row
      |> limit(^(real_limit + 1))
      |> Repo.all()

    {page_items, extra} = Enum.split(rows, real_limit)
    has_next = extra != []

    next_cursor =
      if has_next and page_items != [] do
        extract_cursor_value(List.last(page_items), field_or_fields)
      else
        nil
      end

    {page_items, next_cursor, has_next}
  end

  # ────────────────────────────────────────────────────────────
  # Encode / Decode helpers
  # ────────────────────────────────────────────────────────────

  @doc """
  Encode a single value or a 2-tuple into a string cursor.

  Accepted:
    * nil
    * value
    * {v1, v2}
  """
  def encode_cursor(nil), do: nil
  def encode_cursor({a, b}), do: Enum.join([to_token(a), to_token(b)], @sep)
  def encode_cursor(v), do: to_token(v)

  @doc """
  Decode a raw cursor string into a value or 2-tuple matching `types`.

  `types` must be either:
    * [:type]            → returns a single value
    * [:type1, :type2]   → returns {v1, v2}

  Returns `nil` on parse errors.
  """
  def decode_cursor(nil, _), do: nil
  def decode_cursor("", _), do: nil

  def decode_cursor(raw, [t1]) do
    with {:ok, v1} <- from_token(raw, t1) do
      v1
    else
      _ -> nil
    end
  end

  def decode_cursor(raw, [t1, t2]) do
    case String.split(raw, @sep, parts: 2) do
      [p1, p2] ->
        with {:ok, v1} <- from_token(p1, t1),
             {:ok, v2} <- from_token(p2, t2) do
          {v1, v2}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Extend easily if you ever support >2 fields.
  def decode_cursor(_raw, _types), do: raise("Only 1 or 2-field cursors supported")

  # ────────────────────────────────────────────────────────────
  # Internal encode/decode pieces
  # ────────────────────────────────────────────────────────────

  defp to_token(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_token(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp to_token(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 15])
  defp to_token(i) when is_integer(i), do: Integer.to_string(i)
  defp to_token(s) when is_binary(s), do: s
  defp to_token(other), do: to_string(other)

  defp from_token(str, :datetime) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp from_token(str, :int) do
    case Integer.parse(str) do
      {i, ""} -> {:ok, i}
      _ -> :error
    end
  end

  defp from_token(str, :decimal) do
    case Decimal.parse(str) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  defp from_token(str, :float) do
    case Float.parse(str) do
      {f, ""} -> {:ok, f}
      _ -> :error
    end
  end

  defp from_token(str, :string), do: {:ok, str}

  # ────────────────────────────────────────────────────────────
  # Filtering helpers
  # ────────────────────────────────────────────────────────────

  defp add_filter(query, _field, nil, _order), do: query

  # single-field
  defp add_filter(query, field, cursor, :desc) when is_atom(field) do
    from(q in query, where: field(q, ^field) < ^cursor)
  end

  defp add_filter(query, field, cursor, :asc) when is_atom(field) do
    from(q in query, where: field(q, ^field) > ^cursor)
  end

  # composite (2-field) cursor
  defp add_filter(query, [f1, f2], {c1, c2}, :desc) do
    from(q in query,
      where: field(q, ^f1) < ^c1 or (field(q, ^f1) == ^c1 and field(q, ^f2) < ^c2)
    )
  end

  defp add_filter(query, [f1, f2], {c1, c2}, :asc) do
    from(q in query,
      where: field(q, ^f1) > ^c1 or (field(q, ^f1) == ^c1 and field(q, ^f2) > ^c2)
    )
  end

  # ────────────────────────────────────────────────────────────
  # Ordering helpers
  # ────────────────────────────────────────────────────────────

  # single-field
  defp add_order(query, field, :desc) when is_atom(field) do
    order_by(query, [q], desc: field(q, ^field))
  end

  defp add_order(query, field, :asc) when is_atom(field) do
    order_by(query, [q], asc: field(q, ^field))
  end

  # composite (2-field)
  defp add_order(query, [f1, f2], :desc) do
    order_by(query, [q], desc: field(q, ^f1), desc: field(q, ^f2))
  end

  defp add_order(query, [f1, f2], :asc) do
    order_by(query, [q], asc: field(q, ^f1), asc: field(q, ^f2))
  end

  # ────────────────────────────────────────────────────────────
  # Cursor extraction
  # ────────────────────────────────────────────────────────────

  defp extract_cursor_value(item, field) when is_atom(field),
    do: Map.get(item, field)

  defp extract_cursor_value(item, [f1, f2]),
    do: {Map.get(item, f1), Map.get(item, f2)}

  # ────────────────────────────────────────────────────────────
  # Misc
  # ────────────────────────────────────────────────────────────

  defp clamp_limit(limit), do: limit |> max(1) |> min(@max_page_size)
end

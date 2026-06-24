defmodule Kaguya.PublicDump.SqlBuilder do
  @moduledoc """
  Builds `COPY (SELECT ...) TO STDOUT` queries from `Kaguya.PublicDump.Spec`s.

  Mirrors `export_table` in VNDB's `util/dbdump.pl` (lines 191–235): per-column
  rendering, automatic LEFT JOIN against `users` for FK columns (with
  CASE-NULL-on-deleted), `::date` truncation for timestamps, and a required
  ORDER BY for deterministic output (defaulting to the spec's primary key).
  """

  alias Kaguya.PublicDump.Spec

  @doc """
  Build the COPY query for a `Spec`. Returns a string ready for
  `Ecto.Adapters.SQL.stream/3` or `Repo.query!/2`.

  Synthesized specs (with `:sql` set) are wrapped verbatim. Regular specs
  drive a `SELECT cols FROM <name> x [JOINs] [WHERE …] ORDER BY …` build,
  with `order_by` defaulting to `primary_key` when not given.
  """
  def build(%Spec{sql: sql}) when is_binary(sql) do
    "COPY (\n#{String.trim_trailing(sql)}\n) TO STDOUT"
  end

  def build(%Spec{} = spec) do
    {select_list, joins} = render_columns(spec.columns)
    order_by = spec.order_by || spec.primary_key || raise_no_order(spec)
    table_name = spec.source_name || spec.name

    inner = """
    SELECT #{select_list}
      FROM #{table_name} x#{join_clause(joins)}#{where_clause(spec.where)}
     ORDER BY #{order_by}\
    """

    "COPY (\n#{inner}\n) TO STDOUT"
  end

  defp where_clause(nil), do: ""
  defp where_clause(""), do: ""
  defp where_clause(w), do: "\n WHERE #{String.trim_trailing(w)}"

  defp join_clause([]), do: ""
  defp join_clause(joins), do: "\n   " <> Enum.join(joins, "\n   ")

  defp raise_no_order(spec) do
    raise ArgumentError,
          "spec #{inspect(spec.name)} has neither :order_by nor :primary_key — at least one is required for deterministic output"
  end

  # ── column rendering ──────────────────────────────────────────────────────

  defp render_columns(cols) do
    {selects, joins} =
      Enum.reduce(cols, {[], []}, fn col, {sel_acc, join_acc} ->
        {sel, join} = render_column(col)
        {[sel | sel_acc], if(join, do: [join | join_acc], else: join_acc)}
      end)

    select_list = selects |> Enum.reverse() |> Enum.join(", ")
    joins = joins |> Enum.reverse() |> Enum.uniq()
    {select_list, joins}
  end

  defp render_column(name) when is_atom(name), do: {"x.#{name}", nil}

  defp render_column({name, :date}) do
    {"x.#{name}::date AS #{name}", nil}
  end

  defp render_column({name, :user_fk}) do
    alias_ = "u_#{name}"
    select = "CASE WHEN #{alias_}.username IS NULL THEN NULL ELSE #{alias_}.id END AS #{name}"
    join = "LEFT JOIN users #{alias_} ON #{alias_}.id = x.#{name}"
    {select, join}
  end

  defp render_column(other) do
    raise ArgumentError, "unrecognized column spec: #{inspect(other)}"
  end
end

defmodule Kaguya.PublicDump.SchemaWriter do
  @moduledoc """
  Generates `schema.sql` (CREATE TABLE statements) and `import.sql` (turnkey
  psql import script).

  Mirrors `export_schema/2` and `export_import_script/1` in VNDB's
  `util/dbdump.pl` (lines 238–322). Column types come from
  `information_schema` at run time — no drift between Ecto schemas and the
  dump schema. Primary keys and foreign keys come from each `Spec`; the
  fallback `lookup_column_types/2` overrides happen for transformed columns
  (`{name, :date}` → `date`, `{name, :user_fk}` → `uuid`).
  """

  alias Kaguya.PublicDump.Spec
  alias Kaguya.Repo

  @doc "Write `schema.sql` containing CREATE TABLE statements for the included specs."
  def write_schema(specs, path) do
    File.write!(path, render_schema(specs))
  end

  @doc "Write `import.sql` — the turnkey psql import script."
  def write_import(specs, path) do
    File.write!(path, render_import(specs))
  end

  # ── schema.sql ─────────────────────────────────────────────────────────────

  defp render_schema(specs) do
    Enum.map_join(specs, "\n\n", &render_create_table/1)
  end

  # entry_meta isn't a real table; column types come from us, not info_schema.
  defp render_create_table(%Spec{name: :entry_meta} = spec) do
    """
    CREATE TABLE entry_meta (
      entity_type text NOT NULL,
      entity_id uuid NOT NULL,
      created date NOT NULL,
      last_modified date NOT NULL,
      revision integer NOT NULL,
      num_edits integer NOT NULL,
      num_users integer NOT NULL,
      PRIMARY KEY (#{spec.primary_key})
    );\
    """
  end

  defp render_create_table(%Spec{} = spec) do
    source_name = spec.source_name || spec.name
    types = lookup_column_types(source_name, needed_columns(spec))

    col_defs =
      Enum.map_join(spec.columns, ",\n", fn col ->
        {col_name, override} = column_name_and_override(col)
        type = override || Map.fetch!(types, col_name)
        "  #{col_name} #{type}"
      end)

    pk_clause = if spec.primary_key, do: ",\n  PRIMARY KEY (#{spec.primary_key})", else: ""

    """
    CREATE TABLE #{spec.name} (
    #{col_defs}#{pk_clause}
    );\
    """
  end

  defp needed_columns(%Spec{columns: cols}) do
    cols
    |> Enum.map(fn
      name when is_atom(name) -> name
      {name, _} -> name
    end)
    |> MapSet.new()
  end

  defp column_name_and_override(name) when is_atom(name), do: {name, nil}
  defp column_name_and_override({name, :date}), do: {name, "date"}
  defp column_name_and_override({name, :user_fk}), do: {name, "uuid"}

  defp lookup_column_types(table_name, needed) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT column_name, data_type, udt_name
          FROM information_schema.columns
         WHERE table_name = $1
         ORDER BY ordinal_position
        """,
        [Atom.to_string(table_name)]
      )

    rows
    |> Enum.filter(fn [col, _, _] -> MapSet.member?(needed, String.to_atom(col)) end)
    |> Map.new(fn [col, data_type, udt] ->
      {String.to_atom(col), pg_type(data_type, udt, table_name)}
    end)
  end

  defp pg_type("ARRAY", udt, _table) do
    case udt do
      "_int4" -> "integer[]"
      "_int8" -> "bigint[]"
      "_int2" -> "smallint[]"
      "_text" -> "text[]"
      "_uuid" -> "uuid[]"
      "_varchar" -> "varchar[]"
      "_float4" -> "real[]"
      "_float8" -> "double precision[]"
      "_bool" -> "boolean[]"
      _ -> raise "unmapped array element udt: #{udt}"
    end
  end

  # Custom enum types stored as text in the dump (Postgres native enums are
  # non-portable and the application is the source of truth anyway).
  defp pg_type("USER-DEFINED", _udt, _), do: "text"
  defp pg_type("character varying", _, _), do: "text"
  defp pg_type("integer", _, _), do: "integer"
  defp pg_type("bigint", _, _), do: "bigint"
  defp pg_type("smallint", _, _), do: "smallint"
  defp pg_type("boolean", _, _), do: "boolean"
  defp pg_type("date", _, _), do: "date"
  defp pg_type("text", _, _), do: "text"
  defp pg_type("uuid", _, _), do: "uuid"
  defp pg_type("timestamp with time zone", _, _), do: "timestamp with time zone"
  defp pg_type("timestamp without time zone", _, _), do: "timestamp without time zone"
  defp pg_type("real", _, _), do: "real"
  defp pg_type("double precision", _, _), do: "double precision"
  defp pg_type("numeric", _, _), do: "numeric"
  defp pg_type("jsonb", _, _), do: "jsonb"
  defp pg_type("json", _, _), do: "jsonb"

  defp pg_type(other, udt, table) do
    raise "unmapped Postgres type #{inspect(other)} (udt: #{inspect(udt)}) on table #{inspect(table)}"
  end

  # ── import.sql ─────────────────────────────────────────────────────────────

  defp render_import(specs) do
    copy_lines = Enum.map_join(specs, "", &"\\copy #{&1.name} from 'db/#{&1.name}'\n")

    """
    -- This script imports the Kaguya public DB dump into a PostgreSQL database.
    --
    -- Usage:
    --   createdb kaguya_dump
    --   psql -d kaguya_dump -f import.sql
    --
    -- The imported DB has only PRIMARY KEYs; other indexes are not recreated.
    -- Foreign keys are added at the end as a consistency check; comment out
    -- that block if you don't need it.

    \\i schema.sql

    -- You can comment out tables you don't need to speed up the import.
    #{copy_lines}
    -- Foreign keys (consistency check; safe to comment out).
    #{render_fk_constraints(specs)}
    """
  end

  defp render_fk_constraints(specs) do
    included = MapSet.new(specs, & &1.name)

    specs
    |> Enum.flat_map(fn %Spec{name: from, foreign_keys: fks} ->
      Enum.map(fks, fn {col, ref_t, ref_col} -> {from, col, ref_t, ref_col} end)
    end)
    |> Enum.filter(fn {_, _, ref_t, _} -> MapSet.member?(included, ref_t) end)
    |> Enum.map_join("\n", fn {t, col, ref_t, ref_col} ->
      "ALTER TABLE #{t} ADD CONSTRAINT #{t}_#{col}_fkey FOREIGN KEY (#{col}) REFERENCES #{ref_t} (#{ref_col});"
    end)
  end
end

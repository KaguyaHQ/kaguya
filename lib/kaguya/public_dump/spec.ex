defmodule Kaguya.PublicDump.Spec do
  @moduledoc """
  A single table specification for the public dump.

  Each entry in `Kaguya.PublicDump.Tables.all/0` is a `%Spec{}`. The pipeline
  reads these to drive COPY queries (`SqlBuilder`), schema generation
  (`SchemaWriter`), and the foreign-key block in `import.sql`.

  ## Regular vs synthesized tables

  Regular tables set `:columns`, `:primary_key`, and optionally `:where`. The
  pipeline builds `COPY (SELECT … FROM <name> x [JOINs] [WHERE …] ORDER BY …)
  TO STDOUT`. `:order_by` defaults to `:primary_key` if not given (the common
  case); set it explicitly only when you need a different sort order than the
  PK columns (e.g., `producer_external_links` adds `value` to the sort to
  break ties on `(producer_id, site)`).

  Synthesized tables (e.g., `:entry_meta`) set `:sql` to a complete SELECT —
  no `:where` / `:order_by` (the SELECT itself carries them). The query is
  wrapped in `COPY (...) TO STDOUT` verbatim.
  """

  @typedoc """
  Column entry. A bare atom is pass-through; `{name, transform}` applies a
  transform during COPY rendering:

    * `{name, :date}` — `x.col::date` (truncates `timestamptz` to day,
      matching VNDB's privacy convention)
    * `{name, :user_fk}` — LEFT JOIN `users`; emits `CASE WHEN username IS
      NULL THEN NULL ELSE id END` (NULLs the FK for deleted users)
  """
  @type column :: atom() | {atom(), :date} | {atom(), :user_fk}

  @typedoc """
  Foreign-key declaration owned by *this* table — `{column_in_this_table,
  ref_table, ref_column}`. Used by `SchemaWriter` to emit `ALTER TABLE …
  ADD CONSTRAINT … FOREIGN KEY` lines in `import.sql`. FKs whose `ref_table`
  isn't itself in the dump are skipped automatically.
  """
  @type foreign_key :: {atom(), atom(), atom()}

  @type t :: %__MODULE__{
          name: atom(),
          source_name: atom() | nil,
          primary_key: String.t() | nil,
          columns: [column()],
          where: String.t() | nil,
          order_by: String.t() | nil,
          sql: String.t() | nil,
          foreign_keys: [foreign_key()]
        }

  @enforce_keys [:name, :columns]
  defstruct [
    :name,
    :source_name,
    :primary_key,
    :columns,
    :where,
    :order_by,
    :sql,
    foreign_keys: []
  ]
end

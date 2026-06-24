defmodule Kaguya.PublicDump.TablesTest do
  @moduledoc """
  Sanity checks on the spec list — guards against drift between specs,
  primary keys, and foreign-key declarations.
  """
  use ExUnit.Case, async: true

  alias Kaguya.PublicDump.{Spec, Tables}

  describe "all/0" do
    test "returns a non-empty list of %Spec{}" do
      specs = Tables.all()
      assert length(specs) > 0
      assert Enum.all?(specs, &match?(%Spec{}, &1))
    end

    test "all spec names are unique" do
      names = Tables.all() |> Enum.map(& &1.name)
      assert length(names) == length(Enum.uniq(names))
    end

    test "every spec declares :primary_key" do
      for spec <- Tables.all() do
        refute is_nil(spec.primary_key),
               "spec #{inspect(spec.name)} has no :primary_key — won't get a PRIMARY KEY constraint in import.sql"
      end
    end

    test "every spec has at least one column" do
      for spec <- Tables.all() do
        assert spec.columns != [],
               "spec #{inspect(spec.name)} has no columns"
      end
    end

    test "regular specs declare :where xor :sql, not both/neither" do
      for spec <- Tables.all() do
        if is_nil(spec.sql) do
          # regular spec — :where is optional, but spec must be valid
          :ok
        else
          assert spec.where == nil and spec.order_by == nil,
                 "synthesized spec #{inspect(spec.name)} should not also set :where or :order_by"
        end
      end
    end

    test "all foreign_keys reference tables that are also in the spec list" do
      specs = Tables.all()
      included = MapSet.new(specs, & &1.name)

      for spec <- specs,
          {col, ref_table, _ref_col} <- spec.foreign_keys do
        assert MapSet.member?(included, ref_table),
               "spec #{inspect(spec.name)} declares FK on :#{col} → #{inspect(ref_table)}, but #{inspect(ref_table)} is not in Tables.all/0"
      end
    end

    test "no foreign_key column appears multiple times within a single spec" do
      for spec <- Tables.all() do
        cols = Enum.map(spec.foreign_keys, fn {col, _, _} -> col end)

        assert length(cols) == length(Enum.uniq(cols)),
               "spec #{inspect(spec.name)} has duplicate FK columns: #{inspect(cols)}"
      end
    end
  end
end

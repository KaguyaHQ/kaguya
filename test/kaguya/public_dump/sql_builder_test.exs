defmodule Kaguya.PublicDump.SqlBuilderTest do
  use ExUnit.Case, async: true

  alias Kaguya.PublicDump.{Spec, SqlBuilder}

  describe "build/1 — synthesized specs" do
    test "wraps :sql verbatim in COPY (...) TO STDOUT" do
      spec = %Spec{
        name: :entry_meta,
        primary_key: "id",
        columns: [:id],
        sql: "SELECT 1 AS id ORDER BY id"
      }

      assert SqlBuilder.build(spec) == """
             COPY (
             SELECT 1 AS id ORDER BY id
             ) TO STDOUT\
             """
    end

    test "trims trailing whitespace from :sql before wrapping" do
      spec = %Spec{
        name: :entry_meta,
        primary_key: "id",
        columns: [:id],
        sql: "SELECT 1 ORDER BY 1\n\n"
      }

      built = SqlBuilder.build(spec)
      refute String.contains?(built, "\n\n)"), "trailing newlines should be stripped"
    end
  end

  describe "build/1 — regular specs, column rendering" do
    test "bare atom columns render as x.col" do
      spec = %Spec{
        name: :tags,
        primary_key: "id",
        columns: [:id, :name, :slug]
      }

      assert SqlBuilder.build(spec) == """
             COPY (
             SELECT x.id, x.name, x.slug
               FROM tags x
              ORDER BY id
             ) TO STDOUT\
             """
    end

    test "{:col, :date} renders as x.col::date AS col" do
      spec = %Spec{
        name: :foo,
        primary_key: "id",
        columns: [:id, {:inserted_at, :date}]
      }

      assert SqlBuilder.build(spec) =~ "x.inserted_at::date AS inserted_at"
    end

    test "{:col, :user_fk} adds LEFT JOIN + CASE-NULL-on-deleted" do
      spec = %Spec{
        name: :vn_images,
        primary_key: "id",
        columns: [:id, {:uploaded_by, :user_fk}]
      }

      built = SqlBuilder.build(spec)
      assert built =~ "LEFT JOIN users u_uploaded_by ON u_uploaded_by.id = x.uploaded_by"

      assert built =~
               "CASE WHEN u_uploaded_by.username IS NULL THEN NULL ELSE u_uploaded_by.id END AS uploaded_by"
    end

    test "multiple :user_fk columns each get a unique LEFT JOIN alias" do
      spec = %Spec{
        name: :vn_quotes,
        primary_key: "id",
        columns: [:id, {:uploaded_by, :user_fk}, {:created_by, :user_fk}]
      }

      built = SqlBuilder.build(spec)
      assert built =~ "LEFT JOIN users u_uploaded_by"
      assert built =~ "LEFT JOIN users u_created_by"
    end

    test "raises on unrecognized column transforms" do
      spec = %Spec{
        name: :foo,
        primary_key: "id",
        columns: [{:bad, :nope}]
      }

      assert_raise ArgumentError, ~r/unrecognized column spec/, fn ->
        SqlBuilder.build(spec)
      end
    end
  end

  describe "build/1 — ORDER BY resolution" do
    test ":order_by defaults to :primary_key when not given" do
      spec = %Spec{
        name: :tags,
        primary_key: "id",
        columns: [:id]
      }

      assert SqlBuilder.build(spec) =~ "ORDER BY id"
    end

    test ":order_by overrides :primary_key when both are set" do
      spec = %Spec{
        name: :producer_external_links,
        primary_key: "producer_id, site",
        order_by: "producer_id, site, value",
        columns: [:producer_id, :site, :value]
      }

      assert SqlBuilder.build(spec) =~ "ORDER BY producer_id, site, value"
    end

    test "raises if neither :order_by nor :primary_key is set" do
      spec = %Spec{name: :foo, columns: [:id]}

      assert_raise ArgumentError, ~r/at least one is required/, fn ->
        SqlBuilder.build(spec)
      end
    end
  end

  describe "build/1 — WHERE clause" do
    test "includes WHERE when :where is set" do
      spec = %Spec{
        name: :visual_novels,
        primary_key: "id",
        columns: [:id],
        where: "hidden_at IS NULL"
      }

      assert SqlBuilder.build(spec) =~ "WHERE hidden_at IS NULL"
    end

    test "omits WHERE when :where is nil" do
      spec = %Spec{
        name: :tags,
        primary_key: "id",
        columns: [:id]
      }

      refute SqlBuilder.build(spec) =~ "WHERE"
    end

    test "omits WHERE when :where is an empty string" do
      spec = %Spec{
        name: :tags,
        primary_key: "id",
        columns: [:id],
        where: ""
      }

      refute SqlBuilder.build(spec) =~ "WHERE"
    end
  end
end

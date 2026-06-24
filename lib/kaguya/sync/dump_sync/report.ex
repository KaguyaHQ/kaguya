defmodule Kaguya.Sync.DumpSync.Report do
  @moduledoc """
  Accumulates sync stats (new/updated counts and new entity IDs) during a dump sync run,
  then writes a human-readable report file to `priv/sync_reports/`.

  New IDs can be plain strings or maps with details (slug, title, name, etc.).
  Maps are rendered with all their fields for richer reports.
  """

  @table :dump_sync_report

  def start do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ets.new(@table, [:named_table, :public, :set])
    :ok
  end

  def stop do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ok
  end

  @doc """
  Record counts for a step.

  `new_ids` is a list of either:
  - plain strings (e.g. "v123")
  - maps with details (e.g. %{id: "v123", title: "Title", slug: "slug"})
  """
  def record(step, new_count, updated_count, new_ids \\ []) do
    if :ets.whereis(@table) != :undefined do
      :ets.insert(
        @table,
        {step, %{type: :upsert, new: new_count, updated: updated_count, new_ids: new_ids}}
      )
    end

    :ok
  end

  @doc """
  Record removal counts for a step.

  `details` is a list of maps with removal context, e.g.:
    %{id: "g10 + v119", entity: "VN-tag", reason: "below vote threshold"}
  """
  def record_removal(step, removed_count, details \\ []) do
    if :ets.whereis(@table) != :undefined do
      :ets.insert(@table, {step, %{type: :removal, removed: removed_count, details: details}})
    end

    :ok
  end

  @doc "Write the report to a timestamped file. `step_name` is included in the filename when running a single step."
  def write_report(step_name \\ nil) do
    entries =
      if :ets.whereis(@table) != :undefined do
        :ets.tab2list(@table) |> Enum.sort_by(&elem(&1, 0))
      else
        []
      end

    if entries == [] do
      nil
    else
      content = build_report(entries)
      path = report_path(step_name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      path
    end
  end

  defp report_path(step_name) do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    suffix = if step_name, do: "_#{step_name}", else: ""
    Path.join([File.cwd!(), "priv", "sync_reports", "dump_sync#{suffix}_#{ts}.txt"])
  end

  defp build_report(entries) do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")

    header = """
    ╔══════════════════════════════════════════════════╗
    ║           VNDB Dump Sync Report                  ║
    ║           #{ts}                ║
    ╚══════════════════════════════════════════════════╝

    """

    {upserts, removals} =
      Enum.split_with(entries, fn {_step, data} -> Map.get(data, :type, :upsert) == :upsert end)

    # Upsert summary
    upsert_section =
      if upserts != [] do
        summary =
          upserts
          |> Enum.map_join("\n", fn {step, data} ->
            n = Map.get(data, :new, 0)
            u = Map.get(data, :updated, 0)
            total = n + u

            "  #{pad_step(step)} │ #{pad_num(total)} total │ #{pad_num(n)} new │ #{pad_num(u)} updated"
          end)

        new_ids_sections =
          upserts
          |> Enum.filter(fn {_step, data} -> Map.get(data, :new_ids, []) != [] end)
          |> Enum.map_join("", fn {step, %{new_ids: ids}} ->
            """

            ── New #{step} (#{length(ids)}) ──────────────────────────────────
            #{format_new_ids(ids)}
            """
          end)

        "Summary\n" <>
          "  ─────────────────────────────────────────────────\n" <>
          summary <> "\n" <> new_ids_sections
      else
        ""
      end

    # Removals summary
    removal_section =
      if removals != [] do
        summary =
          removals
          |> Enum.map_join("\n", fn {step, %{removed: n}} ->
            "  #{pad_step(step)} │ #{pad_num(n)} removed"
          end)

        detail_sections =
          removals
          |> Enum.filter(fn {_step, %{details: d}} -> d != [] end)
          |> Enum.map_join("", fn {step, %{removed: n, details: details}} ->
            """

            ── Removed #{step} (#{n}) ──────────────────────────────────
            #{format_new_ids(details)}
            """
          end)

        "\nRemovals\n" <>
          "  ─────────────────────────────────────────────────\n" <>
          summary <> "\n" <> detail_sections
      else
        ""
      end

    header <> upsert_section <> removal_section
  end

  # Format new IDs — maps get rich multi-field rendering, strings stay simple
  defp format_new_ids([%{} | _] = ids) do
    ids
    |> Enum.sort_by(&Map.get(&1, :id, ""))
    |> Enum.map_join("\n", &format_map_entry/1)
  end

  defp format_new_ids(ids) do
    ids |> Enum.sort() |> Enum.map_join("\n", &"  #{&1}")
  end

  defp format_map_entry(map) do
    id = Map.get(map, :id, "?")
    rest = map |> Map.drop([:id]) |> Enum.sort_by(&elem(&1, 0))

    details =
      Enum.map_join(rest, "  ", fn {k, v} ->
        "#{k}: #{v || "—"}"
      end)

    "  #{id}  #{details}"
  end

  defp pad_step(step), do: step |> to_string() |> String.pad_trailing(18)
  defp pad_num(n), do: n |> to_string() |> String.pad_leading(7)
end

defmodule KaguyaWeb.StaticAssetCacheTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "runtime code does not hard-code bare JS asset paths" do
    files =
      [
        Path.join(@root, "lib"),
        Path.join(@root, "assets/js")
      ]
      |> Enum.flat_map(&runtime_files/1)

    offenders =
      files
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _line_number} -> bare_js_asset_path?(line) end)
        |> Enum.map(fn {_line, line_number} ->
          Path.relative_to(file, @root) <> ":" <> Integer.to_string(line_number)
        end)
      end)

    assert offenders == [],
           "bare /assets/js paths bypass Phoenix digests; use ~p in HEEx and pass the URL through data-* attributes:\n" <>
             Enum.join(offenders, "\n")
  end

  defp runtime_files(path) do
    path
    |> Path.join("**/*.{ex,heex,js}")
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, "/node_modules/"))
  end

  defp bare_js_asset_path?(line) do
    has_asset_path? =
      String.contains?(line, ~s("/assets/js/)) or String.contains?(line, ~s('/assets/js/))

    verified_route? =
      String.contains?(line, ~s(~p"/assets/js/)) or String.contains?(line, ~s(~p'/assets/js/))

    has_asset_path? and not verified_route?
  end
end

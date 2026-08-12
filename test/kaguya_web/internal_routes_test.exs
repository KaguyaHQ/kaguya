defmodule KaguyaWeb.InternalRoutesTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.NotFoundController
  alias KaguyaWeb.Router

  @literal_internal_link ~r/\b(?:href|navigate|patch)="(?<path>\/[^"{}]*)"/

  test "literal internal links resolve to registered GET routes" do
    dead_links =
      ["lib/kaguya_web/**/*.ex", "lib/kaguya_web/**/*.heex"]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.flat_map(&literal_links/1)
      |> Enum.reject(fn {_file, path} -> routable?(path) end)

    assert dead_links == [], format_dead_links(dead_links)
  end

  defp literal_links(file) do
    file
    |> File.read!()
    |> then(&Regex.scan(@literal_internal_link, &1, capture: :all_names))
    |> Enum.map(fn [path] -> {file, path} end)
  end

  defp routable?(raw_path) do
    path = URI.parse(raw_path).path

    case Phoenix.Router.route_info(Router, "GET", path, "kaguya.io") do
      %{plug: NotFoundController} -> false
      %{} -> true
      :error -> false
    end
  end

  defp format_dead_links([]), do: ""

  defp format_dead_links(dead_links) do
    details = Enum.map_join(dead_links, "\n", fn {file, path} -> "  #{file}: #{path}" end)
    "Expected every literal internal link to resolve:\n#{details}"
  end
end

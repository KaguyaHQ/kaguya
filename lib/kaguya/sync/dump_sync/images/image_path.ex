defmodule Kaguya.Sync.DumpSync.Images.ImagePath do
  @moduledoc """
  Shared utility for converting VNDB image IDs to file paths.

  VNDB stores images in directories bucketed by `num % 100` (zero-padded):
    cv12345 → cv/45/12345.jpg
    ch6789  → ch/89/6789.jpg
    sf976   → sf/76/976.jpg
  """

  @doc "Convert a VNDB image ID to its relative file path."
  def to_relative_path("cv" <> num_str) do
    num = String.to_integer(num_str)
    "cv/#{padded_dir(num)}/#{num}.jpg"
  end

  def to_relative_path("ch" <> num_str) do
    num = String.to_integer(num_str)
    "ch/#{padded_dir(num)}/#{num}.jpg"
  end

  def to_relative_path("sf" <> num_str) do
    num = String.to_integer(num_str)
    "sf/#{padded_dir(num)}/#{num}.jpg"
  end

  @doc "Convert a VNDB image ID to an absolute file path under `base_dir`."
  def absolute_path(base_dir, vndb_id) do
    Path.join(base_dir, to_relative_path(vndb_id))
  end

  defp padded_dir(num) when is_integer(num) do
    num
    |> rem(100)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end

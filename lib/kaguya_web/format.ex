defmodule KaguyaWeb.Format do
  @moduledoc """
  Shared formatting helpers for user-visible values.
  """

  @doc """
  Formats a number as a comma-grouped integer.
  """
  def integer(nil), do: "0"

  def integer(value) when is_integer(value) do
    sign = if value < 0, do: "-", else: ""

    grouped =
      value
      |> abs()
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&(Enum.reverse(&1) |> Enum.join("")))
      |> Enum.reverse()
      |> Enum.join(",")

    sign <> grouped
  end

  def integer(value) when is_float(value), do: value |> round() |> integer()
  def integer(value), do: to_string(value)
end
